import Foundation
@testable import NDKSwift

// MARK: - Standard Test Data

enum TestFixtures {
    // MARK: - Test Keys
    
    /// Well-known test private/public key pairs
    enum Keys {
        static let alice = TestKeyPair(
            privateKey: "5c0b3e8f4b3a8d7e9f2a1b6c8d4e7f9a2b5c8e1f4d7a9b3c6e8f1a3d5b7c9e2f",
            publicKey: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        )
        
        static let bob = TestKeyPair(
            privateKey: "7d1a2f8e9c3b4d5e6f7a8b9c1d2e3f4a5b6c7d8e9f1a2b3c4d5e6f7a8b9c1d2e",
            publicKey: "9e30e940982e7764c489dc59a550278012a106cb278877e68274424502dc8430"
        )
        
        static let charlie = TestKeyPair(
            privateKey: "9f1b2c3d4e5f6a7b8c9d1e2f3a4b5c6d7e8f9a1b2c3d4e5f6a7b8c9d1e2f3a4b",
            publicKey: "8e3f5d9a2b1c4e7f6a9b8c7d5e4f3a2b1c9d8e7f6a5b4c3d2e1f9a8b7c6d5e4f"
        )
    }
    
    // MARK: - Test Events
    
    /// Pre-constructed test events
    enum Events {
        static let textNote = NDKEvent(
            id: "test_event_001",
            pubkey: Keys.alice.publicKey,
            createdAt: 1700000000,
            kind: 1,
            tags: [],
            content: "Hello, Nostr!",
            sig: "test_signature_001"
        )
        
        static let replyNote = NDKEvent(
            id: "test_event_002",
            pubkey: Keys.bob.publicKey,
            createdAt: 1700000100,
            kind: 1,
            tags: [
                [NostrConstants.TagName.event, textNote.id],
                [NostrConstants.TagName.pubkey, textNote.pubkey]
            ],
            content: "Nice to meet you!",
            sig: "test_signature_002"
        )
        
        static let metadata = NDKEvent(
            id: "test_event_003",
            pubkey: Keys.alice.publicKey,
            createdAt: 1700000200,
            kind: 0,
            tags: [],
            content: """
            {
                "name": "Alice",
                "about": "Test user Alice",
                "picture": "https://example.com/alice.jpg",
                "nip05": "alice@example.com"
            }
            """,
            sig: "test_signature_003"
        )
        
        static let contactList = NDKEvent(
            id: "test_event_004",
            pubkey: Keys.alice.publicKey,
            createdAt: 1700000300,
            kind: 3,
            tags: [
                [NostrConstants.TagName.pubkey, Keys.bob.publicKey],
                [NostrConstants.TagName.pubkey, Keys.charlie.publicKey]
            ],
            content: "",
            sig: "test_signature_004"
        )
        
        static let deletion = NDKEvent(
            id: "test_event_005",
            pubkey: Keys.alice.publicKey,
            createdAt: 1700000400,
            kind: 5,
            tags: [
                [NostrConstants.TagName.event, textNote.id]
            ],
            content: "Deleting test note",
            sig: "test_signature_005"
        )
    }
    
    // MARK: - Test Filters
    
    /// Common filter patterns
    enum Filters {
        static let allTextNotes = NDKFilter(kinds: [1])
        
        static let aliceTextNotes = NDKFilter(
            authors: [Keys.alice.publicKey],
            kinds: [1]
        )
        
        static let recentEvents = NDKFilter(
            since: Timestamp.now - 3600 // Last hour
        )
        
        static let allMetadata = NDKFilter(
            kinds: [0],
            limit: 100
        )
        
        static let repliesToEvent = { (eventId: EventID) in
            NDKFilter(
                kinds: [1],
                tags: [NostrConstants.TagName.event: [eventId]]
            )
        }
    }
    
    // MARK: - Test Relay URLs
    
    /// Test relay configurations
    enum Relays {
        static let defaultRelays = [
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://relay.nostr.band"
        ]
        
        static let mockRelays = [
            "wss://mock1.relay.test",
            "wss://mock2.relay.test",
            "wss://mock3.relay.test"
        ]
        
        static let singleRelay = ["wss://single.relay.test"]
    }
    
    // MARK: - Test Content
    
    /// Sample content for various event types
    enum Content {
        static let shortNote = "Test note"
        static let longNote = String(repeating: "Lorem ipsum dolor sit amet. ", count: 100)
        static let emojiNote = "Hello 👋 Nostr! 🎉"
        static let mentionNote = "Hey nostr:\(Keys.bob.publicKey), check this out!"
        static let urlNote = "Visit https://nostr.com for more info"
        static let hashtagNote = "Testing #nostr #development"
        
        static let validMetadata = """
        {
            "name": "Test User",
            "about": "I am a test user",
            "picture": "https://example.com/pic.jpg",
            "banner": "https://example.com/banner.jpg",
            "nip05": "test@example.com",
            "lud16": "test@getalby.com"
        }
        """
        
        static let invalidMetadata = "{ invalid json }"
    }
    
    // MARK: - Test Tags
    
    /// Common tag patterns
    enum Tags {
        static let mention = { (pubkey: PublicKey) in
            [NostrConstants.TagName.pubkey, pubkey]
        }
        
        static let eventReference = { (eventId: EventID) in
            [NostrConstants.TagName.event, eventId]
        }
        
        static let replyMarker = { (eventId: EventID) in
            [NostrConstants.TagName.event, eventId, "", NostrConstants.Marker.reply]
        }
        
        static let rootMarker = { (eventId: EventID) in
            [NostrConstants.TagName.event, eventId, "", NostrConstants.Marker.root]
        }
        
        static let hashtag = { (tag: String) in
            [NostrConstants.TagName.hashtag, tag]
        }
        
        static let relayHint = { (eventId: EventID, relay: String) in
            [NostrConstants.TagName.event, eventId, relay]
        }
    }
    
    // MARK: - Test Timestamps
    
    /// Useful timestamp values
    enum Timestamps {
        static let past = Timestamp(1600000000) // September 2020
        static let recent = Timestamp.now - 3600 // 1 hour ago
        static let now = Timestamp.now
        static let future = Timestamp.now + 3600 // 1 hour from now
        static let farFuture = Timestamp(2000000000) // May 2033
    }
}

// MARK: - Supporting Types

struct TestKeyPair {
    let privateKey: String
    let publicKey: String
    
    func createSigner() throws -> NDKPrivateKeySigner {
        return try NDKPrivateKeySigner(privateKey: privateKey)
    }
}

// MARK: - Test Data Generators

extension TestFixtures {
    /// Generates a series of test events
    static func generateEventSeries(
        count: Int,
        author: PublicKey,
        kind: Kind = 1,
        baseTime: Timestamp = Timestamp.now
    ) -> [NDKEvent] {
        return (0..<count).map { index in
            NDKEvent(
                id: "series_event_\(index)",
                pubkey: author,
                createdAt: baseTime + Timestamp(index),
                kind: kind,
                tags: [],
                content: "Event #\(index) in series",
                sig: "series_sig_\(index)"
            )
        }
    }
    
    /// Generates a thread of connected events
    static func generateEventThread(
        depth: Int,
        rootAuthor: PublicKey = Keys.alice.publicKey
    ) -> [NDKEvent] {
        var events: [NDKEvent] = []
        
        // Create root event
        let root = NDKEvent(
            id: "thread_root",
            pubkey: rootAuthor,
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Root of thread",
            sig: "thread_root_sig"
        )
        events.append(root)
        
        // Create replies
        for i in 1..<depth {
            let parent = events[i - 1]
            let author = i % 2 == 0 ? Keys.bob.publicKey : Keys.charlie.publicKey
            
            let reply = NDKEvent(
                id: "thread_reply_\(i)",
                pubkey: author,
                createdAt: parent.createdAt + 60,
                kind: 1,
                tags: [
                    [NostrConstants.TagName.event, root.id, "", NostrConstants.Marker.root],
                    [NostrConstants.TagName.event, parent.id, "", NostrConstants.Marker.reply],
                    [NostrConstants.TagName.pubkey, parent.pubkey]
                ],
                content: "Reply #\(i) to thread",
                sig: "thread_reply_\(i)_sig"
            )
            events.append(reply)
        }
        
        return events
    }
}