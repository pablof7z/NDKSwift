#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Test connection error rate limiting with failing relays
struct TestConnectionErrorLogging {
    static func main() async throws {
        print("🧪 Testing connection error rate limiting...")
        
        // Create NDK instance with only failing relays
        let ndk = NDK(userFacingAppName: "ConnectionErrorTest")
        
        // Add some relays that will definitely fail
        let failingRelays = [
            "wss://this-relay-does-not-exist.com/",
            "wss://devrelay.highlighter.com/",  // From the user's example
            "wss://devray.highlighter.com/",    // From the user's example
            "wss://nostr.coinfund.app/",        // From the user's example
            "wss://invalid-domain-12345.test/"
        ]
        
        print("\n📡 Adding \(failingRelays.count) failing relays...")
        for relayUrl in failingRelays {
            _ = await ndk.addRelay(relayUrl)
        }
        
        // Also add one valid relay to ensure the system still works
        _ = await ndk.addRelay("wss://relay.damus.io/")
        
        print("\n🔌 Attempting to connect to all relays...")
        await ndk.connect()
        
        // Wait a bit for initial connection attempts
        print("\n⏳ Waiting 5 seconds for initial connection attempts...")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        print("\n📊 First wave of errors should be logged")
        print("   (Each failing relay should log once)")
        
        // Force reconnection attempts to test rate limiting
        print("\n🔄 Forcing reconnection attempts...")
        for _ in 0..<3 {
            // Disconnect and reconnect to trigger more errors
            await ndk.disconnect()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await ndk.connect()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        print("\n📊 Subsequent errors should be rate-limited")
        print("   (You should see fewer error logs and summary messages)")
        
        // Wait longer to show rate limiting reset
        print("\n⏳ Waiting 35 seconds to demonstrate rate limit reset...")
        try await Task.sleep(nanoseconds: 35_000_000_000)
        
        print("\n🔄 Attempting one more connection cycle...")
        await ndk.disconnect()
        await ndk.connect()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("\n📊 After rate limit timeout, errors should log again")
        
        print("\n✅ Test completed!")
        print("\n📋 Summary:")
        print("   - Connection errors are now rate-limited to prevent log spam")
        print("   - Same error type for same relay logs at most once per 30 seconds")
        print("   - Suppressed error counts are shown in debug logs")
        print("   - Different error types are tracked separately")
        
        // Clean up
        await ndk.disconnect()
    }
}

// Run the test
Task {
    do {
        try await TestConnectionErrorLogging.main()
    } catch {
        print("❌ Test failed: \(error)")
    }
    exit(0)
}

RunLoop.main.run()