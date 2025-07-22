import Foundation
import CryptoKit

import CashuSwift

/// Manages zapping functionality with decoupled protocol and payment handling
public actor NDKZapManager {
    private let ndk: NDK
    private var zapProtocols: [ZapType: NDKZapProtocol] = [:]
    private var paymentProviders: [NDKPaymentProvider] = []
    
    // Cache for recipient zap info (pubkey -> info)
    private var recipientInfoCache: [String: RecipientZapInfo] = [:]
    // Track in-flight fetches to prevent duplicate requests
    private var fetchTasks: [String: Task<RecipientZapInfo, Never>] = [:]
    
    public init(ndk: NDK) {
        self.ndk = ndk
        
        // Register default protocols
        zapProtocols[.lightning] = NDKLightningZapProtocol(ndk: ndk)
        zapProtocols[.nutzap] = NDKNutzapProtocol(ndk: ndk)
    }
    
    // MARK: - Protocol Management
    
    /// Register a zap protocol
    public func register(protocol zapProtocol: NDKZapProtocol) {
        zapProtocols[zapProtocol.type] = zapProtocol
    }
    
    // MARK: - Payment Provider Management
    
    /// Register a payment provider
    public func register(provider: NDKPaymentProvider) {
        paymentProviders.append(provider)
    }
    
    /// Remove a payment provider
    public func unregister(providerId: String) {
        paymentProviders.removeAll { $0.id == providerId }
    }
    
    /// Configure with default providers based on available wallets
    public func configureDefaults(
        cashuWallet: NIP60Wallet? = nil,
        nwcWallet: NDKNWCWallet? = nil
    ) {
        // Clear existing providers
        paymentProviders.removeAll()
        
        // Add Cashu provider if available (highest priority for privacy)
        if let cashuWallet = cashuWallet {
            register(provider: cashuWallet)
        }
        
        // Add NWC provider if available
        if let nwcWallet = nwcWallet {
            register(provider: nwcWallet)
        }
        
        // Always add QR code as fallback
        register(provider: QRCodePaymentProvider())
    }
    
    // MARK: - Recipient Info Management
    
    /// Fetch all zap-related info for a recipient in one go
    private func fetchRecipientZapInfo(for user: NDKUser, maxAge: TimeInterval = TimeConstants.day) async -> RecipientZapInfo {
        let pubkey = user.pubkey
        
        // Check cache first
        if let cached = recipientInfoCache[pubkey], cached.isFresh(maxAge: maxAge) {
            return cached
        }
        
        // Check if there's already a fetch in progress
        if let existingTask = fetchTasks[pubkey] {
            return await existingTask.value
        }
        
        // Create a new fetch task
        let task = Task<RecipientZapInfo, Never> {
            // Create a combined filter for all event types we need
            var filter = NDKFilter()
            filter.authors = [pubkey]
            filter.kinds = [
                EventKind.metadata,           // kind:0 - profile with lightning address
                EventKind.nutzapPreferences  // kind:10019 - nutzap preferences
            ]
            
            // Create data source and collect until EOSE
            let dataSource = NDKDataSource(
                ndk: ndk,
                filter: filter,
                maxAge: maxAge
            )
            
            // Collect all events with a reasonable timeout
            let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionLong)
            
            // Create RecipientZapInfo from fetched events
            let info = await RecipientZapInfo.from(
                pubkey: pubkey,
                events: events
            )
            
            // Cache the result
            recipientInfoCache[pubkey] = info
            
            // Clean up the task reference
            fetchTasks.removeValue(forKey: pubkey)
            
            return info
        }
        
        // Store the task to prevent duplicate fetches
        fetchTasks[pubkey] = task
        
        return await task.value
    }
    
    /// Clear cached recipient info
    public func clearRecipientCache(for pubkey: String? = nil) {
        if let pubkey = pubkey {
            recipientInfoCache.removeValue(forKey: pubkey)
            fetchTasks[pubkey]?.cancel()
            fetchTasks.removeValue(forKey: pubkey)
        } else {
            recipientInfoCache.removeAll()
            for task in fetchTasks.values {
                task.cancel()
            }
            fetchTasks.removeAll()
        }
    }
    
    // MARK: - Zapping
    
    /// Smart zap with automatic protocol and payment provider selection
    public func zap(
        event: NDKEvent? = nil,
        to recipient: NDKUser,
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil,
        preferredProvider: String? = nil
    ) async throws -> ZapResult {
        NDKLogger.log(.debug, category: .wallet, "// 1. Fetch all recipient info ONCE")
        // 1. Fetch all recipient info ONCE
        let recipientInfo = await fetchRecipientZapInfo(for: recipient)
        
        NDKLogger.log(.debug, category: .wallet, "// 2. Select zap protocol based on available options")
        // 2. Select zap protocol based on available options
        let zapProtocol = try selectZapProtocol(
            recipientInfo: recipientInfo,
            preferredType: preferredType
        )
        
        NDKLogger.log(.debug, category: .wallet, "// 3. Prepare the zap with pre-fetched info")
        // 3. Prepare the zap with pre-fetched info
        let prepared = try await zapProtocol.prepareZap(
            event: event,
            recipientInfo: recipientInfo,
            amountSats: amountSats,
            comment: comment
        )
        
        NDKLogger.log(.debug, category: .wallet, "// 3. Try to find a provider that can directly fulfill the request")
        // 3. Try to find a provider that can directly fulfill the request
        if let provider = try? await selectPaymentProvider(
            for: prepared.paymentRequest,
            preferredId: preferredProvider
        ) {
            NDKLogger.log(.debug, category: .wallet, "// Direct fulfillment path")
            // Direct fulfillment path
            let confirmation = try await provider.fulfill(prepared.paymentRequest)
            return try await zapProtocol.completeZap(
                prepared: prepared,
                confirmation: confirmation
            )
        }
        
        NDKLogger.log(.debug, category: .wallet, "// 4. No direct provider - try protocol transformation")
        // 4. No direct provider - try protocol transformation
        // If this is a Nutzap, try Lightning fallback
        if zapProtocol.type == .nutzap,
           let nutzapProtocol = zapProtocol as? NDKNutzapProtocol,
           let nutzapRequest = prepared.paymentRequest as? NutzapPaymentRequest {
            
            // Try Lightning-based funding
            return try await fundNutzapViaLightning(
                nutzapProtocol: nutzapProtocol,
                prepared: prepared,
                nutzapRequest: nutzapRequest,
                preferredProvider: preferredProvider
            )
        }
        
        // 5. No fallback available
        throw ZapError.noWalletConfigured
    }
    
    /// Fund a Nutzap using Lightning payment to mint
    private func fundNutzapViaLightning(
        nutzapProtocol: NDKNutzapProtocol,
        prepared: PreparedZap,
        nutzapRequest: NutzapPaymentRequest,
        preferredProvider: String?
    ) async throws -> ZapResult {
        // Try each accepted mint
        var mintAttempts = 0
        var lastError: Error?
        
        for mintURL in nutzapRequest.acceptedMints {
            mintAttempts += 1
            let mintHost = mintURL.host ?? mintURL.absoluteString
            
            do {
                // Create mint quote
                let quote: MintQuote
                do {
                    quote = try await nutzapProtocol.createMintQuote(
                        invoice: "", // Will be filled by mint
                        mint: mintURL,
                        amount: nutzapRequest.amountSats
                    )
                } catch {
                    lastError = ZapError.mintQuoteFailed(mint: mintHost, reason: error.localizedDescription)
                    continue
                }
                
                // Create Lightning request for the mint's invoice
                let lightningRequest = LightningInvoiceRequest(
                    invoice: quote.invoice,
                    amountSats: quote.amount,
                    recipient: "Mint: \(mintHost)"
                )
                
                // Find a Lightning provider
                guard let lightningProvider = try? await selectPaymentProvider(
                    for: lightningRequest,
                    preferredId: preferredProvider
                ) else {
                    lastError = ZapError.noWalletConfigured
                    continue
                }
                
                // Pay the Lightning invoice
                do {
                    _ = try await lightningProvider.fulfill(lightningRequest)
                } catch {
                    lastError = ZapError.paymentFailed(error.localizedDescription)
                    continue
                }
                
                // Mint tokens using the paid invoice
                let proofs: [CashuSwift.Proof]
                do {
                    proofs = try await mintTokensWithQuote(
                        quote: quote,
                        recipientP2PK: nutzapRequest.recipientP2PK
                    )
                } catch {
                    lastError = ZapError.mintTokenCreationFailed(mint: mintHost, reason: error.localizedDescription)
                    continue
                }
                
                // Create Cashu confirmation
                let cashuConfirmation = CashuPaymentConfirmation(
                    proofs: proofs,
                    change: nil,
                    mintURL: mintURL
                )
                
                // Complete the zap
                return try await nutzapProtocol.completeZap(
                    prepared: prepared,
                    confirmation: cashuConfirmation
                )
                
            } catch {
                // Catch any other errors
                lastError = error
                continue
            }
        }
        
        // All mints failed
        if mintAttempts > 0 {
            throw ZapError.allMintsFailed(attempts: mintAttempts)
        } else {
            throw lastError ?? ZapError.paymentFailed("No mints available")
        }
    }
    
    /// Mint tokens using a paid quote
    private func mintTokensWithQuote(
        quote: MintQuote,
        recipientP2PK: String
    ) async throws -> [CashuSwift.Proof] {
        // Connect to the mint and load keysets
        let cashuMint = try await CashuSwift.loadMint(url: quote.mint)
        
        do {
            // Mint is now loaded with keysets
            
            // First, check if the quote has been paid
            let quoteState = try await CashuSwift.mintQuoteState(
                for: quote.id,
                mint: cashuMint
            )
            
            guard quoteState.state == .paid else {
                throw ZapError.paymentFailed("Lightning invoice not yet paid")
            }
            
            // Generate a seed for deterministic output generation
            let seed = Crypto.randomBytes(count: Crypto.Constants.privateKeySize).hexString
            
            // Since CashuSwift has already verified the quote is paid,
            // we can now issue the tokens
            // Create a properly typed mint quote from our stored data
            let mintQuoteData: [String: Any] = [
                "quote": quote.id,
                "amount": Int(quote.amount),
                "request": quote.invoice,
                "state": "PAID",
                "expiry": Int(Timestamp.from(quote.expiry))
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: mintQuoteData)
            let mintQuote = try JSONCoding.decode(CashuSwift.Bolt11.MintQuote.self, from: jsonData)
            
            // Issue tokens for the paid quote
            let (proofs, validDLEQ) = try await CashuSwift.issue(
                for: mintQuote,
                with: cashuMint,
                seed: seed
            )
            
            if !validDLEQ {
                NDKLogger.log(.warning, category: .general, "⚠️ Warning: DLEQ verification failed for minted proofs")
            }
            
            // Now we need to swap these proofs to P2PK-locked ones
            // Use the CashuSwift send API correctly
            let token = try await CashuSwift.send(
                inputs: proofs,
                mint: cashuMint,
                amount: Int(quote.amount),
                seed: seed,
                lockToPublicKey: recipientP2PK
            )
            
            // Extract the locked proofs from the token
            guard let mintProofs = token.token.proofsByMint[quote.mint.absoluteString] else {
                throw ZapError.mintTokenCreationFailed(
                    mint: quote.mint.host ?? quote.mint.absoluteString,
                    reason: "No proofs returned from mint"
                )
            }
            
            // Return the locked proofs directly
            return mintProofs
            
        } catch {
            throw ZapError.mintTokenCreationFailed(
                mint: quote.mint.host ?? quote.mint.absoluteString,
                reason: error.localizedDescription
            )
        }
    }
    
    /// Get available payment providers for a given payment request
    public func availableProviders(for request: PaymentRequest) async -> [NDKPaymentProvider] {
        var available: [NDKPaymentProvider] = []
        
        for provider in paymentProviders {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                available.append(provider)
            }
        }
        
        return available
    }
    
    /// Subscribe to zaps for an event or user (reactive, event-driven approach)
    /// 
    /// This method returns immediately with an AsyncSequence that yields zaps as they arrive.
    /// Perfect for UIs that should update progressively as zaps are received.
    /// 
    /// - Parameters:
    ///   - event: The event to get zaps for
    ///   - user: The user to get zaps for (if event is nil)
    /// - Returns: AsyncSequence of ZapInfo objects
    /// 
    /// ## Example:
    /// ```swift
    /// for try await zap in zapManager.subscribeToZaps(for: event) {
    ///     // Update UI with each zap as it arrives
    ///     updateZapDisplay(zap)
    /// }
    /// ```
    public func subscribeToZaps(
        for event: NDKEvent? = nil,
        user: NDKUser? = nil
    ) -> AsyncThrowingStream<ZapInfo, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var kinds = [EventKind.zapReceipt]
                    kinds.append(EventKind.nutzap)
                    
                    var filter = NDKFilter()
                    filter.kinds = kinds
                    
                    if let event = event {
                        let eventId = event.id
                        filter.addTagFilter("e", values: [eventId])
                    } else if let user = user {
                        filter.addTagFilter("p", values: [user.pubkey])
                    } else {
                        continuation.finish(throwing: NDKError.invalidInput(message: "Must specify either event or user"))
                        return
                    }
                    
                    // Use NDKDataSource for real-time zap monitoring
                    let dataSource = NDKDataSource(
                        ndk: ndk,
                        filter: filter,
                        maxAge: 0, // Always fresh for real-time zap monitoring
                        cachePolicy: .cacheWithNetwork
                    )
                    
                    for await event in dataSource.events {
                        let eventKind = event.kind
                        if eventKind == EventKind.zapReceipt {
                            let receipt = NDKZapReceipt(event: event)
                            if let zapInfo = try? await self.validateAndParseZapReceipt(receipt) {
                                continuation.yield(zapInfo)
                            }
                        } else if eventKind == EventKind.nutzap {
                            let nutzap = NDKNutzap(event: event)
                            let totalAmount = nutzap.totalAmount
                            
                            let zapInfo = ZapInfo(
                                type: .nutzap,
                                amountSats: Int64(totalAmount),
                                sender: event.pubkey,
                                recipient: nutzap.recipientPubkey ?? "",
                                comment: nutzap.comment,
                                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                                event: event
                            )
                            continuation.yield(zapInfo)
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }
    
    /// Fetch zaps for an event or user (blocking approach)
    /// 
    /// ⚠️ **WARNING**: This blocks until all zaps are received. Consider using `subscribeToZaps` instead
    /// for reactive UIs that should update as zaps arrive.
    /// 
    /// Use this only when you need all zaps before proceeding (e.g., calculating totals for a static report).
    public func fetchZaps(
        for event: NDKEvent? = nil,
        user: NDKUser? = nil
    ) async throws -> [ZapInfo] {
        var kinds = [EventKind.zapReceipt]
        kinds.append(EventKind.nutzap)
        
        var filter = NDKFilter()
        filter.kinds = kinds
        
        if let event = event {
            let eventId = event.id
            filter.addTagFilter("e", values: [eventId])
        } else if let user = user {
            filter.addTagFilter("p", values: [user.pubkey])
        } else {
            throw NDKError.invalidInput(message: "Must specify either event or user")
        }
        
        // Use NDKDataSource for fetching zaps
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: TimeConstants.minute * 5 // 5 minutes - zaps are fairly static once created
        )
        
        // Collect all zap events
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionLong)
        
        var zaps: [ZapInfo] = []
        
        for event in events {
            let eventKind = event.kind
            if eventKind == EventKind.zapReceipt {
                let receipt = NDKZapReceipt(event: event)
                if let zapInfo = try? await validateAndParseZapReceipt(receipt) {
                    zaps.append(zapInfo)
                }
            } else if eventKind == EventKind.nutzap {
                let nutzap = NDKNutzap(event: event)
                let totalAmount = nutzap.totalAmount
                let recipientPubkey = nutzap.recipientPubkey
                let comment = nutzap.comment
                let createdAt = event.createdAt
                let eventPubkey = event.pubkey
                
                zaps.append(ZapInfo(
                    type: .nutzap,
                    amountSats: totalAmount,
                    sender: eventPubkey,
                    recipient: recipientPubkey ?? "",
                    comment: comment,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(createdAt)),
                    event: event
                ))
            }
        }
        
        // Sort by timestamp descending
        return zaps.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Private Methods
    
    private func selectZapProtocol(
        recipientInfo: RecipientZapInfo,
        preferredType: ZapType?
    ) throws -> NDKZapProtocol {
        NDKLogger.log(.debug, category: .wallet, "selectZapProtocol \(String(describing: preferredType)), supported: \(recipientInfo.supportedZapTypes)")
        
        // Try preferred type first if it's supported
        if let preferredType = preferredType,
           recipientInfo.supports(preferredType),
           let zapProtocol = zapProtocols[preferredType] {
            return zapProtocol
        }
        
        // Smart routing: Prioritize Nutzap for privacy
        if recipientInfo.hasNutzapSupport,
           let nutzapProtocol = zapProtocols[.nutzap] {
            return nutzapProtocol
        }
        
        // Fallback to Lightning
        if recipientInfo.hasLightningSupport,
           let lightningProtocol = zapProtocols[.lightning] {
            return lightningProtocol
        }
        NDKLogger.log(.debug, category: .wallet, "recipientDoesNotSupportZaps")
        
        throw ZapError.recipientDoesNotSupportZaps
    }
    
    private func selectPaymentProvider(
        for request: PaymentRequest,
        preferredId: String?
    ) async throws -> NDKPaymentProvider {
        // Try preferred provider first
        if let preferredId = preferredId,
           let provider = paymentProviders.first(where: { $0.id == preferredId }) {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                return provider
            }
        }
        
        // Find first available provider that can fulfill the request
        for provider in paymentProviders {
            let isAvailable = await provider.isAvailable()
            let canFulfill = await provider.canFulfill(request)
            if isAvailable && canFulfill {
                return provider
            }
        }
        
        throw ZapError.noWalletConfigured
    }
    
    private func validateAndParseZapReceipt(_ receipt: NDKZapReceipt) async throws -> ZapInfo? {
        // Get the recipient to fetch their LNURL provider pubkey
        let recipientPubkey = receipt.recipientPubkey
        guard let recipientPubkey = recipientPubkey else {
            return nil
        }
        
        let recipient = NDKUser(pubkey: recipientPubkey)
        recipient.ndk = ndk
        
        // Try to get provider pubkey from recipient's profile
        var providerPubkey: String?
        for await profile in await ndk.profileManager.observe(for: recipientPubkey, maxAge: TimeConstants.hour) {
            if let profile = profile {
                // Try to resolve LNURL to get provider pubkey
                if let lnurlAddress = profile.lud16 ?? profile.lud06 {
                    do {
                        let resolution = try await ndk.lnurlResolver.resolve(lnurlAddress)
                        providerPubkey = resolution.providerPubkey
                        
                        // If no provider pubkey from LNURL, check if service allows Nostr
                        if providerPubkey == nil && resolution.payResponse.allowsNostr == true {
                            // Some services that allow Nostr might use the recipient's pubkey
                            // as the zap receipt signer
                            providerPubkey = receipt.event.pubkey
                        }
                    } catch {
                        NDKLogger.log(.warning, category: .general, 
                                    "Failed to resolve LNURL for \(lnurlAddress): \(error)")
                        // Fall back to using receipt pubkey
                        providerPubkey = receipt.event.pubkey
                    }
                } else {
                    // No LNURL configured, use receipt pubkey
                    providerPubkey = receipt.event.pubkey
                }
            }
            break // Only need first value
        }
        
        guard let providerPubkey = providerPubkey,
              receipt.validate(lnurlProviderPubkey: providerPubkey) else {
            return nil
        }
        
        let amountSats = receipt.amountSats ?? 0
        let senderPubkey = receipt.senderPubkey
        let comment = receipt.comment
        let createdAt = receipt.event.createdAt
        
        return ZapInfo(
            type: .lightning,
            amountSats: amountSats,
            sender: senderPubkey,
            recipient: recipientPubkey,
            comment: comment,
            timestamp: Date(timeIntervalSince1970: TimeInterval(createdAt)),
            event: receipt.event
        )
    }
}

/// Information about a zap
public struct ZapInfo {
    public let type: ZapType
    public let amountSats: Int64
    public let sender: String?
    public let recipient: String
    public let comment: String?
    public let timestamp: Date
    public let event: NDKEvent
}

// MARK: - NDK Extension

extension NDK {
    /// Access the zap manager
    public var zapManager: NDKZapManager {
        if let existing = objc_getAssociatedObject(self, &zapManagerKey) as? NDKZapManager {
            return existing
        }
        
        let manager = NDKZapManager(ndk: self)
        objc_setAssociatedObject(self, &zapManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
    }
}

private var zapManagerKey: UInt8 = 0

// MARK: - User Extension

extension NDKUser {
    /// Zap this user
    public func zap(
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil
    ) async throws -> ZapResult {
        guard let ndk = self.ndk else {
            throw NDKError.notConfigured("NDK not available")
        }
        
        return try await ndk.zapManager.zap(
            to: self,
            amountSats: amountSats,
            comment: comment,
            preferredType: preferredType
        )
    }
    
    /// Fetch zaps sent to this user
    public func fetchZaps() async throws -> [ZapInfo] {
        guard let ndk = self.ndk else {
            throw NDKError.notConfigured("NDK not available")
        }
        
        return try await ndk.zapManager.fetchZaps(
            user: self
        )
    }
}

// MARK: - Event Extension

extension NDKEvent {
    /// Zap this event (requires NDK instance)
    public func zap(
        with ndk: NDK,
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil
    ) async throws -> ZapResult {
        let author = NDKUser(pubkey: pubkey)
        
        return try await ndk.zapManager.zap(
            event: self,
            to: author,
            amountSats: amountSats,
            comment: comment,
            preferredType: preferredType
        )
    }
    
    /// Fetch zaps for this event (requires NDK instance)
    public func fetchZaps(with ndk: NDK) async throws -> [ZapInfo] {
        return try await ndk.zapManager.fetchZaps(
            for: self
        )
    }
}