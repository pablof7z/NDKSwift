import XCTest
@testable import NDKSwift

final class BasicEventFlowE2ETests: XCTestCase {
    let relayURLs = RelayConstants.testRelays
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Configure logging for debugging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false // Too verbose for E2E tests
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
    }
    
    func testBasicEventCreateSignPublishSubscribe() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting basic event flow E2E test")
        
        // Create two NDK instances - publisher and subscriber
        let publisherNDK = NDK(cache: MemoryCache())
        let subscriberNDK = NDK(cache: MemoryCache())
        
        // Create signer for publisher
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        publisherNDK.signer = signer
        
        print("[\(timestamp())] Generated keypair, pubkey: \(pubkey)")
        
        // Connect both instances to relays
        print("[\(timestamp())] Connecting to relays...")
        for relayURL in relayURLs {
            await publisherNDK.addRelay(relayURL)
            await subscriberNDK.addRelay(relayURL)
        }
        
        await publisherNDK.connect()
        await subscriberNDK.connect()
        
        // Wait for connections
        print("[\(timestamp())] Waiting for relay connections...")
        let publisherConnected = await publisherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let subscriberConnected = await subscriberNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard publisherConnected > 0 && subscriberConnected > 0 else {
            XCTFail("Failed to connect to relays")
            return
        }
        
        let connectTime = Date()
        print("[\(timestamp())] Connected to relays in \(connectTime.timeIntervalSince(testStart))s")
        
        // Step 1: Create a simple text note event
        print("[\(timestamp())] Creating text note event...")
        let content = "Hello from NDKSwift E2E test at \(Date())"
        let event = try await NDKEventBuilder(ndk: publisherNDK)
            .content(content)
            .kind(EventKind.textNote)
            .build()
        
        // Verify event properties
        XCTAssertEqual(event.content, content)
        XCTAssertEqual(event.kind, EventKind.textNote)
        XCTAssertEqual(event.pubkey, pubkey)
        XCTAssertNotNil(event.sig)
        XCTAssertNotNil(event.id)
        
        print("[\(timestamp())] Event created with id: \(event.id)")
        
        // Step 2: Set up subscription before publishing
        print("[\(timestamp())] Setting up subscription...")
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10
        )
        
        var receivedEvents: [NDKEvent] = []
        let expectation = XCTestExpectation(description: "Receive published event")
        
        // Use observe() API to subscribe
        let dataSource = subscriberNDK.observe(filter: filter)
        
        // Start observing for events
        Task {
            for await receivedEvent in dataSource.events {
                print("[\(timestamp())] Subscription received event: \(receivedEvent.id)")
                receivedEvents.append(receivedEvent)
                
                // Check if this is our event
                if receivedEvent.id == event.id {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        // Give subscription time to establish
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Step 3: Publish the event
        print("[\(timestamp())] Publishing event...")
        let publishStart = Date()
        let publishedRelays = try await publisherNDK.publish(event)
        let publishTime = Date()
        
        print("[\(timestamp())] Event published to \(publishedRelays.count) relays in \(publishTime.timeIntervalSince(publishStart))s")
        XCTAssertGreaterThan(publishedRelays.count, 0, "Should publish to at least one relay")
        
        // Step 4: Wait for subscription to receive the event
        print("[\(timestamp())] Waiting for subscription to receive event...")
        let subscriptionResult = await XCTWaiter.fulfillment(of: [expectation], timeout: 10.0)
        
        if subscriptionResult == .completed {
            print("[\(timestamp())] Event received via subscription")
            
            // Verify the received event
            let receivedEvent = receivedEvents.first { $0.id == event.id }
            XCTAssertNotNil(receivedEvent)
            
            if let received = receivedEvent {
                XCTAssertEqual(received.content, event.content)
                XCTAssertEqual(received.kind, event.kind)
                XCTAssertEqual(received.pubkey, event.pubkey)
                XCTAssertEqual(received.sig, event.sig)
                XCTAssertEqual(received.createdAt, event.createdAt)
                print("[\(timestamp())] Event verification successful")
            }
        } else {
            XCTFail("Subscription did not receive the event within timeout")
        }
        
        // DataSource will auto-cleanup when out of scope
        
        // Step 5: Test one-shot retrieval with maxAge > 0
        print("[\(timestamp())] Testing one-shot event retrieval...")
        let fetchStart = Date()
        
        // Use observe with maxAge > 0 for one-shot behavior
        let oneShot = subscriberNDK.observe(filter: filter, maxAge: 3600) // 1 hour
        var fetchedEvents: [NDKEvent] = []
        
        // Collect events for a short time
        for await fetchedEvent in oneShot.events {
            fetchedEvents.append(fetchedEvent)
            if fetchedEvents.count >= 5 || Date().timeIntervalSince(fetchStart) > 2.0 {
                break
            }
        }
        
        let fetchTime = Date()
        print("[\(timestamp())] Fetched \(fetchedEvents.count) events in \(fetchTime.timeIntervalSince(fetchStart))s")
        
        // Verify our event is in the fetched results
        let fetchedEvent = fetchedEvents.first { $0.id == event.id }
        XCTAssertNotNil(fetchedEvent, "Published event should be in fetched results")
        
        // Step 6: Test fetching by event ID filter
        print("[\(timestamp())] Testing individual event fetch by ID...")
        let individualFetchStart = Date()
        
        let idFilter = NDKFilter(ids: [event.id])
        let idDataSource = subscriberNDK.observe(filter: idFilter, maxAge: 3600)
        
        var individualEvent: NDKEvent?
        for await fetchedEvent in idDataSource.events {
            if fetchedEvent.id == event.id {
                individualEvent = fetchedEvent
                break
            }
        }
        
        let individualFetchTime = Date()
        print("[\(timestamp())] Individual event fetched in \(individualFetchTime.timeIntervalSince(individualFetchStart))s")
        XCTAssertNotNil(individualEvent)
        XCTAssertEqual(individualEvent?.id, event.id)
        
        // Cleanup
        print("[\(timestamp())] Disconnecting from relays...")
        await publisherNDK.disconnect()
        await subscriberNDK.disconnect()
        
        let totalTime = Date()
        print("[\(timestamp())] Test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testMultipleEventsPublishAndSubscribe() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting multiple events E2E test")
        
        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        ndk.signer = signer
        
        // Connect to relays
        for relayURL in relayURLs {
            await ndk.addRelay(relayURL)
        }
        await ndk.connect()
        
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        guard connected > 0 else {
            XCTFail("Failed to connect to relays")
            return
        }
        
        // Create multiple events
        print("[\(timestamp())] Creating multiple events...")
        var events: [NDKEvent] = []
        let eventCount = 5
        
        for i in 0..<eventCount {
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("Test event #\(i) at \(Date())")
                .kind(EventKind.textNote)
                .tag(["test", "e2e", "batch\(i)"])
                .build()
            events.append(event)
        }
        
        // Publish all events
        print("[\(timestamp())] Publishing \(eventCount) events...")
        let publishStart = Date()
        
        for event in events {
            _ = try await ndk.publish(event)
            print("[\(timestamp())] Published event \(event.id)")
        }
        
        let publishTime = Date()
        print("[\(timestamp())] All events published in \(publishTime.timeIntervalSince(publishStart))s")
        
        // Give relays time to process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Fetch all events with filter
        print("[\(timestamp())] Fetching events with filter...")
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: eventCount,
            tags: ["test": ["e2e"]] // Events tagged with ["test", "e2e"]
        )
        
        let fetchStart = Date()
        // Use observe with maxAge for one-shot fetch
        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
        var fetchedEvents: [NDKEvent] = []
        
        for await event in dataSource.events {
            fetchedEvents.append(event)
            if fetchedEvents.count >= eventCount {
                break
            }
        }
        let fetchTime = Date()
        
        print("[\(timestamp())] Fetched \(fetchedEvents.count) events in \(fetchTime.timeIntervalSince(fetchStart))s")
        
        // Verify all events were fetched
        XCTAssertEqual(fetchedEvents.count, eventCount, "Should fetch all published events")
        
        // Verify each event
        for originalEvent in events {
            let found = fetchedEvents.contains { $0.id == originalEvent.id }
            XCTAssertTrue(found, "Event \(originalEvent.id) should be in fetched results")
        }
        
        await ndk.disconnect()
        let totalTime = Date()
        print("[\(timestamp())] Test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testEventWithComplexTags() async throws {
        print("[\(timestamp())] Starting complex tags E2E test")
        
        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Connect to relays
        for relayURL in relayURLs {
            await ndk.addRelay(relayURL)
        }
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        // Create event with various tag types
        print("[\(timestamp())] Creating event with complex tags...")
        let referencedEventId = "abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234"
        let mentionedPubkey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Event with complex tags #nostr #test")
            .kind(EventKind.textNote)
            .tag(["e", referencedEventId])
            .tagUser(mentionedPubkey)
            .tag(["t", "nostr"])
            .tag(["t", "test"])
            .tag(["subject", "E2E Testing"])
            .tag(["custom", "value1", "value2", "value3"])
            .build()
        
        print("[\(timestamp())] Publishing event with tags: \(event.tags)")
        _ = try await ndk.publish(event)
        
        // Give relays time to process
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Fetch and verify
        print("[\(timestamp())] Fetching event...")
        // Fetch the specific event
        let idFilter = NDKFilter(ids: [event.id])
        let dataSource = ndk.observe(filter: idFilter, maxAge: 3600)
        
        var fetchedEvent: NDKEvent?
        for await foundEvent in dataSource.events {
            if foundEvent.id == event.id {
                fetchedEvent = foundEvent
                break
            }
        }
        
        XCTAssertNotNil(fetchedEvent)
        if let fetched = fetchedEvent {
            // Verify all tags are preserved
            XCTAssertEqual(fetched.tags.count, event.tags.count)
            
            // Check specific tags
            XCTAssertTrue(fetched.tags.contains(["e", referencedEventId]))
            XCTAssertTrue(fetched.tags.contains(["p", mentionedPubkey]))
            XCTAssertTrue(fetched.tags.contains(["t", "nostr"]))
            XCTAssertTrue(fetched.tags.contains(["t", "test"]))
            XCTAssertTrue(fetched.tags.contains(["subject", "E2E Testing"]))
            XCTAssertTrue(fetched.tags.contains(["custom", "value1", "value2", "value3"]))
            
            print("[\(timestamp())] All tags verified successfully")
        }
        
        await ndk.disconnect()
        print("[\(timestamp())] Complex tags test completed")
    }
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}