import Foundation
import CryptoSwift
@testable import NDKSwift

struct TestEvents {
    // Helper to create a properly formatted event ID
    private static func calculateEventId(pubkey: String, createdAt: Timestamp, kind: Kind, tags: [Tag], content: String) -> String {
        let eventData: [Any] = [0, pubkey, Int(createdAt), kind, tags, content]
        let serialized = try! JSONSerialization.data(withJSONObject: eventData, options: [.sortedKeys, .withoutEscapingSlashes])
        return serialized.sha256().hexString
    }
    
    // Valid events for testing (unsigned)
    static func unsignedTextNoteEvent(from pubkey: String = TestKeys.alicePublicKey, content: String = "Hello, Nostr!") -> NDKEvent {
        let createdAt = Timestamp(1640995200)
        let kind: Kind = 1
        let tags: [Tag] = []
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: "" // Empty sig for unsigned events
        )
    }
    
    static func unsignedProfileEvent(from pubkey: String = TestKeys.alicePublicKey) -> NDKEvent {
        let metadata = """
        {"name":"Alice","about":"Test user","picture":"https://example.com/alice.jpg","nip05":"alice@example.com"}
        """
        let createdAt = Timestamp(1640995200)
        let kind: Kind = 0
        let tags: [Tag] = []
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: metadata)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: metadata,
            sig: ""
        )
    }
    
    static func unsignedReactionEvent(to eventId: String, from pubkey: String = TestKeys.bobPublicKey) -> NDKEvent {
        let createdAt = Timestamp(1640995300)
        let kind: Kind = 7
        let tags: [Tag] = [["e", eventId], ["p", TestKeys.alicePublicKey]]
        let content = "+"
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
    }
    
    static func unsignedReplyEvent(to eventId: String, from pubkey: String = TestKeys.bobPublicKey) -> NDKEvent {
        let createdAt = Timestamp(1640995400)
        let kind: Kind = 1
        let tags: [Tag] = [["e", eventId, "", "reply"], ["p", TestKeys.alicePublicKey]]
        let content = "Great post!"
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
    }
    
    static func unsignedDeleteEvent(eventIds: [String], from pubkey: String = TestKeys.alicePublicKey) -> NDKEvent {
        let createdAt = Timestamp(1640995500)
        let kind: Kind = 5
        let tags: [Tag] = eventIds.map { ["e", $0] }
        let content = "These posts were deleted"
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
    }
    
    static func unsignedDmEvent(from sender: String = TestKeys.alicePublicKey, to recipient: String = TestKeys.bobPublicKey) -> NDKEvent {
        let createdAt = Timestamp(1640995600)
        let kind: Kind = 4
        let tags: [Tag] = [["p", recipient]]
        let content = "This is a private message"
        
        let id = calculateEventId(pubkey: sender, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: sender,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
    }
    
    static func eventWithMultipleTags() -> NDKEvent {
        let pubkey = TestKeys.alicePublicKey
        let createdAt = Timestamp(1640995900)
        let kind: Kind = 1
        let tags: [Tag] = [
            ["e", "event1"],
            ["e", "event2", "wss://relay.example.com"],
            ["p", TestKeys.bobPublicKey],
            ["p", TestKeys.charliePublicKey],
            ["t", "nostr"],
            ["t", "test"],
            ["a", "30023:\(TestKeys.alicePublicKey):article"],
            ["d", "unique-identifier"]
        ]
        let content = "Post with many tags"
        
        let id = calculateEventId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
    }
    
    // Pre-signed events for testing verification
    static func preSignedValidEvent() -> NDKEvent {
        // Use async context to create and sign the event
        let semaphore = DispatchSemaphore(value: 0)
        var signedEvent: NDKEvent?
        
        Task {
            let signer = MockSigner(privateKey: TestKeys.alicePrivateKey)
            let builder = NDKEventBuilder(content: "Hello, Nostr!")
                .kind(1)  // textNote
                .createdAt(Timestamp(1640995200))
            
            signedEvent = try? await builder.build(signer: signer, generateContentTags: false)
            semaphore.signal()
        }
        
        semaphore.wait()
        
        guard let event = signedEvent else {
            fatalError("Failed to create pre-signed valid event")
        }
        
        return event
    }
    
    static func preSignedInvalidEvent() -> NDKEvent {
        let valid = preSignedValidEvent()
        return NDKEvent(
            id: valid.id,
            pubkey: valid.pubkey,
            createdAt: valid.createdAt,
            kind: valid.kind,
            tags: valid.tags,
            content: valid.content,
            sig: "0000000000000000000000000000000000000000000000000000000000000000" // Invalid signature
        )
    }
    
    // Convenience method for tests that need a simple text note event
    static func textNoteEvent(from pubkey: String = TestKeys.alicePublicKey, content: String = "Hello, Nostr!") -> NDKEvent {
        return unsignedTextNoteEvent(from: pubkey, content: content)
    }
}