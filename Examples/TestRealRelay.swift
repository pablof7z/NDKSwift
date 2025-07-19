#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test against a real relay that supports NIP-77

@main
struct TestRealRelay {
    static func main() async {
        print("🔬 Testing Negentropy Against Real Relay")
        print("======================================\n")
        
        do {
            let ndk = NDK()
            let cache = MemoryCache()
            await ndk.setCacheAdapter(cache)
            
            // Connect to strfry relay which supports NIP-77
            let relayURL = "wss://relay.nostr.band"
            print("Connecting to \(relayURL)...")
            
            try await ndk.connect(relayURLs: [relayURL])
            
            // Wait a bit for connection
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            print("Connected! Testing NIP-77 sync...\n")
            
            // Create a simple filter - just get recent text notes
            let filter = NDKFilter(
                kinds: [1],
                limit: 10,
                since: Timestamp.now - 3600 // Last hour
            )
            
            print("Starting sync with filter:")
            print("  kinds: [1]")
            print("  since: last hour")
            print("  limit: 10\n")
            
            // Try the sync
            do {
                let result = try await ndk.syncEvents(
                    filter: filter,
                    relay: relayURL
                )
                
                print("Sync successful!")
                print("  Downloaded: \(result.downloadedEvents.count) events")
                print("  Uploaded: \(result.uploadedEvents.count) events")
                print("  Message rounds: \(result.messageRounds)")
                
            } catch {
                print("Sync error: \(error)")
                
                // If it's a protocol error, let's see what the exact issue is
                if let ndkError = error as? NDKError {
                    print("\nNDKError details: \(ndkError)")
                }
            }
            
            await ndk.disconnect()
            
        } catch {
            print("Error: \(error)")
        }
    }
}