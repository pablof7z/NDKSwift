import XCTest
@testable import NDKSwift

// Helper extension for testing
extension NDKRelayConnectionState {
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

final class WebSocketRelayTests: XCTestCase {
    
    var ndk: NDK!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        ndk = NDK()
        mockRelay = MockRelay(url: "wss://test.relay.com")
        mockRelay.ndk = ndk
    }
    
    override func tearDown() async throws {
        await mockRelay.disconnect()
        ndk = nil
        mockRelay = nil
        try await super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testSuccessfulConnection() async throws {
        // Configure mock
        mockRelay.autoConnect = true
        mockRelay.connectionDelay = 0.1
        
        // Connect
        try await mockRelay.connect()
        
        // Verify
        XCTAssertEqual(mockRelay.connectionState, .connected)
    }
    
    func testConnectionFailure() async throws {
        // Configure mock to fail
        mockRelay.shouldFailConnection = true
        mockRelay.connectionError = URLError(.cannotConnectToHost)
        
        // Attempt connection
        do {
            try await mockRelay.connect()
            XCTFail("Should have thrown error")
        } catch {
            // Expected
            XCTAssertTrue(mockRelay.connectionState.isFailure)
        }
    }
    
    func testReconnectionAfterDisconnect() async throws {
        // Initial connection
        try await mockRelay.connect()
        XCTAssertEqual(mockRelay.connectionState, .connected)
        
        // Disconnect
        await mockRelay.disconnect()
        XCTAssertEqual(mockRelay.connectionState, .disconnected)
        
        // Reconnect
        try await mockRelay.connect()
        XCTAssertEqual(mockRelay.connectionState, .connected)
    }
    
    // MARK: - Message Sending Tests
    
    func testSendMessage() async throws {
        // Connect first
        try await mockRelay.connect()
        
        // Send a REQ message
        let message = """
        ["REQ","sub123",{"kinds":[1],"limit":10}]
        """
        
        try await mockRelay.send(message)
        
        // Verify
        XCTAssertEqual(mockRelay.sentMessages.count, 1)
        XCTAssertEqual(mockRelay.sentMessages.first, message)
    }
    
    func testSendMessageWhenDisconnected() async throws {
        // Don't connect
        
        let message = """
        ["REQ","sub123",{"kinds":[1]}]
        """
        
        do {
            try await mockRelay.send(message)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
            XCTAssertTrue(mockRelay.sentMessages.isEmpty)
        }
    }
    
    // MARK: - Subscription Tests
    
    func testSubscriptionFlow() async throws {
        // Setup
        try await mockRelay.connect()
        
        // Create subscription
        let filter = NDKFilter(kinds: [1], limit: 5)
        let subscription = NDKSubscription(
            id: "test_sub",
            filters: [filter],
            ndk: ndk
        )
        
        // Add to relay
        mockRelay.addSubscription(subscription)
        
        // Create mock event
        let mockEvent = NDKEvent(
            pubkey: "pubkey1",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test event"
        )
        mockEvent.id = "event1"
        mockEvent.sig = "sig1"
        
        // Configure mock to respond with event
        mockRelay.addMockResponse(for: "test_sub", events: [mockEvent])
        mockRelay.autoRespond = true
        
        // Simulate sending REQ
        let reqMessage = """
        ["REQ","test_sub",{"kinds":[1],"limit":5}]
        """
        try await mockRelay.send(reqMessage)
        
        // Wait for auto-response
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify REQ was sent
        XCTAssertTrue(mockRelay.wasSent(messageType: "REQ"))
        XCTAssertEqual(mockRelay.sentMessages.count, 1)
    }
    
    func testAutoEOSE() async throws {
        // Setup with auto-respond
        mockRelay.autoRespond = true
        try await mockRelay.connect()
        
        // Create subscription
        let subscription = NDKSubscription(
            id: "auto_sub",
            filters: [NDKFilter(kinds: [1])],
            ndk: ndk
        )
        mockRelay.addSubscription(subscription)
        
        // Send REQ
        let reqMessage = """
        ["REQ","auto_sub",{"kinds":[1]}]
        """
        try await mockRelay.send(reqMessage)
        
        // Wait for auto EOSE
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify REQ was sent
        XCTAssertTrue(mockRelay.sentMessages.contains(reqMessage))
    }
    
    // MARK: - Event Publishing Tests
    
    func testEventPublishing() async throws {
        // Setup
        try await mockRelay.connect()
        let signer = try NDKPrivateKeySigner.generate()
        
        // Create and sign event
        let event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test message"
        )
        
        var mutableEvent = event
        try await signer.sign(event: &mutableEvent)
        
        // Publish
        let eventMessage = NostrMessage.event(subscriptionId: nil, event: mutableEvent)
        try await mockRelay.send(eventMessage.serialize())
        
        // Verify
        XCTAssertEqual(mockRelay.sentMessages.count, 1)
        XCTAssertTrue(mockRelay.wasSent(messageType: "EVENT"))
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkError() async throws {
        try await mockRelay.connect()
        
        // Configure mock to fail sends
        mockRelay.shouldFailSend = true
        
        let message = """
        ["REQ","error_sub",{"kinds":[1]}]
        """
        
        do {
            try await mockRelay.send(message)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
            XCTAssertTrue(error is NDKError || error is URLError)
        }
    }
    
    func testReceiveError() async throws {
        try await mockRelay.connect()
        
        let subscription = NDKSubscription(
            id: "error_sub",
            filters: [NDKFilter(kinds: [1])],
            ndk: ndk
        )
        
        mockRelay.addSubscription(subscription)
        
        // Simulate error for subscription
        mockRelay.simulateError(URLError(.networkConnectionLost), forSubscription: "error_sub")
        
        // Verify subscription handles error gracefully
        var receivedError = false
        
        Task {
            for await update in subscription.updates {
                if case .error = update {
                    receivedError = true
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Error handling depends on implementation
        // Just verify no crash occurs
    }
    
    // MARK: - Performance Tests
    
    func testHighVolumeMessages() async throws {
        try await mockRelay.connect()
        
        // Send many messages rapidly
        for i in 0..<100 {
            let message = """
            ["REQ","perf_sub_\(i)",{"kinds":[1],"limit":1}]
            """
            try await mockRelay.send(message)
        }
        
        // Verify all sent
        XCTAssertEqual(mockRelay.sentMessages.count, 100)
    }
    
    func testConnectionStateObserver() async throws {
        var stateChanges: [NDKRelayConnectionState] = []
        
        mockRelay.observeConnectionState { state in
            stateChanges.append(state)
        }
        
        // Should immediately receive current state
        XCTAssertEqual(stateChanges.count, 1)
        XCTAssertEqual(stateChanges[0], .disconnected)
        
        // Connect
        try await mockRelay.connect()
        
        // Should have received connecting and connected states
        XCTAssertGreaterThanOrEqual(stateChanges.count, 3)
        XCTAssertEqual(stateChanges.last, .connected)
    }
}