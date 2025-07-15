import Foundation
import CashuSwift

// MARK: - NIP-60 Token Event Structure

/// Structure for NIP-60 token event content
public struct NIP60TokenEvent: Codable {
    public let mint: String
    public let proofs: [CashuSwift.Proof]
    public let del: [String]?  // Array of deleted event IDs
    
    public init(mint: String, proofs: [CashuSwift.Proof], del: [String]? = nil) {
        self.mint = mint
        self.proofs = proofs
        self.del = del
    }
}

// MARK: - NDKCashuTokenEvent

/// NIP-60 Cashu Token Event (kind: 7375)
/// Encrypted event that stores Cashu proofs for a wallet
public struct NDKCashuTokenEvent {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create and publish a new token event
    /// - Parameters:
    ///   - ndk: NDK instance
    ///   - token: Cashu token containing proofs
    ///   - signer: Signer for encryption and signing
    ///   - deletedEventIds: IDs of token events being replaced
    /// - Returns: The published token event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        token: CashuSwift.Token,
        signer: NDKSigner,
        deletedEventIds: [String]? = nil
    ) async throws -> NDKCashuTokenEvent {
        let tokenEvent = try await create(
            ndk: ndk,
            token: token,
            signer: signer,
            deletedEventIds: deletedEventIds
        )
        
        let publishedRelays = try await ndk.publish(tokenEvent.event)
        print("NDKCashuTokenEvent - Published to \(publishedRelays.count) relays")
        
        return tokenEvent
    }
    
    /// Create without publishing
    public static func create(
        ndk: NDK,
        token: CashuSwift.Token,
        signer: NDKSigner,
        deletedEventIds: [String]? = nil
    ) async throws -> NDKCashuTokenEvent {
        guard let mintURL = token.proofsByMint.keys.first else {
            throw NDKError.invalidRequest("Token has no mint URL")
        }
        
        let proofs = token.proofsByMint[mintURL] ?? []
        
        let nip60Token = NIP60TokenEvent(
            mint: mintURL,
            proofs: proofs,
            del: deletedEventIds
        )
        
        let tokenData = try JSONEncoder().encode(nip60Token)
        guard let plaintext = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token data")
        }
        
        let tokenEvent = try await NDKEventBuilder()
            .content(plaintext)
            .kind(EventKind.cashuToken)
            .encrypt(signer: signer, scheme: .nip44)
        
        return NDKCashuTokenEvent(event: tokenEvent)
    }
}

// MARK: - NDKCashuQuoteEvent

/// NIP-60 Cashu Quote Event (kind: 7374)
/// Encrypted event that stores mint quotes for deposits
public struct NDKCashuQuoteEvent {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create and publish a new quote event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        quote: CashuMintQuote,
        signer: NDKSigner
    ) async throws -> NDKCashuQuoteEvent {
        let quoteEvent = try await create(
            ndk: ndk,
            quote: quote,
            signer: signer
        )
        
        try await ndk.publish(quoteEvent.event)
        print("NDKCashuQuoteEvent - Published quote event: \(quoteEvent.event.id)")
        
        return quoteEvent
    }
    
    /// Create without publishing
    public static func create(
        ndk: NDK,
        quote: CashuMintQuote,
        signer: NDKSigner
    ) async throws -> NDKCashuQuoteEvent {
        let quoteData = try JSONEncoder().encode(quote)
        guard let plaintext = String(data: quoteData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode quote data")
        }
        
        let quoteEvent = try await NDKEventBuilder()
            .content(plaintext)
            .kind(EventKind.cashuQuote)
            .encrypt(signer: signer, scheme: .nip44)
        
        return NDKCashuQuoteEvent(event: quoteEvent)
    }
}

// MARK: - NDKCashuWalletEvent

/// NIP-60 Cashu Wallet Configuration Event (kind: 17375)
/// Stores wallet configuration including mints, relays, and P2PK keys
public struct NDKCashuWalletEvent {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create and publish a wallet configuration event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mints: [String],
        relays: [String]? = nil,
        p2pkPrivateKey: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuWalletEvent {
        let walletEvent = try await create(
            ndk: ndk,
            mints: mints,
            relays: relays,
            p2pkPrivateKey: p2pkPrivateKey,
            signer: signer
        )
        
        print("NDKCashuWalletEvent - Publishing wallet configuration event: \(walletEvent.event.id)")
        print("NDKCashuWalletEvent - Event kind: \(walletEvent.event.kind)")
        print("NDKCashuWalletEvent - Event tags: \(walletEvent.event.tags)")
        print("NDKCashuWalletEvent - Event author: \(walletEvent.event.pubkey)")
        
        do {
            let publishedRelays = try await ndk.publish(walletEvent.event)
            print("NDKCashuWalletEvent - Successfully published wallet configuration to \(publishedRelays.count) relays: \(publishedRelays)")
        } catch {
            print("NDKCashuWalletEvent - ERROR: Failed to publish wallet event: \(error)")
            throw error
        }
        
        return walletEvent
    }
    
    /// Create without publishing
    public static func create(
        ndk: NDK,
        mints: [String],
        relays: [String]? = nil,
        p2pkPrivateKey: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuWalletEvent {
        var walletTags: [[String]] = []
        
        // Add mint tags
        for mint in mints {
            walletTags.append(["mint", mint])
        }
        
        // Add P2PK private key if provided
        if let privkey = p2pkPrivateKey {
            walletTags.append(["privkey", privkey])
        }
        
        // Encrypt wallet configuration
        let walletDataJSON = try JSONEncoder().encode(walletTags)
        guard let plaintext = String(data: walletDataJSON, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode wallet data")
        }
        
        let builder = NDKEventBuilder()
            .content(plaintext)
            .kind(EventKind.cashuWalletConfig)
        
        // Add relay tags (unencrypted according to NIP-60)
        if let relays = relays {
            for relay in relays {
                _ = builder.tag(["relay", relay])
            }
        }
        
        let walletEvent = try await builder.encrypt(signer: signer, scheme: .nip44)
        
        return NDKCashuWalletEvent(event: walletEvent)
    }
    
    /// The mints configured in this wallet event
    public func mints(signer: NDKSigner) async throws -> [String] {
        let tags = try await decryptedTags(signer: signer)
        return tags
            .filter { $0.first == "mint" && $0.count > 1 }
            .map { $0[1] }
    }
    
    /// The P2PK private key configured in this wallet event
    public func privateKey(signer: NDKSigner) async throws -> String? {
        let tags = try await decryptedTags(signer: signer)
        return tags.first(where: { $0.first == "privkey" && $0.count > 1 })?[1]
    }
    
    /// The relays configured in this wallet event (unencrypted)
    public var relays: [String] {
        event.tags
            .filter { $0.first == "relay" && $0.count > 1 }
            .map { $0[1] }
    }
    
    // MARK: - Private Helpers
    
    private func decryptedTags(signer: NDKSigner) async throws -> [[String]] {
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        guard let tagsData = decryptedContent.data(using: .utf8),
              let walletTags = try? JSONDecoder().decode([[String]].self, from: tagsData) else {
            throw NDKError.invalidContent("Failed to parse wallet configuration")
        }
        
        return walletTags
    }
}

// MARK: - NDKCashuSpendingHistory

/// NIP-60 Cashu Spending History Event (kind: 7376)
/// Encrypted event that tracks wallet spending history
public struct NDKCashuSpendingHistory {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create and publish a spending history event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        direction: SpendingDirection,
        amount: Int64,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuSpendingHistory {
        let historyEvent = try await create(
            ndk: ndk,
            direction: direction,
            amount: amount,
            destroyedEventIds: destroyedEventIds,
            createdEventIds: createdEventIds,
            redeemedEventId: redeemedEventId,
            signer: signer
        )
        
        try await ndk.publish(historyEvent.event)
        print("NDKCashuSpendingHistory - Created spending history event")
        
        return historyEvent
    }
    
    /// Create without publishing
    public static func create(
        ndk: NDK,
        direction: SpendingDirection,
        amount: Int64,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuSpendingHistory {
        var encryptedTags: [[String]] = []
        encryptedTags.append(["direction", direction.rawValue])
        encryptedTags.append(["amount", String(amount)])
        
        if let createdIds = createdEventIds {
            for eventId in createdIds {
                encryptedTags.append(["e", eventId, "", "created"])
            }
        }
        
        if let destroyedIds = destroyedEventIds {
            for eventId in destroyedIds {
                encryptedTags.append(["e", eventId, "", "destroyed"])
            }
        }
        
        var clearTags: [[String]] = []
        
        if let redeemedId = redeemedEventId {
            clearTags.append(["e", redeemedId, "", "redeemed"])
        }
        
        let tagsData = try JSONEncoder().encode(encryptedTags)
        guard let plaintext = String(data: tagsData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode spending history")
        }
        
        let historyEvent = try await NDKEventBuilder()
            .content(plaintext)
            .kind(EventKind.cashuSpendingHistory)
            .tags(clearTags)
            .encrypt(signer: signer, scheme: .nip44)
        
        return NDKCashuSpendingHistory(event: historyEvent)
    }
}

// MARK: - NDKCashuMintList

/// NIP-60 Cashu Mint List Event (kind: 10019)
/// Public event that advertises which mints a user accepts for nutzaps
public struct NDKCashuMintList {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create and publish a mint list event
    /// - Parameters:
    ///   - ndk: NDK instance
    ///   - mints: List of mint URLs to advertise
    ///   - signer: Signer for signing the event
    /// - Returns: The published mint list event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mints: [String],
        signer: NDKSigner
    ) async throws -> NDKCashuMintList {
        let mintList = try await create(
            ndk: ndk,
            mints: mints,
            signer: signer
        )
        
        print("NDKCashuMintList - Publishing mint list event with \(mints.count) mints")
        let publishedRelays = try await ndk.publish(mintList.event)
        print("NDKCashuMintList - Published to \(publishedRelays.count) relays")
        
        return mintList
    }
    
    /// Create without publishing
    public static func create(
        ndk: NDK,
        mints: [String],
        signer: NDKSigner
    ) async throws -> NDKCashuMintList {
        let builder = NDKEventBuilder()
            .kind(10019)  // NIP-60 mint list kind
        
        // Add mint tags
        for mint in mints {
            _ = builder.tag(["mint", mint])
        }
        
        let mintListEvent = try await builder.build(signer: signer)
        return NDKCashuMintList(event: mintListEvent)
    }
    
    /// The mints advertised in this mint list event
    public var mints: [String] {
        event.tags
            .filter { $0.first == "mint" && $0.count > 1 }
            .map { $0[1] }
    }
}