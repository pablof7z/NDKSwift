import Foundation
import NDKSwift

// Enable debug mode
let ndk = NDK(relayUrls: ["wss://relay.primal.net", "wss://relay.damus.io"])
ndk.debugMode = true

// Set up logger to see what's happening
NDKLogger.logLevel = .trace
NDKLogger.enabledCategories = [.subscription, .relay, .general]

let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"

print("Testing profile loading for pubkey: \(testPubkey)")

Task {
    await ndk.connect()
    
    // Wait a moment for connection
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    
    print("\n=== Testing NDKDataSource directly ===")
    let filter = NDKFilter(
        authors: [testPubkey],
        kinds: [0]
    )
    
    let dataSource = ndk.observe(filter: filter, maxAge: 0, cachePolicy: .networkOnly)
    
    print("Created data source, waiting for events...")
    
    var receivedEvent = false
    for await event in dataSource.events {
        receivedEvent = true
        print("\n✅ Received profile event!")
        print("  ID: \(event.id)")
        print("  Created at: \(event.createdAt)")
        print("  Content preview: \(event.content.prefix(100))...")
        
        if let profileData = event.content.data(using: .utf8),
           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
            print("\n✅ Successfully parsed profile:")
            print("  Name: \(profile.name ?? "N/A")")
            print("  Display Name: \(profile.displayName ?? "N/A")")
            print("  Picture: \(profile.picture ?? "N/A")")
            print("  NIP-05: \(profile.nip05 ?? "N/A")")
        } else {
            print("❌ Failed to parse profile JSON")
        }
        
        break
    }
    
    if !receivedEvent {
        print("❌ No events received after waiting")
    }
    
    exit(0)
}

RunLoop.main.run()