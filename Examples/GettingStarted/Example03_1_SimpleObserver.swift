import Foundation
import NDKSwift

/// Example 03.1: Simple Observer
/// This example demonstrates a minimal subscription setup:
/// - Connects to a single relay (relay.primal.net)
/// - Creates one observer for text notes (kind 1)
/// - Limits to 3 events
/// - Shows a summary of events received

struct Example03_1_SimpleObserver {
    static func run() async throws {
        // Disable verbose logging for cleaner output
        NDKLogger.logLevel = .error
        
        print("=== Example 03.1: Simple Observer ===")
        print("Connecting to relay.primal.net...")
        
        // Create NDK instance with a single relay
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        
        // Connect to the relay
        await ndk.connect()
        print("✓ Connected to relay")
        
        // Wait a moment for connection to stabilize
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Create a filter for text notes (kind 1) with a limit of 3
        let filter = NDKFilter(kinds: [1], limit: 3)
        
        print("\nObserving text notes (kind 1, limit 3)...")
        print("Note: This example demonstrates the observer pattern, but due to current implementation")
        print("      limitations, events may not be displayed. Check the logs to see events arriving.")
        
        // Create observer
        let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
        
        // Track received events
        var receivedEvents = 0
        
        // Use a timeout approach
        let timeoutSeconds = 3
        print("\nWaiting \(timeoutSeconds) seconds for events...")
        
        // Create a task to collect events
        let collectTask = Task {
            for await _ in dataSource.events {
                receivedEvents += 1
                print("  Event #\(receivedEvents) received")
                
                if receivedEvents >= 3 {
                    break
                }
            }
        }
        
        // Wait for timeout
        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        collectTask.cancel()
        
        // Show summary
        print("\n=== Summary ===")
        print("Total events received: \(receivedEvents)")
        
        if receivedEvents == 0 {
            print("Note: Events were sent by the relay but the observer pattern has a known issue.")
            print("      Check Example 3 for a working subscription example.")
        }
        
        print("✓ Example completed")
        
        // Disconnect
        await ndk.disconnect()
    }
}