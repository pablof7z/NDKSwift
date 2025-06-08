import Foundation
@testable import NDKSwift

// MARK: - Event Factory Methods

struct EventTestHelpers {
    
    // MARK: - Basic Event Creation
    
    /// Creates a basic test event with default values
    static func createTestEvent(
        content: String = "Test content",
        pubkey: String = "test_pubkey",
        kind: Int = 1,
        tags: [[String]] = [],
        createdAt: Int64? = nil,
        id: String? = nil,
        sig: String? = nil
    ) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: createdAt ?? Int64(Date().timeIntervalSince1970),
            kind: kind,
            tags: tags,
            content: content
        )
        
        if let id = id {
            event.id = id
        } else {
            event.id = generateEventId()
        }
        
        if let sig = sig {
            event.sig = sig
        }
        
        return event
    }
    
    // MARK: - Specific Event Types
    
    /// Creates a profile metadata event (kind 0)
    static func createProfileEvent(
        pubkey: String = "test_pubkey",
        name: String = "Test User",
        about: String = "Test about",
        picture: String = "https://example.com/avatar.jpg",
        nip05: String? = nil,
        lud16: String? = nil,
        website: String? = nil,
        banner: String? = nil
    ) -> NDKEvent {
        var profileData: [String: Any] = [
            "name": name,
            "about": about,
            "picture": picture
        ]
        
        if let nip05 = nip05 {
            profileData["nip05"] = nip05
        }
        if let lud16 = lud16 {
            profileData["lud16"] = lud16
        }
        if let website = website {
            profileData["website"] = website
        }
        if let banner = banner {
            profileData["banner"] = banner
        }
        
        let content = try! JSONSerialization.data(withJSONObject: profileData)
        let contentString = String(data: content, encoding: .utf8)!
        
        return createTestEvent(
            content: contentString,
            pubkey: pubkey,
            kind: EventKind.metadata
        )
    }
    
    /// Creates a text note event (kind 1)
    static func createTextNoteEvent(
        content: String = "Hello, Nostr!",
        pubkey: String = "test_pubkey",
        tags: [[String]] = []
    ) -> NDKEvent {
        return createTestEvent(
            content: content,
            pubkey: pubkey,
            kind: EventKind.textNote,
            tags: tags
        )
    }
    
    /// Creates a reaction event (kind 7)
    static func createReactionEvent(
        content: String = "+",
        reactingTo eventId: String,
        reactingToPubkey: String,
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let tags = [
            ["e", eventId],
            ["p", reactingToPubkey]
        ]
        
        return createTestEvent(
            content: content,
            pubkey: pubkey,
            kind: EventKind.reaction,
            tags: tags
        )
    }
    
    /// Creates a repost event (kind 6)
    static func createRepostEvent(
        reposting event: NDKEvent,
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let eventJson = try! JSONEncoder().encode(event)
        let content = String(data: eventJson, encoding: .utf8)!
        
        let tags = [
            ["e", event.id ?? "", "", "mention"],
            ["p", event.pubkey]
        ]
        
        return createTestEvent(
            content: content,
            pubkey: pubkey,
            kind: EventKind.repost,
            tags: tags
        )
    }
    
    /// Creates a deletion event (kind 5)
    static func createDeletionEvent(
        deletingEventIds: [String],
        reason: String = "Deleted by user",
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let tags = deletingEventIds.map { ["e", $0] }
        
        return createTestEvent(
            content: reason,
            pubkey: pubkey,
            kind: EventKind.deletion,
            tags: tags
        )
    }
    
    /// Creates a relay list event (kind 10002)
    static func createRelayListEvent(
        relays: [(url: String, read: Bool, write: Bool)],
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let tags = relays.map { relay in
            var tag = ["r", relay.url]
            if relay.read && !relay.write {
                tag.append("read")
            } else if !relay.read && relay.write {
                tag.append("write")
            }
            return tag
        }
        
        return createTestEvent(
            content: "",
            pubkey: pubkey,
            kind: EventKind.relayList,
            tags: tags
        )
    }
    
    /// Creates a contact list event (kind 3)
    static func createContactListEvent(
        contacts: [(pubkey: String, relay: String?, petname: String?)],
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let tags = contacts.map { contact in
            var tag = ["p", contact.pubkey]
            if let relay = contact.relay {
                tag.append(relay)
            }
            if let petname = contact.petname {
                tag.append(petname)
            }
            return tag
        }
        
        return createTestEvent(
            content: "",
            pubkey: pubkey,
            kind: EventKind.contacts,
            tags: tags
        )
    }
    
    // MARK: - Event with Specific Properties
    
    /// Creates an event with a specific timestamp
    static func createEventWithTimestamp(
        _ timestamp: Int64,
        content: String = "Test content",
        kind: Int = 1
    ) -> NDKEvent {
        return createTestEvent(
            content: content,
            kind: kind,
            createdAt: timestamp
        )
    }
    
    /// Creates an event with specific tags
    static func createEventWithTags(
        _ tags: [[String]],
        content: String = "Test content",
        kind: Int = 1
    ) -> NDKEvent {
        return createTestEvent(
            content: content,
            kind: kind,
            tags: tags
        )
    }
    
    /// Creates a parameterized replaceable event
    static func createParameterizedReplaceableEvent(
        kind: Int = 30000,
        dTag: String = "test-d-tag",
        content: String = "Test content",
        pubkey: String = "test_pubkey"
    ) -> NDKEvent {
        let tags = [["d", dTag]]
        
        return createTestEvent(
            content: content,
            pubkey: pubkey,
            kind: kind,
            tags: tags
        )
    }
    
    /// Creates a signed event using a mock signer
    static func createSignedEvent(
        content: String = "Test content",
        kind: Int = 1,
        signer: NDKSigner? = nil
    ) async throws -> NDKEvent {
        let mockSigner = signer ?? MockSigner()
        let pubkey = try await mockSigner.pubkey
        
        var event = createTestEvent(
            content: content,
            pubkey: pubkey,
            kind: kind
        )
        
        try await mockSigner.sign(event: &event)
        return event
    }
    
    // MARK: - Helper Methods
    
    /// Generates a random event ID
    static func generateEventId() -> String {
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Creates multiple events with sequential content
    static func createMultipleEvents(
        count: Int,
        prefix: String = "Test event",
        kind: Int = 1
    ) -> [NDKEvent] {
        return (1...count).map { index in
            createTestEvent(
                content: "\(prefix) #\(index)",
                kind: kind
            )
        }
    }
    
    /// Creates an event that matches a specific filter
    static func createEventMatchingFilter(_ filter: NDKFilter) -> NDKEvent {
        let pubkey = filter.authors?.first ?? "test_pubkey"
        let kind = filter.kinds?.first ?? 1
        let tags = filter.tags?.flatMap { tagName, tagValues in
            tagValues.map { [tagName, $0] }
        } ?? []
        
        return createTestEvent(
            pubkey: pubkey,
            kind: kind,
            tags: tags
        )
    }
    
    /// Creates invalid events for testing error handling
    static func createInvalidEvent(reason: InvalidEventReason) -> NDKEvent {
        switch reason {
        case .missingId:
            var event = createTestEvent()
            event.id = ""
            return event
            
        case .missingPubkey:
            return createTestEvent(pubkey: "")
            
        case .invalidSignature:
            var event = createTestEvent()
            event.sig = "invalid_signature"
            return event
            
        case .futureDateTooFar:
            let futureDate = Date().addingTimeInterval(60 * 60 * 24 * 365) // 1 year in future
            return createTestEvent(createdAt: Int64(futureDate.timeIntervalSince1970))
        }
    }
    
    enum InvalidEventReason {
        case missingId
        case missingPubkey
        case invalidSignature
        case futureDateTooFar
    }
}

// MARK: - Test Data Sets

struct EventTestDataSets {
    
    /// Common test pubkeys
    static let testPubkeys = [
        "pubkey1",
        "pubkey2",
        "pubkey3",
        "test_alice",
        "test_bob",
        "test_charlie"
    ]
    
    /// Common test event IDs
    static let testEventIds = [
        "event1",
        "event2",
        "event3"
    ]
    
    /// Creates a conversation thread of events
    static func createConversationThread() -> [NDKEvent] {
        let rootEvent = EventTestHelpers.createTextNoteEvent(
            content: "Starting a conversation",
            pubkey: testPubkeys[0]
        )
        
        let reply1 = EventTestHelpers.createTextNoteEvent(
            content: "Reply to the conversation",
            pubkey: testPubkeys[1],
            tags: [["e", rootEvent.id ?? "", "", "reply"], ["p", rootEvent.pubkey]]
        )
        
        let reply2 = EventTestHelpers.createTextNoteEvent(
            content: "Another reply",
            pubkey: testPubkeys[2],
            tags: [["e", rootEvent.id ?? "", "", "reply"], ["p", rootEvent.pubkey]]
        )
        
        let nestedReply = EventTestHelpers.createTextNoteEvent(
            content: "Reply to a reply",
            pubkey: testPubkeys[0],
            tags: [
                ["e", rootEvent.id, "", "root"],
                ["e", reply1.id, "", "reply"],
                ["p", reply1.pubkey]
            ]
        )
        
        return [rootEvent, reply1, reply2, nestedReply]
    }
    
    /// Creates a set of events with various kinds
    static func createMixedKindEvents() -> [NDKEvent] {
        return [
            EventTestHelpers.createProfileEvent(),
            EventTestHelpers.createTextNoteEvent(),
            EventTestHelpers.createReactionEvent(reactingTo: "event1", reactingToPubkey: "pubkey1"),
            EventTestHelpers.createRelayListEvent(relays: [
                ("wss://relay1.com", true, true),
                ("wss://relay2.com", true, false)
            ]),
            EventTestHelpers.createContactListEvent(contacts: [
                ("pubkey1", "wss://relay1.com", "Alice"),
                ("pubkey2", nil, nil)
            ])
        ]
    }
}