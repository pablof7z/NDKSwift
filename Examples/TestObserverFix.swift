#!/usr/bin/env swift

import Foundation
import NDKSwift

// Simple test to verify the observer fix
@main
struct TestObserverFix {
    static func main() async {
        print("=== Testing Observer Fix ===")
        
        // Create NDK with memory cache (default)
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        
        print("Connecting to relay...")
        await ndk.connect()
        
        // Wait for connection
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Create a simple filter
        let filter = NDKFilter(kinds: [1], limit: 5)
        
        print("Creating observer for text notes...")
        let dataSource = ndk.observe(filter: filter)
        
        var receivedCount = 0
        let timeout = 5 // seconds
        
        print("Waiting \(timeout) seconds for events...")
        
        // Create a task to observe events
        let observerTask = Task {
            for await event in dataSource.events {
                receivedCount += 1
                print("✓ Event #\(receivedCount) received - ID: \(event.id.prefix(8))...")
                
                if receivedCount >= 5 {
                    break
                }
            }
        }
        
        // Wait for timeout
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        observerTask.cancel()
        
        print("\n=== Results ===")
        print("Total events received: \(receivedCount)")
        
        if receivedCount > 0 {
            print("✅ Observer fix is working! Events are being delivered to data sources.")
        } else {
            print("❌ No events received - there may still be an issue.")
        }
        
        await ndk.disconnect()
    }
}