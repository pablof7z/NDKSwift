import XCTest
@testable import NDKSwift

final class TagAddressableEventTests: XCTestCase {
    var signer: NDKPrivateKeySigner!
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Generate a test private key
        let privateKey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Create NDK instance
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        signer = nil
        ndk = nil
        try await super.tearDown()
    }
    
    func testTagParameterizedReplaceableEvent() async throws {
        // Create a parameterized replaceable event (kind 30023 - long-form content)
        let articleEvent = try await NDKEventBuilder(ndk: ndk)
            .content("This is a long-form article")
            .kind(EventKind.longFormContent)
            .dTag("my-article")
            .tag(["title", "My Article"])
            .build(signer: signer)
        
        // Tag the article event
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Reply to article")
            .kind(EventKind.textNote)
            .tagEvent(articleEvent)
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the 'a' tag was created correctly
        let aTags = replyEvent.tags(withName: "a")
        XCTAssertEqual(aTags.count, 1)
        
        let aTag = aTags[0]
        XCTAssertEqual(aTag[0], "a")
        XCTAssertEqual(aTag[1], "\(EventKind.longFormContent):\(articleEvent.pubkey):my-article")
        XCTAssertEqual(aTag[2], "") // Empty relay hint
    }
    
    func testTagRegularReplaceableEvent() async throws {
        // Create a regular replaceable event (kind 10002 - relay list)
        let relayListEvent = try await NDKEventBuilder(ndk: ndk)
            .content("")
            .kind(EventKind.relayList)
            .tag(["r", "wss://relay.example.com"])
            .build(signer: signer)
        
        // Tag the relay list event
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Reply to relay list")
            .kind(EventKind.textNote)
            .tagEvent(relayListEvent)
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the 'a' tag was created correctly
        let aTags = replyEvent.tags(withName: "a")
        XCTAssertEqual(aTags.count, 1)
        
        let aTag = aTags[0]
        XCTAssertEqual(aTag[0], "a")
        XCTAssertEqual(aTag[1], "\(EventKind.relayList):\(relayListEvent.pubkey):")
        XCTAssertEqual(aTag[2], "") // Empty relay hint
    }
    
    func testTagRegularEventUsesETag() async throws {
        // Create a regular event (kind 1 - text note)
        let textEvent = try await NDKEventBuilder(ndk: ndk)
            .content("This is a regular text note")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        // Tag the regular event
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Reply to text note")
            .kind(EventKind.textNote)
            .tagEvent(textEvent, marker: "reply")
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify an 'e' tag was created (not 'a' tag)
        let eTags = replyEvent.tags(withName: "e")
        let aTags = replyEvent.tags(withName: "a")
        
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(aTags.count, 0)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], textEvent.id)
        XCTAssertEqual(eTag[2], "") // Empty relay hint
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], textEvent.pubkey) // Pubkey hint
    }
    
    func testTagAddressableEventWithRelayHint() async throws {
        // Create a parameterized replaceable event
        let articleEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Article with relay hint")
            .kind(EventKind.longFormContent)
            .dTag("article-with-relay")
            .build(signer: signer)
        
        let preferredRelay = "wss://article.relay.com"
        
        // Tag with explicit relay hint
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Reply with relay hint")
            .kind(EventKind.textNote)
            .tagEvent(articleEvent, preferredRelay: preferredRelay)
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the 'a' tag includes the relay hint
        let aTags = replyEvent.tags(withName: "a")
        XCTAssertEqual(aTags.count, 1)
        
        let aTag = aTags[0]
        XCTAssertEqual(aTag[0], "a")
        XCTAssertEqual(aTag[1], "\(EventKind.longFormContent):\(articleEvent.pubkey):article-with-relay")
        XCTAssertEqual(aTag[2], preferredRelay) // Explicit relay hint
    }
    
    func testTagAddressableEventWithNDKTracking() async throws {
        // Create a parameterized replaceable event
        let articleEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Article with NDK tracking")
            .kind(EventKind.longFormContent)
            .dTag("tracked-article")
            .build(signer: signer)
        
        let trackedRelay = "wss://tracked.relay.com"
        
        // Simulate the event being tracked from a relay
        await ndk.eventTracker.setSourceRelay(eventId: articleEvent.id, relay: trackedRelay)
        
        // Tag with NDK (should pick up relay from tracker)
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Reply with tracked relay")
            .kind(EventKind.textNote)
            .tagEvent(articleEvent)
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the 'a' tag includes the tracked relay
        let aTags = replyEvent.tags(withName: "a")
        XCTAssertEqual(aTags.count, 1)
        
        let aTag = aTags[0]
        XCTAssertEqual(aTag[0], "a")
        XCTAssertEqual(aTag[1], "\(EventKind.longFormContent):\(articleEvent.pubkey):tracked-article")
        XCTAssertEqual(aTag[2], trackedRelay) // Tracked relay hint
    }
    
    func testDirectTagAddressableEventMethod() async throws {
        // Create a parameterized replaceable event
        let articleEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Direct tag method test")
            .kind(EventKind.longFormContent)
            .dTag("direct-tag-article")
            .build(signer: signer)
        
        // Use the direct tagAddressableEvent method
        let replyBuilder = await NDKEventBuilder(ndk: ndk)
            .content("Direct tag method reply")
            .kind(EventKind.textNote)
            .tagAddressableEvent(articleEvent, preferredRelay: "wss://direct.relay.com")
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the 'a' tag
        let aTags = replyEvent.tags(withName: "a")
        XCTAssertEqual(aTags.count, 1)
        
        let aTag = aTags[0]
        XCTAssertEqual(aTag[0], "a")
        XCTAssertEqual(aTag[1], "\(EventKind.longFormContent):\(articleEvent.pubkey):direct-tag-article")
        XCTAssertEqual(aTag[2], "wss://direct.relay.com")
    }
}