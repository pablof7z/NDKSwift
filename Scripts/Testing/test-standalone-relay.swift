#!/usr/bin/env swift sh

// swift-tools-version: 5.9
import PackageDescription

import NDKSwift // @nostr-sdk-ios/NDKSwift == 0.0.1-beta10

import Foundation

// Test against a real relay that supports NIP-77

print("🔬 Testing Negentropy Against Real Relay")
print("======================================\n")

do {
    let ndk = NDK()
    
    // Connect to strfry relay which supports NIP-77
    let relayURL = RelayConstants.nostrBand
    print("Connecting to \(relayURL)...")
    
    try await ndk.connect(to: [relayURL])
    
    // Wait a bit for connection
    try await Task.sleep(nanoseconds: 2_000_000_000)
    
    print("Connected! Testing NIP-77 sync...\n")
    
    // Create a simple filter - just get recent text notes
    let filter = NDKFilter(
        kinds: [1],
        since: Timestamp.now - 3600, // Last hour
        limit: 10
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