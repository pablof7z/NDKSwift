import Foundation
@testable import NDKSwift

/// Test fixtures for outbox-related tests
struct OutboxTestFixtures {
    
    // MARK: - Sample Relay URLs
    
    static let relay1 = "wss://relay1.test.com/"
    static let relay2 = "wss://relay2.test.com/"
    static let relay3 = "wss://relay3.test.com/"
    static let relay4 = "wss://relay4.test.com/"
    static let relay5 = "wss://relay5.test.com/"
    static let relay6 = "wss://relay6.test.com/"
    static let authRelay = "wss://auth.relay.test.com/"
    static let blacklistedRelay = "wss://blacklisted.test.com/"
    
    static let allTestRelays: Set<RelayURL> = [
        relay1, relay2, relay3, relay4, relay5, relay6, authRelay
    ]
    
    // MARK: - Sample Pubkeys
    
    static let alicePubkey = "alice123456789012345678901234567890123456789012345678901234567890"
    static let bobPubkey = "bob1234567890123456789012345678901234567890123456789012345678901234"
    static let charliePubkey = "charlie3456789012345678901234567890123456789012345678901234567890"
    static let davePubkey = "dave234567890123456789012345678901234567890123456789012345678901234"
    static let evePubkey = "eve3234567890123456789012345678901234567890123456789012345678901234"
    
    // MARK: - NDKOutboxItem Factory
    
    static func makeOutboxItem(
        pubkey: String = alicePubkey,
        readRelays: Set<RelayURL>,
        writeRelays: Set<RelayURL>,
        fetchedAt: Date? = nil,
        source: RelayListSource? = nil
    ) -> NDKOutboxItem {
        NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelays.map { RelayInfo(url: $0) }),
            writeRelays: Set(writeRelays.map { RelayInfo(url: $0) }),
            fetchedAt: fetchedAt ?? Date(),
            source: source ?? .unknown
        )
    }
    
    // MARK: - Common Relay Configurations
    
    static let aliceRelayInfo = makeOutboxItem(
        readRelays: [relay1, relay2],
        writeRelays: [relay1, relay3]
    )
    
    static let bobRelayInfo = makeOutboxItem(
        readRelays: [relay2, relay4],
        writeRelays: [relay2, relay5]
    )
    
    static let charlieRelayInfo = makeOutboxItem(
        readRelays: [relay3, relay4],
        writeRelays: [relay3, relay6]
    )
    
    static let daveRelayInfo = makeOutboxItem(
        readRelays: [relay1, relay5],
        writeRelays: [relay5, relay6]
    )
    
    static let eveRelayInfo = makeOutboxItem(
        readRelays: [],  // Eve only has write relays
        writeRelays: [relay4, relay6]
    )
    
    // MARK: - NDKEvent Factory
    
    static func makeEvent(
        kind: Int = EventKind.textNote,
        content: String = "Test event",
        pubkey: PublicKey? = nil,
        tags: [Tag] = [],
        createdAt: Timestamp? = nil
    ) async throws -> NDKEvent {
        let builder = NDKEventBuilder(ndk: NDK())
            .kind(Kind(kind))
            .content(content)
            .tags(tags)
        return try await builder.build()
    }
    
    /// Make event with p-tags
    static func makeEventWithPTags(
        author: PublicKey,
        pTaggedUsers: [PublicKey],
        content: String = "Test event with mentions"
    ) async throws -> NDKEvent {
        let tags = pTaggedUsers.map { ["p", $0] }
        return try await makeEvent(
            kind: EventKind.textNote,
            content: content,
            tags: tags
        )
    }
    
    /// Make event with e-tag relay hints
    static func makeEventWithETagRelayHints(
        author: PublicKey,
        referencedEvents: [(String, RelayURL)],
        content: String = "Reply event"
    ) async throws -> NDKEvent {
        let tags = referencedEvents.map { eventId, relay in
            ["e", eventId, relay]
        }
        return try await makeEvent(
            kind: EventKind.textNote,
            content: content,
            tags: tags
        )
    }
    
    /// Make kind 10002 relay list event
    static func makeRelayListEvent(
        pubkey: PublicKey,
        readRelays: Set<RelayURL>,
        writeRelays: Set<RelayURL>,
        createdAt: Timestamp? = nil
    ) async throws -> NDKEvent {
        var tags: [Tag] = []
        
        // Add read-only relays
        for relay in readRelays.subtracting(writeRelays) {
            tags.append(["r", relay, "read"])
        }
        
        // Add write-only relays
        for relay in writeRelays.subtracting(readRelays) {
            tags.append(["r", relay, "write"])
        }
        
        // Add read+write relays
        for relay in readRelays.intersection(writeRelays) {
            tags.append(["r", relay])
        }
        
        return try await makeEvent(
            kind: EventKind.relayList,
            content: "",
            tags: tags
        )
    }
    
    // MARK: - NDKFilter Factory
    
    static func makeFilter(
        authors: Set<PublicKey>? = nil,
        kinds: Set<Int>? = nil,
        tags: [String: Set<String>]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil
    ) -> NDKFilter {
        NDKFilter(
            authors: authors?.map { $0 },
            kinds: kinds?.map { Kind($0) },
            since: since,
            until: until,
            limit: limit,
            tags: tags
        )
    }
    
    /// Make filter with p-tags
    static func makeFilterWithPTags(
        authors: Set<PublicKey>? = nil,
        pTaggedUsers: Set<PublicKey>,
        kinds: Set<Int>? = nil
    ) -> NDKFilter {
        makeFilter(
            authors: authors,
            kinds: kinds,
            tags: ["p": pTaggedUsers]
        )
    }
    
    // MARK: - Relay Performance Data (removed - type doesn't exist)
    
    // MARK: - Pre-configured Test Scenarios
    
    /// Scenario: Small group (< 10 p-tags)
    static func makeSmallGroupEvent() async throws -> NDKEvent {
        try await makeEventWithPTags(
            author: alicePubkey,
            pTaggedUsers: [bobPubkey, charliePubkey, davePubkey],
            content: "Message to small group"
        )
    }
    
    /// Scenario: Large group (>= 10 p-tags)
    static func makeLargeGroupEvent() async throws -> NDKEvent {
        let manyPubkeys = (1...15).map { n in
            "user\(n)23456789012345678901234567890123456789012345678901234567890"
        }
        return try await makeEventWithPTags(
            author: alicePubkey,
            pTaggedUsers: manyPubkeys,
            content: "Message to large group"
        )
    }
    
    /// Scenario: Direct message
    static func makeDirectMessage(from: PublicKey, to: PublicKey) async throws -> NDKEvent {
        try await makeEvent(
            kind: EventKind.encryptedDirectMessage,
            content: "Encrypted content here",
            pubkey: from,
            tags: [["p", to]]
        )
    }
    
    /// Scenario: Filter for multiple authors
    static func makeMultiAuthorFilter() -> NDKFilter {
        makeFilter(
            authors: [alicePubkey, bobPubkey, charliePubkey],
            kinds: [EventKind.textNote]
        )
    }
    
    /// Scenario: Filter with p-tags
    static func makePTagFilter() -> NDKFilter {
        makeFilterWithPTags(
            pTaggedUsers: [alicePubkey, bobPubkey],
            kinds: [EventKind.textNote]
        )
    }
    
    /// Scenario: Complex filter with authors and p-tags
    static func makeComplexFilter() -> NDKFilter {
        makeFilter(
            authors: [alicePubkey],
            kinds: [EventKind.textNote],
            tags: ["p": [bobPubkey, charliePubkey]]
        )
    }
}