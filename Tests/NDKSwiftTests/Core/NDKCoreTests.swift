@testable import NDKSwift
import XCTest

final class NDKCoreTests: XCTestCase {
    
    // MARK: - Basic Type Tests
    
    func testBasicTypes() {
        // Test basic type aliases
        let pubkey: PublicKey = "abc123"
        let privkey: PrivateKey = "def456"
        let eventId: EventID = "ghi789"
        let sig: Signature = "jkl012"
        let timestamp: Timestamp = 1234567890
        let relay: RelayURL = "wss://relay.example.com"
        let kind: Kind = 1
        
        XCTAssertEqual(pubkey, "abc123")
        XCTAssertEqual(privkey, "def456")
        XCTAssertEqual(eventId, "ghi789")
        XCTAssertEqual(sig, "jkl012")
        XCTAssertEqual(timestamp, 1234567890)
        XCTAssertEqual(relay, "wss://relay.example.com")
        XCTAssertEqual(kind, 1)
    }
    
    func testEventKinds() {
        XCTAssertEqual(EventKind.metadata, 0)
        XCTAssertEqual(EventKind.textNote, 1)
        XCTAssertEqual(EventKind.contacts, 3)
        XCTAssertEqual(EventKind.relayList, 10002)
    }
    
    func testTagStructure() {
        let tag: Tag = ["p", "pubkey123", "relay-url", "petname"]
        XCTAssertEqual(tag.count, 4)
        XCTAssertEqual(tag[0], "p")
        XCTAssertEqual(tag[1], "pubkey123")
    }
    
    // MARK: - NDK Initialization Tests
    
    func testNDKBasicCreation() {
        let ndk = NDK()
        
        XCTAssertNotNil(ndk)
        XCTAssertNil(ndk.signer)
        // cacheAdapter removed from NDK
        XCTAssertNil(ndk.activeUser)
        XCTAssertTrue(ndk.debugMode == false)
    }
    
    func testNDKWithRelays() async {
        let relayUrls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com"
        ]
        
        let ndk = NDK(relayUrls: relayUrls)
        
        // Get relay URLs from the pool
        let poolRelays = ndk.relayPool.relays
        let poolUrls = poolRelays.map { $0.url }
        
        XCTAssertEqual(poolUrls.count, 3)
        XCTAssertTrue(poolUrls.contains("wss://relay1.example.com/"))
        XCTAssertTrue(poolUrls.contains("wss://relay2.example.com/"))
        XCTAssertTrue(poolUrls.contains("wss://relay3.example.com/"))
    }
    
    func testNDKRelayManagement() async {
        let ndk = NDK()
        
        // Add relays
        let relay1 = ndk.relayPool.addRelay("wss://relay1.test.com")
        let relay2 = ndk.relayPool.addRelay("wss://relay2.test.com")
        
        XCTAssertNotNil(relay1)
        XCTAssertNotNil(relay2)
        
        let relays = ndk.relayPool.relays
        XCTAssertEqual(relays.count, 2)
        
        // Remove a relay
        ndk.relayPool.removeRelay("wss://relay1.test.com/")
        
        let remainingRelays = ndk.relayPool.relays
        XCTAssertEqual(remainingRelays.count, 1)
        XCTAssertEqual(remainingRelays.first?.url, "wss://relay2.test.com/")
    }
    
    // MARK: - Event Creation Tests
    
    func testEventCreation() {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            content: "Hello Nostr"
        )
        
        XCTAssertEqual(event.content, "Hello Nostr")
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.pubkey, "test_pubkey")
        XCTAssertEqual(event.createdAt, 1234567890)
        XCTAssertTrue(event.tags.isEmpty)
        XCTAssertNil(event.id)
        XCTAssertNil(event.sig)
    }
    
    func testEventWithTags() {
        let tags: [Tag] = [
            ["p", "pubkey123"],
            ["e", "eventid456", "wss://relay.com"]
        ]
        
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: tags,
            content: "Reply"
        )
        
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.tags[0], ["p", "pubkey123"])
        XCTAssertEqual(event.tags[1], ["e", "eventid456", "wss://relay.com"])
    }
    
    // MARK: - Error Handling Tests
    
    func testNDKError() {
        let error = NDKError.validation("invalid_key", "The key is invalid")
        XCTAssertEqual(error.code, "invalid_key")
        XCTAssertEqual(error.message, "The key is invalid")
    }
    
    func testOKMessage() {
        let okMessage = OKMessage(
            accepted: true,
            message: "Event accepted",
            receivedAt: Date()
        )
        XCTAssertTrue(okMessage.accepted)
        XCTAssertEqual(okMessage.message, "Event accepted")
        XCTAssertNotNil(okMessage.receivedAt)
    }
    
    // MARK: - URL Normalization Tests
    
    func testURLNormalizer() {
        // Test basic normalization
        let normalized1 = URLNormalizer.tryNormalizeRelayUrl("relay.example.com")
        XCTAssertEqual(normalized1, "wss://relay.example.com/")
        
        let normalized2 = URLNormalizer.tryNormalizeRelayUrl("wss://relay.example.com")
        XCTAssertEqual(normalized2, "wss://relay.example.com/")
        
        let normalized3 = URLNormalizer.tryNormalizeRelayUrl("ws://relay.example.com/")
        XCTAssertEqual(normalized3, "ws://relay.example.com/")
        
        // Test with paths (always adds trailing slash)
        let normalized4 = URLNormalizer.tryNormalizeRelayUrl("wss://relay.example.com/path")
        XCTAssertEqual(normalized4, "wss://relay.example.com/path/")
        
        // Test invalid URLs (returns nil for invalid URLs)
        let normalized5 = URLNormalizer.tryNormalizeRelayUrl("not a url")
        XCTAssertNil(normalized5)
    }
}