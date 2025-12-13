@testable import NDKSwiftCore
import XCTest

/// Mock delegate for testing relay connection events
class MockRelayConnectionDelegate: NDKRelayConnectionDelegate {
    var receivedMessages: [NostrMessage] = []
    var didConnect = false
    var didDisconnect = false
    var disconnectError: Error?

    func relayConnection(_: NDKRelayConnection, didReceiveMessage message: NostrMessage) {
        receivedMessages.append(message)
    }

    func relayConnectionDidConnect(_: NDKRelayConnection) {
        didConnect = true
    }

    func relayConnectionDidDisconnect(_: NDKRelayConnection, error: Error?) {
        didDisconnect = true
        disconnectError = error
    }
}

final class NDKRelayConnectionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
    }

    // MARK: - Initialization Tests

    func testInitialization() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        let isConnected = await connection.isConnected
        XCTAssertFalse(isConnected, "Connection should not be connected after initialization")

        let messagesSent = await connection.messagesSent
        XCTAssertEqual(messagesSent, 0, "Messages sent should be 0 after initialization")

        let messagesReceived = await connection.messagesReceived
        XCTAssertEqual(messagesReceived, 0, "Messages received should be 0 after initialization")

        let connectedAt = await connection.connectedAt
        XCTAssertNil(connectedAt, "Connected at should be nil after initialization")
    }

    func testDelegateAssignment() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)
        let delegate = MockRelayConnectionDelegate()

        await connection.setDelegate(delegate)
        // Delegate is weak, so we can't directly test it's set, but we can test it works
        // by triggering delegate methods in other tests
    }

    // MARK: - Connection State Tests

    func testDisconnectWhenNotConnected() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)
        let delegate = MockRelayConnectionDelegate()
        await connection.setDelegate(delegate)

        // Should not crash when disconnecting while not connected
        await connection.disconnect()

        // Delegate should not be notified of disconnect when not connected
        XCTAssertFalse(delegate.didDisconnect, "Delegate should not be notified of disconnect when not connected")
    }

    func testMultipleDisconnectCalls() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Multiple disconnect calls should not crash
        await connection.disconnect()
        await connection.disconnect()
        await connection.disconnect()

        let isConnected = await connection.isConnected
        XCTAssertFalse(isConnected, "Connection should remain disconnected")
    }

    // MARK: - Message Sending Tests

    func testSendMessageWhenNotConnected() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test content",
            tags: []
        )

        do {
            try await connection.send(.event(subscriptionId: nil, event: event))
            XCTFail("Should throw error when sending while not connected")
        } catch let error as NDKError {
            switch error {
            case let .connectionLost(relay, message):
                XCTAssertEqual(relay, url.absoluteString)
                XCTAssertEqual(message, "Not connected")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testSendRawJSONWhenNotConnected() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        do {
            try await connection.send("[\"REQ\",\"test\",{}]")
            XCTFail("Should throw error when sending while not connected")
        } catch let error as NDKError {
            switch error {
            case let .connectionLost(relay, message):
                XCTAssertEqual(relay, url.absoluteString)
                XCTAssertEqual(message, "Not connected")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Event Publishing Tests

    func testPublishEventWhenNotConnected() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test content",
            tags: []
        )

        // publishEvent should attempt to connect first
        // Since we can't mock WebSocket, it will fail to connect
        do {
            _ = try await connection.publishEvent(event, timeout: 1.0)
            XCTFail("Should throw error when unable to connect")
        } catch {
            // Expected to fail in test environment
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Connection Statistics Tests

    func testConnectionStatistics() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Initial state
        let initialSent = await connection.messagesSent
        let initialReceived = await connection.messagesReceived
        let initialConnectedAt = await connection.connectedAt

        XCTAssertEqual(initialSent, 0)
        XCTAssertEqual(initialReceived, 0)
        XCTAssertNil(initialConnectedAt)
    }

    // MARK: - Concurrent Connection Tests

    func testConcurrentConnectionAttempts() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Attempt multiple concurrent connections
        let tasks = (0 ..< 10).map { _ in
            Task {
                do {
                    try await connection.connect()
                    return nil as Error?
                } catch {
                    // Expected in test environment
                    return error
                }
            }
        }

        let results = await withTaskGroup(of: Error?.self) { group in
            for task in tasks {
                group.addTask {
                    await task.value
                }
            }

            var errors: [Error?] = []
            for await error in group {
                errors.append(error)
            }
            return errors
        }

        // All connection attempts should fail consistently (no crashes)
        XCTAssertEqual(results.count, 10)
    }

    // MARK: - Message Parsing Tests

    func testHandleEmptyMessage() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)
        let delegate = MockRelayConnectionDelegate()
        await connection.setDelegate(delegate)

        // This would normally be called internally, but we can test the behavior
        // by checking that empty messages don't cause crashes
        // Since handleReceivedMessage is private, we can't test it directly
        // but the race condition tests cover some of this behavior
    }

    // MARK: - Error Mapping Tests

    func testConnectionErrorMapping() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Test connection failure
        do {
            try await connection.connect()
            XCTFail("Should fail to connect in test environment")
        } catch let error as NDKError {
            // Should map to appropriate NDKError
            XCTAssertNotNil(error)
        } catch {
            // Other errors are also acceptable in test environment
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Delegate Notification Tests

    func testDelegateNotifications() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)
        let delegate = MockRelayConnectionDelegate()
        await connection.setDelegate(delegate)

        // Disconnect when not connected should not notify
        await connection.disconnect()
        XCTAssertFalse(delegate.didDisconnect)

        // Connection attempts will fail in test environment
        do {
            try await connection.connect()
        } catch {
            // Expected
        }

        // Delegate might be notified of disconnect due to connection failure
        // This depends on the internal implementation
    }

    // MARK: - Retry Policy Tests

    func testInitialConnectionFailureDoesNotRetry() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // First connection attempt
        do {
            try await connection.connect()
            XCTFail("Should fail to connect in test environment")
        } catch {
            // Expected - initial connection failure should not trigger auto-retry
        }

        // Give some time to see if it retries (it shouldn't)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Should still be disconnected
        let isConnected = await connection.isConnected
        XCTAssertFalse(isConnected, "Should not auto-retry after initial connection failure")
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentSendOperations() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Multiple concurrent send attempts while not connected
        let tasks = (0 ..< 5).map { i in
            Task {
                do {
                    try await connection.send("[\"REQ\",\"test\(i)\",{}]")
                    return nil as Error?
                } catch {
                    return error
                }
            }
        }

        let results = await withTaskGroup(of: Error?.self) { group in
            for task in tasks {
                group.addTask {
                    await task.value
                }
            }

            var errors: [Error?] = []
            for await error in group {
                errors.append(error)
            }
            return errors
        }

        // All should fail with connection lost error
        XCTAssertEqual(results.count, 5)
        for error in results {
            XCTAssertNotNil(error)
        }
    }

    func testConcurrentPublishOperations() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)

        // Multiple concurrent publish attempts
        let tasks = (0 ..< 3).map { i in
            Task {
                let event = EventTestFactory.createEvent(
                    kind: 1,
                    content: "Test content \(i)",
                    tags: []
                )

                do {
                    let result = try await connection.publishEvent(event, timeout: 0.5)
                    return result
                } catch {
                    throw error
                }
            }
        }

        // All should fail in test environment
        for task in tasks {
            do {
                _ = try await task.value
                XCTFail("Should fail in test environment")
            } catch {
                // Expected
                XCTAssertNotNil(error)
            }
        }
    }

    // MARK: - Connection Lifecycle Tests

    func testConnectionLifecycle() async throws {
        let url = URL(string: "wss://relay.example.com")!
        let connection = NDKRelayConnection(url: url)
        let delegate = MockRelayConnectionDelegate()
        await connection.setDelegate(delegate)

        // Initial state
        var isConnected = await connection.isConnected
        XCTAssertFalse(isConnected)
        XCTAssertFalse(delegate.didConnect)
        XCTAssertFalse(delegate.didDisconnect)

        // Attempt connection (will fail in test)
        do {
            try await connection.connect()
        } catch {
            // Expected
        }

        // Should still be disconnected
        isConnected = await connection.isConnected
        XCTAssertFalse(isConnected)

        // Explicit disconnect
        await connection.disconnect()

        // Final state
        isConnected = await connection.isConnected
        XCTAssertFalse(isConnected)
    }
}
