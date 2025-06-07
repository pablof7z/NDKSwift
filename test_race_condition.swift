#!/usr/bin/env swift

import Foundation
import NDKSwift

// Simple test to check if race condition is fixed
@main
struct TestRaceCondition {
    static func main() async {
        print("Testing race condition fix...")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io"])
        ndk.debugMode = true
        
        await ndk.connect()
        
        // Small delay to ensure connection
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        do {
            print("Fetching event...")
            let event = try await ndk.fetchEvent("nevent1qqsdpepvgml06dcsfuuy0x0jhka9jtwpvqrh5ue6qxmtva2xje7n9aqf7whc7")
            
            if let event = event {
                print("✅ Event fetched successfully!")
                print("Event ID: \(event.id ?? "unknown")")
                print("Content: \(String(event.content.prefix(100)))...")
            } else {
                print("❌ Event not found")
            }
        } catch {
            print("❌ Error: \(error)")
        }
        
        await ndk.disconnect()
        print("Test completed")
    }
}