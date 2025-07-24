#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test script to verify outbox fix

@main
struct TestOutboxFix {
    static func main() async {
        print("Testing NDK Outbox Fix...")
        
        // Create NDK instance
        let ndk = NDK()
        
        // Add a relay
        await ndk.pool.addRelay("wss://relay.damus.io")
        
        // Connect
        await ndk.pool.connectAll()
        
        // Wait a bit for connection
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create a filter with many authors (simulating follow list)
        let testAuthors = (0..<111).map { _ in
            // Generate random pubkeys
            String((0..<64).map { _ in "0123456789abcdef".randomElement()! })
        }
        
        print("Testing with \(testAuthors.count) authors...")
        
        let filter = NDKFilter(
            authors: testAuthors,
            kinds: [1],
            limit: 100
        )
        
        // Test the outbox strategy
        let startTime = Date()
        let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: filter)
        let elapsed = Date().timeIntervalSince(startTime)
        
        print("✅ getOutboxStrategy completed in \(String(format: "%.3f", elapsed))s")
        print("  - Filter breakdown: \(outboxStrategy.filtersByRelay.count) relay-specific filters")
        print("  - Unknown authors: \(outboxStrategy.unknownAuthors.count)")
        print("  - Authors to discover: \(outboxStrategy.authorsToDiscover.count)")
        
        // Verify it doesn't block
        if elapsed < 0.1 {
            print("✅ PASS: Outbox strategy returned quickly (non-blocking)")
        } else {
            print("❌ FAIL: Outbox strategy took too long (\(elapsed)s)")
        }
        
        // Test creating a data source
        print("\nTesting data source creation...")
        let dataSourceStart = Date()
        
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: filter,
            subscriptionId: "test_outbox_fix"
        )
        
        let dataSourceElapsed = Date().timeIntervalSince(dataSourceStart)
        print("✅ DataSource created in \(String(format: "%.3f", dataSourceElapsed))s")
        
        // Check if we can start receiving events
        print("\nWaiting for events (5 seconds)...")
        var eventCount = 0
        
        Task {
            for await event in dataSource.events {
                eventCount += 1
                if eventCount == 1 {
                    print("✅ First event received!")
                }
            }
        }
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        print("\nTest complete!")
        print("Total events received: \(eventCount)")
        
        exit(0)
    }
}