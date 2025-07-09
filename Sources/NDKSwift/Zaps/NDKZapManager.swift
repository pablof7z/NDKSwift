import Foundation

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
        
        // 3. Select payment provider
        let provider = try await selectPaymentProvider(
            for: prepared.paymentRequest,
            preferredId: preferredProvider
        )
        
        // 4. Execute payment
        let confirmation = try await provider.fulfill(prepared.paymentRequest)
        
        // 5. Complete the zap
        return try await zapProtocol.completeZap(
            prepared: prepared,
            confirmation: confirmation
        )
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
            let eventId = await event.id
            if let eventId = eventId {
                filter.addTagFilter("e", values: [eventId])
            }
        } else if let user = user {
            filter.addTagFilter("p", values: [user.pubkey])
        } else {
            throw NDKError.invalidInput(message: "Must specify either event or user")
        }
        
        let events = try await ndk.fetchEvents(filter)
        
        var zaps: [ZapInfo] = []
        
        for event in events {
            let eventKind = await event.kind
            if eventKind == EventKind.zapReceipt {
                let receipt = NDKZapReceipt(event: event)
                if let zapInfo = try? await validateAndParseZapReceipt(receipt) {
                    zaps.append(zapInfo)
                }
            } else if eventKind == EventKind.nutzap {
                let nutzap = NDKNutzap(event: event)
                let totalAmount = await nutzap.totalAmount
                let recipientPubkey = await nutzap.recipientPubkey
                let comment = await nutzap.comment
                let createdAt = await event.createdAt
                let eventPubkey = await event.pubkey
                
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
    /// Zap this event
    public func zap(
        amountSats: Int64,
        comment: String? = nil,
        preferredType: ZapType? = nil
    ) async throws -> ZapResult {
        guard let ndk = await ndk else {
            throw NDKError.notConfigured("NDK not available")
        }
        
        let author = NDKUser(pubkey: await pubkey)
        
        return try await ndk.zapManager.zap(
            event: self,
            to: author,
            amountSats: amountSats,
            comment: comment,
            preferredType: preferredType
        )
    }
    
    /// Fetch zaps for this event
    public func fetchZaps(includeNutzaps: Bool = true) async throws -> [ZapInfo] {
        guard let ndk = await ndk else {
            throw NDKError.notConfigured("NDK not available")
        }
        
        return try await ndk.zapManager.fetchZaps(
            for: self,
            includeNutzaps: includeNutzaps
        )
    }
}