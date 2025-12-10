import Foundation
@testable import NDKSwiftCore

// MARK: - Extended Test Fixtures

extension TestFixtures {
    
    // MARK: - Encryption Test Data
    
    /// Test data for encryption/decryption tests
    enum Encryption {
        static let plaintext = "Hello, encrypted world!"
        static let longPlaintext = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50)
        static let unicodePlaintext = "Hello 👋 Nostr! 🎉 €£¥"
        
        /// Shared secret for NIP-04/NIP-44 tests
        static let sharedSecret = "test_shared_secret_32_bytes_long"
        
        /// Test conversation between Alice and Bob
        static let conversation = [
            "Alice: Hey Bob!",
            "Bob: Hi Alice, how are you?",
            "Alice: Great! Testing encryption.",
            "Bob: Awesome, it's working! 🎉"
        ]
    }
    
    // MARK: - Wallet Test Data
    
    /// Test data for wallet/payment tests
    enum Wallet {
        static let testMintURL = "https://testmint.cashu.space"
        static let testMintURLs = [
            "https://mint1.test.com",
            "https://mint2.test.com",
            "https://mint3.test.com"
        ]
        
        static let testInvoice = "lnbc1000n1pj9k8..."
        static let testZapRequest = """
        {
            "kind": 9734,
            "content": "Great post!",
            "tags": [
                ["p", "\(Keys.bob.publicKey)"],
                ["e", "test_event_001"],
                ["amount", "1000"],
                ["relays", "wss://relay.damus.io"]
            ]
        }
        """
        
        static let sampleProofs = [
            ["amount": 1, "C": "test_c_1", "id": "test_id_1", "secret": "test_secret_1"],
            ["amount": 2, "C": "test_c_2", "id": "test_id_2", "secret": "test_secret_2"],
            ["amount": 4, "C": "test_c_4", "id": "test_id_4", "secret": "test_secret_4"]
        ]
    }
    
    // MARK: - Subscription Test Data
    
    /// Test data for subscription tests
    enum Subscriptions {
        /// Creates a series of filters for testing aggregation
        static func createAggregationFilters() -> [NDKFilter] {
            return [
                NDKFilter(authors: [Keys.alice.publicKey], kinds: [1]),
                NDKFilter(authors: [Keys.bob.publicKey], kinds: [1]),
                NDKFilter(authors: [Keys.charlie.publicKey], kinds: [1])
            ]
        }
        
        /// Creates filters with different fingerprints
        static func createDistinctFilters() -> [NDKFilter] {
            return [
                NDKFilter(kinds: [1], limit: 10),
                NDKFilter(kinds: [0, 3], limit: 20),
                NDKFilter(authors: [Keys.alice.publicKey]),
                NDKFilter(tags: ["p": [Keys.bob.publicKey]])
            ]
        }
        
        /// Creates filters that should be grouped together
        static func createGroupableFilters() -> [NDKFilter] {
            return [
                NDKFilter(kinds: [1], since: Timestamps.recent),
                NDKFilter(kinds: [1], since: Timestamps.recent),
                NDKFilter(kinds: [1], since: Timestamps.recent)
            ]
        }
    }
    
    // MARK: - Relay Test Data
    
    /// Test data for relay-specific tests
    enum RelayData {
        /// AUTH challenge for NIP-42 tests
        static let authChallenge = "auth_challenge_string_32_chars_long"
        
        /// OK message samples
        static let okMessages = [
            ["OK", "test_event_001", true, ""],
            ["OK", "test_event_002", false, "duplicate: already have this event"],
            ["OK", "test_event_003", false, "invalid: signature verification failed"]
        ]
        
        /// NOTICE messages
        static let noticeMessages = [
            "rate limit exceeded",
            "authentication required",
            "invalid filter: limit too high"
        ]
        
        /// CLOSED messages
        static let closedMessages = [
            ["CLOSED", "sub_001", "error: invalid filter"],
            ["CLOSED", "sub_002", "error: auth required"]
        ]
    }
    
    // MARK: - Large Dataset Generators
    
    /// Generators for performance and stress tests
    enum LargeDatasets {
        /// Generates a large number of events with realistic distribution
        static func generateRealisticEventSet(
            count: Int,
            authors: [PublicKey]? = nil
        ) -> [NDKEvent] {
            let authorList = authors ?? [Keys.alice.publicKey, Keys.bob.publicKey, Keys.charlie.publicKey]
            let kinds: [Kind] = [0, 1, 3, 6, 7] // metadata, notes, contacts, reposts, reactions
            
            return (0..<count).map { index in
                let author = authorList[index % authorList.count]
                let kind = kinds[index % kinds.count]
                let timestamp = Timestamp.now - Timestamp(count - index) // Oldest first
                
                let content: String
                let tags: [Tag]
                
                switch kind {
                case 0: // Metadata
                    content = """
                    {"name":"User \(index)","about":"Test user #\(index)","picture":"https://example.com/\(index).jpg"}
                    """
                    tags = []
                case 1: // Text note
                    content = "Note #\(index): \(Content.longNote.prefix(100))..."
                    tags = index % 3 == 0 ? [[NostrConstants.TagName.hashtag, "test"]] : []
                case 3: // Contact list
                    content = ""
                    tags = authorList.map { [NostrConstants.TagName.pubkey, $0] }
                case 6: // Repost
                    content = "{}"
                    tags = [[NostrConstants.TagName.event, "reposted_event_\(index)"]]
                case 7: // Reaction
                    content = index % 2 == 0 ? "+" : "❤️"
                    tags = [
                        [NostrConstants.TagName.event, "reacted_event_\(index)"],
                        [NostrConstants.TagName.pubkey, authorList[(index + 1) % authorList.count]]
                    ]
                default:
                    content = "Event #\(index)"
                    tags = []
                }
                
                return NDKEvent(
                    id: "large_dataset_event_\(index)",
                    pubkey: author,
                    createdAt: timestamp,
                    kind: kind,
                    tags: tags,
                    content: content,
                    sig: "large_dataset_sig_\(index)"
                )
            }
        }
        
        /// Generates events that form a social graph
        static func generateSocialGraph(
            userCount: Int = 10,
            avgFollowsPerUser: Int = 3,
            avgNotesPerUser: Int = 5
        ) -> (users: [String], events: [NDKEvent]) {
            var events: [NDKEvent] = []
            let users = (0..<userCount).map { "user_pubkey_\($0)" }
            var eventIdCounter = 0
            
            // Generate metadata for each user
            for (index, pubkey) in users.enumerated() {
                let metadata = NDKEvent(
                    id: "social_event_\(eventIdCounter)",
                    pubkey: pubkey,
                    createdAt: Timestamp.now - Timestamp(userCount - index),
                    kind: 0,
                    tags: [],
                    content: """
                    {"name":"User \(index)","about":"Social graph test user #\(index)"}
                    """,
                    sig: "social_sig_\(eventIdCounter)"
                )
                events.append(metadata)
                eventIdCounter += 1
            }
            
            // Generate follow lists
            for (index, pubkey) in users.enumerated() {
                var followTags: [Tag] = []
                for _ in 0..<avgFollowsPerUser {
                    let followIndex = Int.random(in: 0..<userCount)
                    if followIndex != index {
                        followTags.append([NostrConstants.TagName.pubkey, users[followIndex]])
                    }
                }
                
                let followList = NDKEvent(
                    id: "social_event_\(eventIdCounter)",
                    pubkey: pubkey,
                    createdAt: Timestamp.now - Timestamp(userCount - index - 1),
                    kind: 3,
                    tags: followTags,
                    content: "",
                    sig: "social_sig_\(eventIdCounter)"
                )
                events.append(followList)
                eventIdCounter += 1
            }
            
            // Generate notes
            for (index, pubkey) in users.enumerated() {
                for noteIndex in 0..<avgNotesPerUser {
                    let note = NDKEvent(
                        id: "social_event_\(eventIdCounter)",
                        pubkey: pubkey,
                        createdAt: Timestamp.now - Timestamp((userCount - index) * 10 + noteIndex),
                        kind: 1,
                        tags: [],
                        content: "Note \(noteIndex) from user \(index)",
                        sig: "social_sig_\(eventIdCounter)"
                    )
                    events.append(note)
                    eventIdCounter += 1
                }
            }
            
            return (users, events)
        }
    }
    
    // MARK: - NIP-Specific Test Data
    
    /// Test data organized by NIP
    enum NIPs {
        /// NIP-05 identifier test cases
        static let nip05Identifiers = [
            "alice@nostr.example.com",
            "bob@example.com",
            "_@example.com",
            "test_user@sub.domain.example.com"
        ]
        
        /// NIP-19 bech32 test cases
        static let nip19TestCases = [
            (hex: Keys.alice.publicKey, bech32: "npub1..."), // Would need actual encoding
            (hex: "test_note_id", bech32: "note1..."),
            (hex: Keys.bob.privateKey, bech32: "nsec1...")
        ]
        
        /// NIP-25 reaction types
        static let reactionTypes = ["+", "-", "❤️", "🔥", "💯", "🤙", "⚡", "🤔"]
        
        /// NIP-36 content warning examples
        static let contentWarnings = [
            "NSFW",
            "Politics",
            "Spoiler: Movie ending",
            "Sensitive content"
        ]
    }
    
    // MARK: - Mock Response Generators
    
    /// Generators for mock relay responses
    enum MockResponses {
        /// Generates a mock EVENT message
        static func eventMessage(event: NDKEvent, subscription: String) -> [Any] {
            // Convert event to dictionary for the EVENT message
            let eventDict: [String: Any] = [
                "id": event.id,
                "pubkey": event.pubkey,
                "created_at": event.createdAt,
                "kind": event.kind,
                "tags": event.tags,
                "content": event.content,
                "sig": event.sig
            ]
            return ["EVENT", subscription, eventDict]
        }
        
        /// Generates a mock EOSE message
        static func eoseMessage(subscription: String) -> [Any] {
            return ["EOSE", subscription]
        }
        
        /// Generates a mock OK message
        static func okMessage(eventId: String, success: Bool = true, message: String = "") -> [Any] {
            return ["OK", eventId, success, message]
        }
        
        /// Generates a mock AUTH message
        static func authMessage(challenge: String) -> [Any] {
            return ["AUTH", challenge]
        }
        
        /// Generates a mock NOTICE message
        static func noticeMessage(_ message: String) -> [Any] {
            return ["NOTICE", message]
        }
    }
}

// MARK: - Test Event Builders

extension TestFixtures {
    /// Convenient builders for complex event types
    enum EventBuilders {
        /// Creates a zap request event
        static func createZapRequest(
            amount: Int64,
            to pubkey: String,
            for eventId: String? = nil,
            comment: String = "Zap!"
        ) -> NDKEvent {
            var tags: [Tag] = [
                [NostrConstants.TagName.pubkey, pubkey],
                ["amount", String(amount)],
                ["relays", RelayConstants.testRelays.joined(separator: ",")]
            ]
            
            if let eventId = eventId {
                tags.append([NostrConstants.TagName.event, eventId])
            }
            
            return EventTestFactory.createEvent(
                kind: 9734,
                content: comment,
                tags: tags
            )
        }
        
        /// Creates a nutzap event
        static func createNutzap(
            amount: Int64,
            to pubkey: String,
            proofs: [[String: Any]],
            mint: String
        ) -> NDKEvent {
            let tags: [Tag] = [
                [NostrConstants.TagName.pubkey, pubkey],
                ["amount", String(amount)],
                ["u", mint]
            ]
            
            let proofsData = try! JSONSerialization.data(withJSONObject: ["proofs": proofs], options: [])
            let content = String(data: proofsData, encoding: .utf8)!
            
            return EventTestFactory.createEvent(
                kind: 9321,
                content: content,
                tags: tags
            )
        }
        
        /// Creates a replaceable event
        static func createReplaceableEvent(
            kind: Kind = 10002,
            dTag: String = "test",
            content: String = "Replaceable content"
        ) -> NDKEvent {
            return EventTestFactory.createEvent(
                kind: kind,
                content: content,
                tags: [["d", dTag]]
            )
        }
        
        /// Creates a parameterized replaceable event
        static func createParameterizedReplaceableEvent(
            kind: Kind = 30023,
            dTag: String = "test-article",
            title: String = "Test Article",
            content: String = "Article content..."
        ) -> NDKEvent {
            return EventTestFactory.createEvent(
                kind: kind,
                content: content,
                tags: [
                    ["d", dTag],
                    ["title", title],
                    ["published_at", String(Timestamp.now)]
                ]
            )
        }
    }
}