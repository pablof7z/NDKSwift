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
public struct NDKCashuTokenEvent: NDKPublishableEvent {
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
        return try await EventPublishingHelper.createAndPublish(
            type: NDKCashuTokenEvent.self,
            ndk: ndk,
            logPrefix: "NDKCashuTokenEvent"
        ) {
            try await create(
                ndk: ndk,
                token: token,
                signer: signer,
                deletedEventIds: deletedEventIds
            )
        }
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

        let plaintext = try JSONCoding.encodeToString(nip60Token)

        let tokenEvent = try await NDKEventBuilder(ndk: ndk)
            .content(plaintext)
            .kind(EventKind.cashuToken)
            .encrypt(signer: signer, scheme: .nip44)

        return NDKCashuTokenEvent(event: tokenEvent)
    }
}

// MARK: - NDKCashuQuoteEvent

/// NIP-60 Cashu Quote Event (kind: 7374)
/// Encrypted event that stores mint quotes for deposits
public struct NDKCashuQuoteEvent: NDKPublishableEvent {
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
        return try await EventPublishingHelper.createAndPublishWithId(
            type: NDKCashuQuoteEvent.self,
            ndk: ndk,
            logPrefix: "NDKCashuQuoteEvent - Published quote event"
        ) {
            try await create(
                ndk: ndk,
                quote: quote,
                signer: signer
            )
        }
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        quote: CashuMintQuote,
        signer: NDKSigner
    ) async throws -> NDKCashuQuoteEvent {
        let plaintext = try JSONCoding.encodeToString(quote)

        let quoteEvent = try await NDKEventBuilder(ndk: ndk)
            .content(plaintext)
            .kind(EventKind.cashuQuote)
            .encrypt(signer: signer, scheme: .nip44)

        return NDKCashuQuoteEvent(event: quoteEvent)
    }
}

// MARK: - Decrypted Data Cache

/// Cache for decrypted wallet data to avoid repeated decryption
private actor DecryptedWalletCache {
    private var cache: [EventID: [[String]]] = [:]

    func get(for eventId: EventID) -> [[String]]? {
        return cache[eventId]
    }

    func set(_ tags: [[String]], for eventId: EventID) {
        cache[eventId] = tags
    }
}

// Global cache instance
private let decryptedWalletCache = DecryptedWalletCache()

// MARK: - NDKCashuWalletEvent

/// NIP-60 Cashu Wallet Configuration Event (kind: 17375)
/// Stores wallet configuration including mints, relays, and P2PK keys
public struct NDKCashuWalletEvent: NDKPublishableEvent {
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
        NDKLogger.log(.info, category: .event, "📍 Publishing Kind 17375 wallet configuration event with:")
        NDKLogger.log(.info, category: .event, "📍   - Mints: \(mints)")
        NDKLogger.log(.info, category: .event, "📍   - Relays: \(relays ?? [])")
        NDKLogger.log(.info, category: .event, "📍   - Has P2PK key: \(p2pkPrivateKey != nil)")

        return try await EventPublishingHelper.createAndPublishWithId(
            type: NDKCashuWalletEvent.self,
            ndk: ndk,
            logPrefix: "NDKCashuWalletEvent - Published wallet configuration event"
        ) {
            try await create(
                ndk: ndk,
                mints: mints,
                relays: relays,
                p2pkPrivateKey: p2pkPrivateKey,
                signer: signer
            )
        }
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        mints: [String],
        relays: [String]? = nil,
        p2pkPrivateKey: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuWalletEvent {
        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Creating Kind 17375 wallet configuration event")
        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Input parameters:")
        NDKLogger.log(.debug, category: .event, "🔐   - mints: \(mints)")
        NDKLogger.log(.debug, category: .event, "🔐   - relays: \(relays ?? [])")
        NDKLogger.log(.debug, category: .event, "🔐   - p2pkPrivateKey: \(p2pkPrivateKey?.prefix(8) ?? "nil")...")

        var walletTags: [[String]] = []

        // Add mint tags
        for mint in mints {
            walletTags.append([NostrConstants.TagName.mint, mint])
        }
        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Added mint tags: \(walletTags.filter { $0[0] == NostrConstants.TagName.mint })")

        // Add P2PK private key if provided
        if let privkey = p2pkPrivateKey {
            walletTags.append(["privkey", privkey])
            NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Added P2PK private key tag")
        }

        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Complete encrypted tags structure: \(walletTags)")

        // Encrypt wallet configuration
        let plaintext = try JSONCoding.encodeToString(walletTags)

        let builder = NDKEventBuilder(ndk: ndk)
            .content(plaintext)
            .kind(EventKind.cashuWalletConfig)

        // Add relay tags (unencrypted according to NIP-60)
        if let relays = relays {
            for relay in relays {
                _ = builder.tag([NostrConstants.TagName.relay, relay])
            }
        }

        let walletEvent = try await builder.encrypt(signer: signer, scheme: .nip44)

        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletEvent - Final event details:")
        NDKLogger.log(.debug, category: .event, "🔐   - Event ID: \(walletEvent.id)")
        NDKLogger.log(.debug, category: .event, "🔐   - Event Kind: \(walletEvent.kind)")
        NDKLogger.log(.debug, category: .event, "🔐   - Event Author: \(walletEvent.pubkey)")
        NDKLogger.log(.debug, category: .event, "🔐   - Encrypted content: \(walletEvent.content.prefix(100))...")
        NDKLogger.log(.debug, category: .event, "🔐   - Encrypted content size: \(walletEvent.content.count) characters")
        NDKLogger.log(.debug, category: .event, "🔐   - Unencrypted tags: \(walletEvent.tags)")
        NDKLogger.log(.debug, category: .event, "🔐   - Created at: \(walletEvent.createdAt)")

        return NDKCashuWalletEvent(event: walletEvent)
    }

    /// The mints configured in this wallet event
    public func mints(signer: NDKSigner) async throws -> [String] {
        let tags = try await decryptedTags(signer: signer)
        let mintURLs = tags
            .filter { $0.first == NostrConstants.TagName.mint && $0.count > 1 }
            .map { $0[1] }
        return mintURLs
    }

    /// The P2PK private key configured in this wallet event
    public func privateKey(signer: NDKSigner) async throws -> String? {
        let tags = try await decryptedTags(signer: signer)
        let privateKey = tags.first(where: { $0.first == "privkey" && $0.count > 1 })?[1]
        return privateKey
    }

    /// The relays configured in this wallet event (unencrypted)
    public var relays: [String] {
        return event.tags.compactMap { tag in
            guard tag.first == NostrConstants.TagName.relay, tag.count > 1 else { return nil }
            return tag[1]
        }
    }

    // MARK: - Private Helpers

    private func decryptedTags(signer: NDKSigner) async throws -> [[String]] {
        // Check cache first
        if let cachedTags = await decryptedWalletCache.get(for: event.id) {
            return cachedTags
        }

        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        guard let tagsData = decryptedContent.data(using: .utf8),
              let walletTags = JSONCoding.safeDecode([[String]].self, from: tagsData) else {
            throw NDKError.invalidContent("Failed to parse wallet configuration")
        }

        // Cache the decrypted tags
        await decryptedWalletCache.set(walletTags, for: event.id)

        return walletTags
    }
}

// MARK: - NIP-60 Wallet Backup Event (Kind 375)

/// A backup event for NIP-60 wallets (kind 375)
/// Similar to kind 17375 but includes a public key tag for easy retrieval during restoration
public struct NDKCashuWalletBackupEvent: NDKPublishableEvent {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a wallet backup event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mints: [String],
        relays: [String]? = nil,
        p2pkPrivateKey: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuWalletBackupEvent {
        NDKLogger.log(.info, category: .event, "📦 Creating Kind 375 wallet backup event")

        return try await EventPublishingHelper.createAndPublishWithId(
            type: NDKCashuWalletBackupEvent.self,
            ndk: ndk,
            logPrefix: "NDKCashuWalletBackupEvent - Published backup event"
        ) {
            try await create(
                ndk: ndk,
                mints: mints,
                relays: relays,
                p2pkPrivateKey: p2pkPrivateKey,
                signer: signer
            )
        }
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        mints: [String],
        relays: [String]? = nil,
        p2pkPrivateKey: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuWalletBackupEvent {
        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletBackupEvent - Creating Kind 375 wallet backup event")

        var walletTags: [[String]] = []

        // Add mint tags
        for mint in mints {
            walletTags.append([NostrConstants.TagName.mint, mint])
        }

        // Add P2PK private key if provided
        if let privkey = p2pkPrivateKey {
            walletTags.append(["privkey", privkey])
        }

        // Encrypt wallet configuration
        let plaintext = try JSONCoding.encodeToString(walletTags)

        let userPubkey = try await signer.pubkey

        let builder = NDKEventBuilder(ndk: ndk)
            .content(plaintext)
            .kind(EventKind.cashuWalletBackup)
            .tag(["p", userPubkey])  // Add public key tag for easy retrieval

        // Add relay tags (unencrypted according to NIP-60)
        if let relays = relays {
            for relay in relays {
                _ = builder.tag([NostrConstants.TagName.relay, relay])
            }
        }

        let backupEvent = try await builder.encrypt(signer: signer, scheme: .nip44)

        NDKLogger.log(.debug, category: .event, "🔐 NDKCashuWalletBackupEvent - Final backup event details:")
        NDKLogger.log(.debug, category: .event, "🔐   - Event ID: \(backupEvent.id)")
        NDKLogger.log(.debug, category: .event, "🔐   - Event Kind: \(backupEvent.kind)")
        NDKLogger.log(.debug, category: .event, "🔐   - Event Author: \(backupEvent.pubkey)")
        NDKLogger.log(.debug, category: .event, "🔐   - Tags: \(backupEvent.tags)")

        return NDKCashuWalletBackupEvent(event: backupEvent)
    }

    /// The mints configured in this backup event
    public func mints(signer: NDKSigner) async throws -> [String] {
        let tags = try await decryptedWalletTags(signer: signer)
        return tags.tagValues(named: NostrConstants.TagName.mint)
    }

    /// The P2PK private key in this backup event
    public func p2pkPrivateKey(signer: NDKSigner) async throws -> String? {
        let tags = try await decryptedWalletTags(signer: signer)
        return tags.firstTagValue(named: "privkey")
    }

    /// The relays configured in this backup event
    public var relays: [String] {
        event.tags.tagValues(named: NostrConstants.TagName.relay)
    }

    // Private helper using the same cache as wallet config
    private func decryptedWalletTags(signer: NDKSigner) async throws -> [[String]] {
        // Check cache first
        if let cachedTags = await decryptedWalletCache.get(for: event.id) {
            return cachedTags
        }

        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        guard let tagsData = decryptedContent.data(using: .utf8),
              let walletTags = JSONCoding.safeDecode([[String]].self, from: tagsData) else {
            throw NDKError.invalidContent("Failed to parse wallet backup")
        }

        // Cache the decrypted tags
        await decryptedWalletCache.set(walletTags, for: event.id)

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
        memo: String? = nil,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        token: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuSpendingHistory {
        let historyEvent = try await create(
            ndk: ndk,
            direction: direction,
            amount: amount,
            memo: memo,
            destroyedEventIds: destroyedEventIds,
            createdEventIds: createdEventIds,
            redeemedEventId: redeemedEventId,
            token: token,
            signer: signer
        )

        _ = try await ndk.publish(historyEvent.event)
        NDKLogger.log(.info, category: .event, "NDKCashuSpendingHistory - Published spending history event")

        return historyEvent
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        direction: SpendingDirection,
        amount: Int64,
        memo: String? = nil,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        token: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuSpendingHistory {
        var encryptedTags: [[String]] = []
        encryptedTags.append(["direction", direction.rawValue])
        encryptedTags.append([NostrConstants.TagName.amount, String(amount)])

        if let memo = memo {
            encryptedTags.append(["memo", memo])
        }

        if let token = token {
            encryptedTags.append(["token", token])
        }

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

        let plaintext = try JSONCoding.encodeToString(encryptedTags)

        let historyEvent = try await NDKEventBuilder(ndk: ndk)
            .content(plaintext)
            .kind(EventKind.cashuSpendingHistory)
            .tags(clearTags)
            .encrypt(signer: signer, scheme: .nip44)

        return NDKCashuSpendingHistory(event: historyEvent)
    }

    // MARK: - Data Extraction Methods

    /// Extract direction from the spending history event
    public func direction(signer: NDKSigner) async throws -> SpendingDirection? {
        let tags = try await decryptedTags(signer: signer)
        guard let directionValue = tags.firstTagValue(named: "direction") else { return nil }
        return SpendingDirection(rawValue: directionValue)
    }

    /// Extract amount from the spending history event
    public func amount(signer: NDKSigner) async throws -> Int64? {
        let tags = try await decryptedTags(signer: signer)
        guard let amountString = tags.firstTagValue(named: NostrConstants.TagName.amount) else { return nil }
        return Int64(amountString)
    }

    /// Extract memo from the spending history event
    public func memo(signer: NDKSigner) async throws -> String? {
        let tags = try await decryptedTags(signer: signer)
        return tags.firstTagValue(named: "memo")
    }

    /// Extract Cashu token from the spending history event
    public func token(signer: NDKSigner) async throws -> String? {
        let tags = try await decryptedTags(signer: signer)
        return tags.firstTagValue(named: "token")
    }

    /// Extract created event IDs from the spending history event
    public func createdEventIds(signer: NDKSigner) async throws -> [String] {
        let tags = try await decryptedTags(signer: signer)
        return tags.compactMap { tag in
            guard tag.count >= 4, tag[0] == "e", tag[3] == "created" else { return nil }
            return tag[1]
        }
    }

    /// Extract destroyed event IDs from the spending history event
    public func destroyedEventIds(signer: NDKSigner) async throws -> [String] {
        let tags = try await decryptedTags(signer: signer)
        return tags.compactMap { tag in
            guard tag.count >= 4, tag[0] == "e", tag[3] == "destroyed" else { return nil }
            return tag[1]
        }
    }

    /// Extract redeemed event ID from the unencrypted tags
    public var redeemedEventId: String? {
        event.tags.first(where: { $0.count >= 4 && $0[0] == "e" && $0[3] == "redeemed" })?[1]
    }

    // MARK: - Private Helpers

    private func decryptedTags(signer: NDKSigner) async throws -> [[String]] {
        // Check cache first
        if let cachedTags = await decryptedWalletCache.get(for: event.id) {
            return cachedTags
        }

        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        guard let tagsData = decryptedContent.data(using: .utf8),
              let tags = JSONCoding.safeDecode([[String]].self, from: tagsData) else {
            throw NDKError.invalidContent("Failed to parse spending history tags")
        }

        // Cache the decrypted tags
        await decryptedWalletCache.set(tags, for: event.id)

        return tags
    }
}

// MARK: - NDKCashuMintList

/// NIP-60 Cashu Mint List Event (kind: 10019)
/// Public event that advertises which mints a user accepts for nutzaps
public struct NDKCashuMintList: NDKPublishableEvent {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a mint list event
    /// - Parameters:
    ///   - ndk: NDK instance
    ///   - mints: List of mint URLs to advertise
    ///   - signer: Signer for signing the event
    ///   - p2pkPubkey: P2PK public key for receiving nutzaps (optional)
    /// - Returns: The published mint list event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mints: [String],
        signer: NDKSigner,
        p2pkPubkey: String? = nil,
        relays: [String]? = nil
    ) async throws -> NDKCashuMintList {
        let mintList = try await create(
            ndk: ndk,
            mints: mints,
            signer: signer,
            p2pkPubkey: p2pkPubkey,
            relays: relays
        )

        _ = try await ndk.publish(mintList.event)

        return mintList
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        mints: [String],
        signer: NDKSigner,
        p2pkPubkey: String? = nil,
        relays: [String]? = nil
    ) async throws -> NDKCashuMintList {
        let builder = NDKEventBuilder(ndk: ndk)
            .kind(10019)  // NIP-60 mint list kind

        // Add mint tags
        for mint in mints {
            _ = builder.tag([NostrConstants.TagName.mint, mint])
        }

        // Add P2PK pubkey tag if provided (required for nutzaps per NIP-61)
        if let p2pkPubkey = p2pkPubkey {
            _ = builder.tag([NostrConstants.TagName.pubkey, p2pkPubkey])
        }

        // Add relay tags if provided (recommended for nutzaps per NIP-61)
        if let relays = relays {
            for relay in relays {
                _ = builder.tag([NostrConstants.TagName.relay, relay])
            }
        }

        let mintListEvent = try await builder.build(signer: signer)

        return NDKCashuMintList(event: mintListEvent)
    }

    /// The mints advertised in this mint list event
    public var mints: [String] {
        event.tags
            .filter { $0.first == NostrConstants.TagName.mint && $0.count > 1 }
            .map { $0[1] }
    }
}

// MARK: - NDKCashuMintAnnouncement

/// NIP-87 Cashu Mint Announcement Event (kind: 38172)
/// Public event that announces a Cashu mint
public struct NDKCashuMintAnnouncement {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a mint announcement event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mintURL: String,
        supportedNuts: [String],
        network: String = "mainnet",
        description: String? = nil,
        contact: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuMintAnnouncement {
        let announcement = try await create(
            ndk: ndk,
            mintURL: mintURL,
            supportedNuts: supportedNuts,
            network: network,
            description: description,
            contact: contact,
            signer: signer
        )

        _ = try await ndk.publish(announcement.event)
        return announcement
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        mintURL: String,
        supportedNuts: [String],
        network: String = "mainnet",
        description: String? = nil,
        contact: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKCashuMintAnnouncement {
        var tags: [[String]] = []

        // Add d tag (mint's pubkey)
        let signerPubkey = try await signer.pubkey
        tags.append(["d", signerPubkey])

        // Add u tag (mint URL)
        tags.append(["u", mintURL])

        // Add nuts tags (supported protocol versions)
        for nut in supportedNuts {
            tags.append(["nuts", nut])
        }

        // Add n tag (network)
        tags.append(["n", network])

        let builder = NDKEventBuilder(ndk: ndk)
            .kind(38172)  // NIP-87 Cashu Mint Announcement
            .tags(tags)

        // Add optional content (description)
        if let description = description {
            _ = builder.content(description)
        }

        // Add optional contact tag
        if let contact = contact {
            _ = builder.tag(["contact", contact])
        }

        let announcementEvent = try await builder.build(signer: signer)
        return NDKCashuMintAnnouncement(event: announcementEvent)
    }

    /// Extract mint URL from the announcement
    public var mintURL: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.url)
    }

    /// Extract supported nuts from the announcement
    public var supportedNuts: [String] {
        event.tags.tagValues(named: "nuts")
    }

    /// Extract network from the announcement
    public var network: String? {
        event.tags.firstTagValue(named: "n")
    }

    /// Extract contact from the announcement
    public var contact: String? {
        event.tags.firstTagValue(named: "contact")
    }

    /// Extract description from content
    public var description: String? {
        guard !event.content.isEmpty else { return nil }

        // Try to parse content as JSON first
        if let data = event.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let description = json["description"] as? String {
            return description
        }

        // Fall back to raw content if not JSON
        return event.content
    }

    /// Extract name from content JSON
    public var name: String? {
        guard !event.content.isEmpty,
              let data = event.content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return nil
        }
        return name
    }
}

// MARK: - NDKNutzapEvent

/// NIP-61 Nutzap Event (kind: 9321)
/// Public event that sends Cashu tokens to a recipient
public struct NDKNutzapEvent: NDKPublishableEvent {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a nutzap event
    /// - Parameters:
    ///   - ndk: NDK instance
    ///   - token: Cashu token containing the proofs to send
    ///   - mintURL: URL of the mint the proofs are from
    ///   - recipient: Recipient's nostr pubkey
    ///   - comment: Optional comment
    ///   - eventId: Optional event ID if nutzapping an event
    ///   - signer: Signer for signing the event
    /// - Returns: The published nutzap event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        token: CashuSwift.Token,
        mintURL: String,
        recipient: PublicKey,
        comment: String? = nil,
        eventId: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKNutzapEvent {
        return try await EventPublishingHelper.createAndPublish(
            type: NDKNutzapEvent.self,
            ndk: ndk,
            logPrefix: "NDKNutzapEvent"
        ) {
            try await create(
                ndk: ndk,
                token: token,
                mintURL: mintURL,
                recipient: recipient,
                comment: comment,
                eventId: eventId,
                signer: signer
            )
        }
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        token: CashuSwift.Token,
        mintURL: String,
        recipient: PublicKey,
        comment: String? = nil,
        eventId: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKNutzapEvent {
        let builder = NDKEventBuilder(ndk: ndk)
            .content(comment ?? "") // Content is the comment
            .kind(EventKind.nutzap) // 9321

        // Add p tag for recipient
        _ = builder.tag(["p", recipient])

        // Add e tag if nutzapping an event
        if let eventId = eventId {
            _ = builder.tag(["e", eventId])
        }

        // Add individual proof tags for each proof (per NIP-61)
        guard let proofs = token.proofsByMint[mintURL] else {
            throw NDKError.invalidRequest("No proofs found for mint \(mintURL)")
        }

        // Calculate total amount
        let totalAmount = proofs.reduce(0) { $0 + $1.amount }

        // Add mint URL tag (u tag per NIP-61)
        _ = builder.tag(["u", mintURL])

        // Add amount tag
        _ = builder.tag([NostrConstants.TagName.amount, String(totalAmount)])

        // Add unit tag (hardcoded to "sat")
        _ = builder.tag([NostrConstants.TagName.unit, "sat"])

        for proof in proofs {
            let proofJSON = try JSONCoding.encodeToString(proof)
            _ = builder.tag([NostrConstants.TagName.proof, proofJSON])
        }

        let nutzapEvent = try await builder.build(signer: signer)
        return NDKNutzapEvent(event: nutzapEvent)
    }

    /// Extract the token from the nutzap event
    public var token: CashuSwift.Token? {
        // Get all proof tags
        let proofTags = event.tags.extractTags(named: NostrConstants.TagName.proof)
        guard !proofTags.isEmpty else { return nil }

        // Parse all proofs
        var proofs: [CashuSwift.Proof] = []
        for proofTag in proofTags {
            guard let proofJSON = proofTag[1].data(using: .utf8),
                  let proof = JSONCoding.safeDecode(CashuSwift.Proof.self, from: proofJSON) else {
                continue
            }
            proofs.append(proof)
        }

        guard !proofs.isEmpty, let mintURL = self.mintURL else { return nil }

        // Create token with proofs grouped by mint
        return CashuSwift.Token(
            proofs: [mintURL: proofs],
            unit: unit ?? "sat"
        )
    }

    /// Extract the mint URL from the nutzap event
    public var mintURL: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.url)
    }

    /// Extract the total amount from the amount tag
    public var amount: Int64? {
        guard let amountString = event.tags.firstTagValue(named: NostrConstants.TagName.amount) else {
            return nil
        }
        return Int64(amountString)
    }

    /// Extract the unit from the nutzap event
    public var unit: String? {
        return event.tags.firstTagValue(named: NostrConstants.TagName.unit) ?? "sat"
    }

    /// Extract the recipient from the p tag
    public var recipient: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.pubkey)
    }

    /// Extract the nutzapped event ID from the e tag
    public var nutzappedEventId: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.event)
    }

    /// Get the comment from the event content
    public var comment: String? {
        event.content.nilIfEmpty
    }
}

// MARK: - NDKMintRecommendation

/// NIP-87 Mint Recommendation Event (kind: 38000)
/// Public event that recommends ecash mints
public struct NDKMintRecommendation {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a mint recommendation event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        mintAnnouncementEvent: NDKCashuMintAnnouncement,
        reason: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKMintRecommendation {
        let recommendation = try await create(
            ndk: ndk,
            mintAnnouncementEvent: mintAnnouncementEvent,
            reason: reason,
            signer: signer
        )

        _ = try await ndk.publish(recommendation.event)
        return recommendation
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        mintAnnouncementEvent: NDKCashuMintAnnouncement,
        reason: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKMintRecommendation {
        var tags: [[String]] = []

        // Add k tag (specifying event kind being recommended)
        tags.append(["k", String(EventKind.cashuMintAnnouncement)])

        // Add d tag (event identifier from the announcement)
        if let dTagValue = mintAnnouncementEvent.event.tags.firstTagValue(named: NostrConstants.TagName.identifier) {
            tags.append(["d", dTagValue])
        }

        // Add u tag (mint URL)
        if let mintURL = mintAnnouncementEvent.mintURL {
            tags.append(["u", mintURL])
        }

        // Add a tag (reference to the announcement event)
        tags.append(["a", "38172:\(mintAnnouncementEvent.event.pubkey):\(mintAnnouncementEvent.event.id)"])

        let builder = NDKEventBuilder(ndk: ndk)
            .kind(38000)  // NIP-87 Mint Recommendation
            .tags(tags)

        // Add optional reason as content
        if let reason = reason {
            _ = builder.content(reason)
        }

        let recommendationEvent = try await builder.build(signer: signer)
        return NDKMintRecommendation(event: recommendationEvent)
    }

    /// Extract recommended mint URL
    public var mintURL: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.url)
    }

    /// Extract the announcement event reference
    public var announcementReference: String? {
        event.tags.firstTagValue(named: NostrConstants.TagName.address)
    }

    /// Extract recommendation reason
    public var reason: String? {
        event.content.nilIfEmpty
    }
}