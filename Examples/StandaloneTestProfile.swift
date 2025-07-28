#!/usr/bin/env swift sh

// swift-tools-version: 5.9
import Foundation
@preconcurrency import NDKSwift // ~/test123/NDKSwift

// Test profile loading directly

let relays = [
    "wss://relay.primal.net",
    "wss://relay.damus.io",
    "wss://nos.lol"
]

let ndk = NDK(relayUrls: relays)

Task {
    await ndk.connect()
    
    // Wait for connection
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    
    print("Connected to relays")
    
    // Test pubkey (jack's pubkey)
    let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
    
    print("Fetching profile for pubkey: \(testPubkey)")
    
    // Try direct profile manager
    for await profile in await ndk.profileManager.observe(for: testPubkey, maxAge: TimeConstants.hour) {
        if let profile = profile {
            print("✅ Profile loaded!")
            print("  Name: \(profile.name ?? "none")")
            print("  Display Name: \(profile.displayName ?? "none")")
            print("  Picture: \(profile.picture ?? "none")")
            print("  About: \(String(profile.about?.prefix(50) ?? "none"))...")
            print("  NIP-05: \(profile.nip05 ?? "none")")
        } else {
            print("❌ No profile found")
        }
        break
    }
    
    // Also try with a filter directly
    print("\nTrying direct filter...")
    let filter = NDKFilter(
        authors: [testPubkey],
        kinds: [0]
    )
    
    let dataSource = ndk.observe(filter: filter, maxAge: 0)
    
    for await event in dataSource.events {
        print("✅ Got profile event!")
        print("  Content: \(event.content.prefix(100))...")
        if let profileData = event.content.data(using: .utf8),
           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
            print("  Parsed profile:")
            print("    Name: \(profile.name ?? "none")")
            print("    Picture: \(profile.picture ?? "none")")
        }
        break
    }
    
    exit(0)
}

// Keep process alive
RunLoop.main.run()