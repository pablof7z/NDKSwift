import XCTest
@testable import NDKSwift

final class TagEventRelayHintTests: XCTestCase {
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
    
    func testTagEventWithoutNDK() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        // Tag the event without NDK (should use empty relay)
        let replyBuilder = await ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
            .tagEvent(testEvent, marker: "reply")
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the e tag was created correctly
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], "") // Empty relay hint
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
    }
    
    func testTagEventWithPreferredRelay() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        let preferredRelay = "wss://relay.example.com"
        
        // Tag the event with explicit relay
        let replyBuilder = await ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
            .tagEvent(testEvent, marker: "reply", preferredRelay: preferredRelay)
        
        let replyEvent = try await replyBuilder.build(signer: signer)
        
        // Verify the e tag was created correctly
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], preferredRelay) // Explicit relay hint
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
    }
    
    func testTagEventWithNDKRelayTracking() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        let relayUrl = "wss://relay.tracked.com"
        
        // Simulate the event being tracked from a relay
        await ndk.eventTracker.setSourceRelay(eventId: testEvent.id, relay: relayUrl)
        
        // Tag the event with NDK (should pick up relay from tracker)
        let replyBuilder = ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
        
        let replyBuilderWithTag = await replyBuilder.tagEvent(testEvent, marker: "reply")
        let replyEvent = try await replyBuilderWithTag.build(signer: signer)
        
        // Verify the e tag was created correctly with tracked relay
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], relayUrl) // Relay from tracker
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
    }
    
    func testTagEventWithNDKButNoTrackedRelay() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        // Don't track the event in any relay
        
        // Tag the event with NDK (should use empty relay since no tracking)
        let replyBuilder = ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
        
        let replyBuilderWithTag = await replyBuilder.tagEvent(testEvent, marker: "reply")
        let replyEvent = try await replyBuilderWithTag.build(signer: signer)
        
        // Verify the e tag was created correctly with empty relay
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], "") // Empty relay hint
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
    }
    
    func testTagEventPreferredRelayOverridesNDK() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        let trackedRelay = "wss://relay.tracked.com"
        let preferredRelay = "wss://relay.preferred.com"
        
        // Simulate the event being tracked from a relay
        await ndk.eventTracker.setSourceRelay(eventId: testEvent.id, relay: trackedRelay)
        
        // Tag the event with both NDK and explicit relay (preferred should win)
        let replyBuilder = ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
        
        let replyBuilderWithTag = await replyBuilder.tagEvent(testEvent, marker: "reply", preferredRelay: preferredRelay)
        let replyEvent = try await replyBuilderWithTag.build(signer: signer)
        
        // Verify the e tag was created correctly with preferred relay
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], preferredRelay) // Preferred relay should override tracked
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
    }
    
    func testTagEventWithMultipleRelaysSeen() async throws {
        // Create a test event
        let testEvent = try await ndk.event()
            .content("Test event")
            .kind(EventKind.textNote)
            .build(signer: signer)
        
        let relay1 = "wss://relay1.com"
        let relay2 = "wss://relay2.com"
        let relay3 = "wss://relay3.com"
        
        // Simulate the event being seen on multiple relays
        await ndk.eventTracker.setSourceRelay(eventId: testEvent.id, relay: relay1) // First one is source
        await ndk.eventTracker.markSeen(eventId: testEvent.id, relay: relay2)
        await ndk.eventTracker.markSeen(eventId: testEvent.id, relay: relay3)
        
        // Tag the event with NDK (should use source relay)
        let replyBuilder = ndk.event()
            .content("Reply to test event")
            .kind(EventKind.textNote)
        
        let replyBuilderWithTag = await replyBuilder.tagEvent(testEvent, marker: "reply")
        let replyEvent = try await replyBuilderWithTag.build(signer: signer)
        
        // Verify the e tag uses the source relay (not just any seen relay)
        let eTags = replyEvent.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        
        let eTag = eTags[0]
        XCTAssertEqual(eTag[0], "e")
        XCTAssertEqual(eTag[1], testEvent.id)
        XCTAssertEqual(eTag[2], relay1) // Source relay should be used
        XCTAssertEqual(eTag[3], "reply") // Marker
        XCTAssertEqual(eTag[4], testEvent.pubkey) // Author pubkey
        
        // Verify that all relays were tracked
        let seenRelays = await ndk.eventTracker.getSeenOnRelays(eventId: testEvent.id)
        XCTAssertEqual(seenRelays.count, 3)
        XCTAssertTrue(seenRelays.contains(relay1))
        XCTAssertTrue(seenRelays.contains(relay2))
        XCTAssertTrue(seenRelays.contains(relay3))
    }
}