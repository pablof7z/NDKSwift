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
        readRelays: Set<RelayURL>,
        writeRelays: Set<RelayURL>,
        timestamp: Timestamp? = nil,
        source: RelayURL? = nil
    ) -> NDKOutboxItem {
        NDKOutboxItem(
            readRelays: readRelays,
            writeRelays: writeRelays,
            timestamp: timestamp ?? Timestamp(Date().timeIntervalSince1970),
            source: source ?? relay1
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
        kind: EventKind = .textNote,
        content: String = "Test event",
        pubkey: PublicKey? = nil,
        tags: Tags = [],
        createdAt: Timestamp? = nil
    ) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey ?? alicePubkey,
            createdAt: createdAt ?? Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: tags,
            content: content
        )
        event.computeIdAndSerialize()
        return event
    }
    
    /// Make event with p-tags
    static func makeEventWithPTags(
        author: PublicKey,
        pTaggedUsers: [PublicKey],
        content: String = "Test event with mentions"
    ) -> NDKEvent {
        let tags = pTaggedUsers.map { Tag(id: "p", values: [$0]) }
        return makeEvent(
            kind: .textNote,
            content: content,
            pubkey: author,
            tags: tags
        )
    }
    
    /// Make event with e-tag relay hints
    static func makeEventWithETagRelayHints(
        author: PublicKey,
        referencedEvents: [(String, RelayURL)],
        content: String = "Reply event"
    ) -> NDKEvent {
        let tags = referencedEvents.map { eventId, relay in
            Tag(id: "e", values: [eventId, relay])
        }
        return makeEvent(
            kind: .textNote,
            content: content,
            pubkey: author,
            tags: tags
        )
    }
    
    /// Make kind 10002 relay list event
    static func makeRelayListEvent(
        pubkey: PublicKey,
        readRelays: Set<RelayURL>,
        writeRelays: Set<RelayURL>,
        createdAt: Timestamp? = nil
    ) -> NDKEvent {
        var tags: Tags = []
        
        // Add read-only relays
        for relay in readRelays.subtracting(writeRelays) {
            tags.append(Tag(id: "r", values: [relay, "read"]))
        }
        
        // Add write-only relays
        for relay in writeRelays.subtracting(readRelays) {
            tags.append(Tag(id: "r", values: [relay, "write"]))
        }
        
        // Add read+write relays
        for relay in readRelays.intersection(writeRelays) {
            tags.append(Tag(id: "r", values: [relay]))
        }
        
        return makeEvent(
            kind: .relayList,
            content: "",
            pubkey: pubkey,
            tags: tags,
            createdAt: createdAt
        )
    }
    
    // MARK: - NDKFilter Factory
    
    static func makeFilter(
        authors: Set<PublicKey>? = nil,
        kinds: Set<EventKind>? = nil,
        tags: [String: Set<String>]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil
    ) -> NDKFilter {
        NDKFilter(
            authors: authors,
            kinds: kinds,
            tags: tags,
            since: since,
            until: until,
            limit: limit
        )
    }
    
    /// Make filter with p-tags
    static func makeFilterWithPTags(
        authors: Set<PublicKey>? = nil,
        pTaggedUsers: Set<PublicKey>,
        kinds: Set<EventKind>? = nil
    ) -> NDKFilter {
        makeFilter(
            authors: authors,
            kinds: kinds,
            tags: ["p": pTaggedUsers]
        )
    }
    
    // MARK: - Relay Performance Data
    
    static func makeRelayPerformance(
        successCount: Int = 10,
        failureCount: Int = 0,
        totalResponseTime: TimeInterval = 5.0,
        lastUpdated: Date = Date()
    ) -> RelayPerformance {
        RelayPerformance(
            successCount: successCount,
            failureCount: failureCount,
            totalResponseTime: totalResponseTime,
            lastUpdated: lastUpdated
        )
    }
    
    // MARK: - Pre-configured Test Scenarios
    
    /// Scenario: Small group (< 10 p-tags)
    static func makeSmallGroupEvent() -> NDKEvent {
        makeEventWithPTags(
            author: alicePubkey,
            pTaggedUsers: [bobPubkey, charliePubkey, davePubkey],
            content: "Message to small group"
        )
    }
    
    /// Scenario: Large group (>= 10 p-tags)
    static func makeLargeGroupEvent() -> NDKEvent {
        let manyPubkeys = (1...15).map { n in
            "user\(n)23456789012345678901234567890123456789012345678901234567890"
        }
        return makeEventWithPTags(
            author: alicePubkey,
            pTaggedUsers: manyPubkeys,
            content: "Message to large group"
        )
    }
    
    /// Scenario: Direct message
    static func makeDirectMessage(from: PublicKey, to: PublicKey) -> NDKEvent {
        makeEvent(
            kind: .encryptedDirectMessage,
            content: "Encrypted content here",
            pubkey: from,
            tags: [Tag(id: "p", values: [to])]
        )
    }
    
    /// Scenario: Filter for multiple authors
    static func makeMultiAuthorFilter() -> NDKFilter {
        makeFilter(
            authors: [alicePubkey, bobPubkey, charliePubkey],
            kinds: [.textNote]
        )
    }
    
    /// Scenario: Filter with p-tags
    static func makePTagFilter() -> NDKFilter {
        makeFilterWithPTags(
            pTaggedUsers: [alicePubkey, bobPubkey],
            kinds: [.textNote]
        )
    }
    
    /// Scenario: Complex filter with authors and p-tags
    static func makeComplexFilter() -> NDKFilter {
        makeFilter(
            authors: [alicePubkey],
            kinds: [.textNote],
            tags: ["p": [bobPubkey, charliePubkey]]
        )
    }
}