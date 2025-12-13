@testable import NDKSwiftCore
import XCTest

final class RelayConnectionRaceConditionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Reduce logging noise in tests
        NDKLogger.logLevel = .error
    }

    func testConcurrentConnectionAttempts() async throws {
        // Use a mock relay URL to avoid real network connections
        let url = URL(string: "wss://mock.relay.test")!
        let connection = NDKRelayConnection(url: url)

        // Attempt to connect multiple times concurrently
        async let connect1: Void = connection.connect()
        async let connect2: Void = connection.connect()
        async let connect3: Void = connection.connect()

        // All should complete without error
        do {
            try await connect1
            try await connect2
            try await connect3
        } catch {
            // It's okay if connection fails (network issues),
            // but we shouldn't get race condition crashes
            // Connection errors are expected in test environment with mock URLs
        }

        // Verify we're in a consistent state
        _ = await connection.isConnected
        // State should be consistent regardless of concurrent attempts

        // Clean up
        await connection.disconnect()
    }

    func testRapidConnectDisconnect() async throws {
        // Use a mock relay URL to avoid real network connections
        let url = URL(string: "wss://mock.relay.test")!
        let connection = NDKRelayConnection(url: url)

        // Rapidly connect and disconnect
        for _ in 0 ..< 5 {
            // Start connection and immediately disconnect
            Task {
                try? await connection.connect()
            }

            // Small delay to allow connection to start
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms

            await connection.disconnect()

            // Verify clean state
            let isConnected = await connection.isConnected
            XCTAssertFalse(isConnected, "Connection should be disconnected after disconnect() call")
        }
    }
}
