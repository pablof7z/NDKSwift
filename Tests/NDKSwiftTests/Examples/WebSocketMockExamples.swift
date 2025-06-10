import XCTest
@testable import NDKSwift

/// Example tests demonstrating mock relay usage patterns
final class WebSocketMockExamples: XCTestCase {
    
    // MARK: - Example 1: Basic Connection Testing
    
    func testExample_BasicConnection() async throws {
        // Create mock relay
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        mockRelay.autoConnect = true
        
        // Test connection
        try await mockRelay.connect()
        
        // Verify
        XCTAssertEqual(mockRelay.connectionState, .connected)
    }
    
    // MARK: - Example 2: Testing Connection Failures
    
    func testExample_ConnectionFailureScenarios() async throws {
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        
        // Scenario 1: Network timeout
        mockRelay.shouldFailConnection = true
        mockRelay.connectionError = URLError(.timedOut)
        
        do {
            try await mockRelay.connect()
            XCTFail("Should have failed with timeout")
        } catch {
            XCTAssertTrue(error is NDKError || error is URLError)
        }
        
        // Reset and test scenario 2: Host not found
        mockRelay.reset()
        mockRelay.shouldFailConnection = true
        mockRelay.connectionError = URLError(.cannotFindHost)
        
        do {
            try await mockRelay.connect()
            XCTFail("Should have failed with host not found")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Example 3: Testing Message Flow
    
    func testExample_SubscriptionMessageFlow() async throws {
        // Setup
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        let ndk = NDK()
        mockRelay.ndk = ndk
        mockRelay.autoRespond = true
        
        try await mockRelay.connect()
        
        // Create subscription
        let filter = NDKFilter(
            authors: ["d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],
            kinds: [1],
            limit: 10
        )
        
        let subscription = NDKSubscription(
            id: "example_sub",
            filters: [filter],
            ndk: ndk
        )
        
        mockRelay.addSubscription(subscription)
        
        // Create mock event
        let mockEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Hello from mock!"
        )
        // Set ID and signature for mock
        mockEvent.id = "eventid123"
        mockEvent.sig = "signature123"
        
        // Configure mock response
        mockRelay.addMockResponse(for: "example_sub", events: [mockEvent])
        
        // Send REQ message
        let reqMessage = """
        ["REQ","example_sub",{"authors":["d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],"kinds":[1],"limit":10}]
        """
        try await mockRelay.send(reqMessage)
        
        // Verify REQ was sent
        XCTAssertEqual(mockRelay.sentMessages.count, 1)
        XCTAssertEqual(mockRelay.sentMessages[0], reqMessage)
        
        // Wait for auto-response
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify message was sent
        XCTAssertTrue(mockRelay.wasSent(messageType: "REQ"))
    }
    
    // MARK: - Example 4: Testing Auto-Responses
    
    func testExample_AutoResponseConfiguration() async throws {
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        let ndk = NDK()
        mockRelay.ndk = ndk
        mockRelay.autoRespond = true
        
        // Configure mock responses
        let weatherEvent = NDKEvent(
            pubkey: "weatherbot",
            createdAt: 1234567890,
            kind: 30023,
            tags: [["d", "weather"], ["location", "NYC"]],
            content: "Sunny, 72°F"
        )
        weatherEvent.id = "weather123"
        weatherEvent.sig = "sig123"
        
        mockRelay.addMockResponse(for: "weather_sub", events: [weatherEvent])
        
        try await mockRelay.connect()
        
        // Create subscription
        let subscription = NDKSubscription(
            id: "weather_sub",
            filters: [NDKFilter(kinds: [30023])],
            ndk: ndk
        )
        mockRelay.addSubscription(subscription)
        
        // Send request
        try await mockRelay.send("[\"REQ\",\"weather_sub\",{\"kinds\":[30023],\"#d\":[\"weather\"]}]")
        
        // Auto-response should be triggered
        // EOSE is sent automatically after 100ms
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Verify REQ was sent
        XCTAssertTrue(mockRelay.sentMessages.count > 0)
    }
    
    // MARK: - Example 5: Testing Concurrent Operations
    
    func disabled_testExample_ConcurrentMessageHandling() async throws {
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        let ndk = NDK()
        mockRelay.ndk = ndk
        try await mockRelay.connect()
        
        // Create subscriptions first
        for i in 0..<10 {
            let subscription = NDKSubscription(
                id: "sub_\(i)",
                filters: [NDKFilter(kinds: [1], limit: 1)],
                ndk: ndk
            )
            mockRelay.addSubscription(subscription)
        }
        
        // Send multiple subscriptions concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let message = "[\"REQ\",\"sub_\(i)\",{\"kinds\":[1],\"limit\":1}]"
                    try? await mockRelay.send(message)
                }
            }
        }
        
        // Verify all messages sent
        XCTAssertEqual(mockRelay.sentMessages.count, 10)
        
        // Simulate EOSEs for all subscriptions
        for i in 0..<10 {
            mockRelay.simulateEOSE(forSubscription: "sub_\(i)")
        }
    }
    
    // MARK: - Example 6: Testing Network Interruptions
    
    func testExample_NetworkInterruption() async throws {
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        
        // Connect successfully
        try await mockRelay.connect()
        XCTAssertEqual(mockRelay.connectionState, .connected)
        
        // Send some messages
        try await mockRelay.send("[\"REQ\",\"sub1\",{\"kinds\":[1]}]")
        XCTAssertEqual(mockRelay.sentMessages.count, 1)
        
        // Simulate network interruption by disconnecting
        await mockRelay.disconnect()
        XCTAssertEqual(mockRelay.connectionState, .disconnected)
        
        // Attempts to send should fail
        do {
            try await mockRelay.send("[\"REQ\",\"sub2\",{\"kinds\":[1]}]")
            XCTFail("Should have failed due to disconnection")
        } catch {
            // Expected
        }
        
        // Reconnect
        mockRelay.shouldFailConnection = false
        try await mockRelay.connect()
        XCTAssertEqual(mockRelay.connectionState, .connected)
    }
    
    // MARK: - Example 7: Testing Event Publishing
    
    func testExample_EventPublishingWithOKResponse() async throws {
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        mockRelay.autoRespond = true
        
        try await mockRelay.connect()
        
        // Create and sign an event
        let signer = try NDKPrivateKeySigner.generate()
        var event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test post"
        )
        
        try await signer.sign(event: &event)
        
        // Publish event
        let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
        try await mockRelay.send(eventMessage.serialize())
        
        // Verify EVENT message was sent
        XCTAssertTrue(mockRelay.wasSent(messageType: "EVENT"))
        
        // Mock will process the event
        // In real scenario, you'd check for OK message handling
    }
    
    // MARK: - Example 8: Testing Complex Scenarios
    
    func testExample_CompleteUserScenario() async throws {
        // Setup
        let mockRelay = MockRelay(url: "wss://example.relay.com")
        let ndk = NDK()
        ndk.signer = try NDKPrivateKeySigner.generate()
        mockRelay.ndk = ndk
        mockRelay.autoRespond = true
        
        // 1. Connect to relay
        try await mockRelay.connect()
        
        // 2. Subscribe to feed
        let feedSubscription = NDKSubscription(
            id: "feed",
            filters: [NDKFilter(kinds: [1], limit: 20)],
            ndk: ndk
        )
        mockRelay.addSubscription(feedSubscription)
        
        // 3. Prepare mock events
        var mockEvents: [NDKEvent] = []
        for i in 1...5 {
            let event = NDKEvent(
                pubkey: "author\(i)",
                createdAt: Timestamp(1234567890 + i),
                kind: 1,
                tags: [],
                content: "Post #\(i)"
            )
            event.id = "event\(i)"
            event.sig = "sig\(i)"
            mockEvents.append(event)
        }
        mockRelay.addMockResponse(for: "feed", events: mockEvents)
        
        // Send subscription request
        try await mockRelay.send("[\"REQ\",\"feed\",{\"kinds\":[1],\"limit\":20}]")
        
        // 4. Publish own event
        var myEvent = NDKEvent(
            pubkey: try await ndk.signer!.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "My test post"
        )
        
        try await ndk.signer!.sign(event: &myEvent)
        let publishMessage = NostrMessage.event(subscriptionId: nil, event: myEvent)
        try await mockRelay.send(publishMessage.serialize())
        
        // 5. Close subscription
        try await mockRelay.send("[\"CLOSE\",\"feed\"]")
        
        // Verify complete flow
        XCTAssertTrue(mockRelay.wasSent(messageType: "REQ"))
        XCTAssertTrue(mockRelay.wasSent(messageType: "EVENT"))
        XCTAssertTrue(mockRelay.wasSent(messageType: "CLOSE"))
        XCTAssertGreaterThanOrEqual(mockRelay.sentMessages.count, 3)
    }
}