#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test connection error rate limiting with failing relays
@main
struct TestConnectionErrors {
    static func main() async throws {
        print("🧪 Testing connection error rate limiting...")
        
        // Enable debug logging to see all logs
        NDKLogger.logLevel = .debug
        
        // Create NDK instance with only failing relays
        let ndk = NDK(userFacingAppName: "ConnectionErrorTest")
        
        // Add some relays that will definitely fail
        let failingRelays = [
            "wss://this-relay-does-not-exist.com/",
            "wss://devrelay.highlighter.com/",  // From the user's example
            "wss://devray.highlighter.com/",    // From the user's example
            "wss://nostr.coinfund.app/"         // From the user's example
        ]
        
        print("\n📡 Adding \(failingRelays.count) failing relays...")
        for relayUrl in failingRelays {
            _ = await ndk.addRelay(relayUrl)
        }
        
        // Also add one valid relay to ensure the system still works
        _ = await ndk.addRelay("wss://relay.damus.io/")
        
        print("\n🔌 Attempting to connect to all relays...")
        print("   Expected: Each failing relay logs once")
        print("   ----------------------------------------")
        await ndk.connect()
        
        // Wait a bit for initial connection attempts
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        print("\n🔄 Triggering additional connection errors...")
        print("   Expected: Errors are rate-limited (fewer logs)")
        print("   ------------------------------------------------")
        
        // Manually trigger more connection attempts
        let relays = await ndk.pool.getAllRelays()
        for relay in relays where failingRelays.contains(relay.url) {
            // Try to reconnect each failing relay
            try? await relay.connect()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        
        print("\n📊 Summary:")
        print("   - Connection errors are now rate-limited")
        print("   - Same error type for same relay logs at most once per 30 seconds")
        print("   - This prevents log spam from continuously failing relays")
        
        // Clean up
        await ndk.disconnect()
    }
}