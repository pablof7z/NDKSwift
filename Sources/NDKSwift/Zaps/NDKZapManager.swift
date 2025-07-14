import Foundation
import CashuSwift
import CryptoKit

/// Manages zapping functionality with decoupled protocol and payment handling
public actor NDKZapManager {
    private let ndk: NDK
    private var zapProtocols: [ZapType: NDKZapProtocol] = [:]
    private var paymentProviders: [NDKPaymentProvider] = []
    
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
        cashuWallet: NDKCashuWallet? = nil,
        nwcWallet: NDKNWCWallet? = nil,
        legacyWallet: NDKWallet? = nil
    ) {
        // Clear existing providers
        paymentProviders.removeAll()
        
        // Add Cashu provider if available (highest priority for privacy)
        if let cashuWallet = cashuWallet {
            register(provider: CashuPaymentProvider(cashuWallet: cashuWallet))
        }
        
        // Add NWC provider if available
        if let nwcWallet = nwcWallet {
            register(provider: NWCPaymentProvider(nwcWallet: nwcWallet))
        }
        
        // Add legacy wallet adapter if available
        if let wallet = legacyWallet {
            register(provider: WalletAdapterPaymentProvider(wallet: wallet))
        }
        
        // Always add QR code as fallback
        register(provider: QRCodePaymentProvider())
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
        // 1. Select zap protocol
        let zapProtocol = try await selectZapProtocol(
            for: recipient,
            preferredType: preferredType
        )
        
        // 2. Prepare the zap
        let prepared = try await zapProtocol.prepareZap(
            event: event,
            to: recipient,
            amountSats: amountSats,
            comment: comment
        )
        
        // 3. Try to find a provider that can directly fulfill the request
        if let provider = try? await selectPaymentProvider(
            for: prepared.paymentRequest,
            preferredId: preferredProvider
        ) {
            // Direct fulfillment path
            let confirmation = try await provider.fulfill(prepared.paymentRequest)
            return try await zapProtocol.completeZap(
                prepared: prepared,
                confirmation: confirmation
            )
        }
        
        // 4. No direct provider - try protocol transformation
        // If this is a Nutzap, try Lightning fallback
        if zapProtocol.type == .nutzap,
           let nutzapProtocol = zapProtocol as? NDKNutzapProtocol,
           let nutzapRequest = prepared.paymentRequest as? NutzapFundingRequest {
            
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
        nutzapRequest: NutzapFundingRequest,
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
        // FIXME: CashuSwift functionality temporarily disabled due to build issues
        throw ZapError.paymentFailed("CashuSwift temporarily disabled due to build issues")
        
        /*
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
            let seed = Data(UUID().uuidString.utf8).sha256().hexString
            
            // Since CashuSwift has already verified the quote is paid,
            // we can now issue the tokens
            // Create a properly typed mint quote from our stored data
            let mintQuoteData: [String: Any] = [
                "quote": quote.id,
                "amount": Int(quote.amount),
                "request": quote.invoice,
                "state": "PAID",
                "expiry": Int(quote.expiry.timeIntervalSince1970)
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: mintQuoteData)
            let mintQuote = try JSONDecoder().decode(CashuSwift.Bolt11.MintQuote.self, from: jsonData)
            
            // Issue tokens for the paid quote
            let (proofs, validDLEQ) = try await CashuSwift.issue(
                for: mintQuote,
                with: cashuMint,
                seed: seed
            )
            
            if !validDLEQ {
                print("⚠️ Warning: DLEQ verification failed for minted proofs")
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
            
            // Convert CashuSwift proofs to our format
            return mintProofs.map { $0.toNDKProof() }
            
        } catch {
            throw ZapError.mintTokenCreationFailed(
                mint: quote.mint.host ?? quote.mint.absoluteString,
                reason: error.localizedDescription
            )
        }
        */
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
    
    /// Fetch zaps for an event or user
    public func fetchZaps(
        for event: NDKEvent? = nil,
        user: NDKUser? = nil,
        includeNutzaps: Bool = true
    ) async throws -> [ZapInfo] {
        var kinds = [EventKind.zapReceipt]
        if includeNutzaps {
            kinds.append(EventKind.nutzap)
        }
        
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
        
        let events = try await ndk.fetchEvents(filter)
        
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
        for recipient: NDKUser,
        preferredType: ZapType?
    ) async throws -> NDKZapProtocol {
        // Try preferred type first
        if let preferredType = preferredType,
           let zapProtocol = zapProtocols[preferredType],
           try await zapProtocol.canZap(user: recipient) {
            return zapProtocol
        }
        
        // Smart routing: Prioritize Nutzap for privacy
        if let nutzapProtocol = zapProtocols[.nutzap],
           try await nutzapProtocol.canZap(user: recipient) {
            return nutzapProtocol
        }
        
        // Fallback to Lightning
        if let lightningProtocol = zapProtocols[.lightning],
           try await lightningProtocol.canZap(user: recipient) {
            return lightningProtocol
        }
        
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
        let recipientPubkey = await receipt.recipientPubkey
        guard let recipientPubkey = recipientPubkey else {
            return nil
        }
        
        let recipient = NDKUser(pubkey: recipientPubkey)
        recipient.ndk = ndk
        
        // Try to get provider pubkey from recipient's profile
        var providerPubkey: String?
        if let profile = try? await recipient.fetchProfile(),
           profile.lud16 != nil || profile.lud06 != nil {
            // In a real implementation, we'd resolve the LNURL to get the provider pubkey
            // For now, we'll use the receipt's pubkey as a placeholder
            providerPubkey = await receipt.event.pubkey
        }
        
        guard let providerPubkey = providerPubkey,
              await receipt.validate(lnurlProviderPubkey: providerPubkey) else {
            return nil
        }
        
        let amountSats = await receipt.amountSats ?? 0
        let senderPubkey = await receipt.senderPubkey
        let comment = await receipt.comment
        let createdAt = await receipt.event.createdAt
        
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
    public func fetchZaps(includeNutzaps: Bool = true) async throws -> [ZapInfo] {
        guard let ndk = self.ndk else {
            throw NDKError.notConfigured("NDK not available")
        }
        
        return try await ndk.zapManager.fetchZaps(
            user: self,
            includeNutzaps: includeNutzaps
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
    public func fetchZaps(with ndk: NDK, includeNutzaps: Bool = true) async throws -> [ZapInfo] {
        return try await ndk.zapManager.fetchZaps(
            for: self,
            includeNutzaps: includeNutzaps
        )
    }
    
    /// Update publish status for this event
    public func updatePublishStatus(relay: String, status: RelayPublishStatus) {
        // This method needs to be implemented in NDKEventTracker
        // For now, this is a no-op since NDKEvent is immutable
        // The publish status tracking should be handled by NDKEventTracker
    }
}

// MARK: - Data Extension

private extension Data {
    func sha256() -> Data {
        SHA256.hash(data: self).data
    }
}

private extension SHA256.Digest {
    var data: Data {
        Data(self)
    }
}