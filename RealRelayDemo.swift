// Simple demo showing real relay connections with NDKSwift
// Build NDKSwift first: swift build
// Then run: swift -I .build/debug -L .build/debug -lNDKSwift -parse-as-library RealRelayDemo.swift

import Foundation
import NDKSwift

func runDemo() async {
        print("🚀 NDKSwift Real Relay Demo")
        print("===========================\n")
        
        // Create NDK instance with real relay connections
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol"
            ],
            cache: MemoryCache()
        )
        
        print("📡 Connecting to relays...")
        let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5.0)
        
        if connectedCount == 0 {
            print("❌ Failed to connect to any relays")
            return
        }
        
        print("✅ Connected to \(connectedCount) relay(s)!\n")
        
        // Demo 1: Fetch recent notes
        print("📌 Fetching recent notes...")
        let notesData = await ndk.observe(
            filter: NDKFilter(kinds: [1], limit: 3)
        )
        
        var noteCount = 0
        for await event in notesData.events {
            noteCount += 1
            print("\n[Note \(noteCount)]")
            print("  Author: \(String(event.pubkey.prefix(16)))...")
            print("  Content: \(String(event.content.prefix(100)))...")
            print("  Created: \(Date(timeIntervalSince1970: Double(event.createdAt)))")
            
            if noteCount >= 3 {
                break
            }
        }
        
        // Demo 2: Fetch a specific profile
        print("\n\n📌 Fetching Jack Dorsey's profile...")
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        if let profile = try? await ndk.fetchProfile(for: jackPubkey) {
            print("\nProfile found:")
            print("  Name: \(profile.name ?? "Unknown")")
            print("  About: \(String((profile.about ?? "").prefix(100)))...")
            if let picture = profile.picture {
                print("  Picture: \(picture)")
            }
        }
        
        // Demo 3: Real-time streaming
        print("\n\n📌 Streaming live events for 5 seconds...")
        let liveData = await ndk.observe(
            filter: NDKFilter(kinds: [1]),
            maxAge: 0  // Always fetch fresh
        )
        
        let startTime = Date()
        var liveCount = 0
        
        for await event in liveData.events {
            liveCount += 1
            let elapsed = Date().timeIntervalSince(startTime)
            print("  [\(String(format: "%.1f", elapsed))s] New note from \(String(event.pubkey.prefix(8)))...")
            
            if elapsed > 5.0 {
                break
            }
        }
        
        print("\nReceived \(liveCount) live events!")
        print("\n✨ Demo completed!")
}

// Run the demo
Task {
    await runDemo()
    exit(0)
}

RunLoop.main.run()