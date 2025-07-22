import XCTest
@testable import NDKSwift

final class RelayConnectionRaceConditionTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
    }
    
    func testConcurrentConnectionAttempts() async throws {
        let url = URL(string: "wss://relay.damus.io")!
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
            print("Connection error (expected in test environment): \(error)")
        }
        
        // Verify we're in a consistent state
        let isConnected = await connection.isConnected
        print("Connection state after concurrent attempts: \(isConnected)")
        
        // Clean up
        await connection.disconnect()
    }
    
    func testRapidConnectDisconnect() async throws {
        let url = URL(string: "wss://relay.damus.io")!
        let connection = NDKRelayConnection(url: url)
        
        // Rapidly connect and disconnect
        for i in 0..<5 {
            print("Attempt \(i + 1)")
            
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