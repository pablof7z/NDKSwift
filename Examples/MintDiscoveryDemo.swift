#!/usr/bin/swift

import Foundation
import NDKSwift

/// Demonstrates NIP-60 mint discovery functionality
@main
struct MintDiscoveryDemo {
    static func main() async {
        print("🔍 NIP-60 Mint Discovery Demo")
        print("=============================")
        
        do {
            // Initialize NDK
            let ndk = NDK()
            
            // Add public relays
            try await ndk.addRelay("wss://relay.damus.io")
            try await ndk.addRelay("wss://relay.nostr.band")
            try await ndk.addRelay("wss://nos.lol")
            
            // Connect to relays
            try await ndk.connect()
            print("✅ Connected to relays")
            
            // Create wallet with mint discovery
            let wallet = NDKCashuWallet(ndk: ndk)
            
            // 1. Discover all available mints
            print("\n📡 Discovering mints...")
            let discoveredMints = try await wallet.mintDiscovery.discoverMints(limit: 10)
            
            print("\n✨ Found \(discoveredMints.count) mints:")
            for (index, mint) in discoveredMints.enumerated() {
                print("\n\(index + 1). \(mint.announcement.name ?? "Unnamed Mint")")
                print("   URL: \(mint.announcement.mintURL)")
                print("   Trust Score: \(String(format: "%.2f", mint.reputation.trustScore))")
                print("   Publisher: \(mint.event.pubkey)")
                
                if let description = mint.announcement.description {
                    print("   Description: \(description)")
                }
                
                if let units = mint.announcement.units {
                    print("   Units: \(units.joined(separator: ", "))")
                }
            }
            
            // 2. Filter by unit (sats)
            print("\n💰 Discovering sats-only mints...")
            let satMints = try await wallet.mintDiscovery.discoverMints(units: ["sat"], limit: 5)
            
            print("\nFound \(satMints.count) mints supporting sats:")
            for mint in satMints {
                print("  - \(mint.announcement.name ?? mint.announcement.mintURL.absoluteString)")
            }
            
            // 3. Check for suspicious mints
            print("\n🔒 Security Check:")
            for mint in discoveredMints.prefix(3) {
                let suspicious = wallet.mintDiscovery.isSuspiciousMint(mint.announcement.mintURL)
                print("  \(mint.announcement.mintURL): \(suspicious ? "⚠️  SUSPICIOUS" : "✅ OK")")
            }
            
            // 4. Announce a new mint (demo only - requires signer)
            if let signer = NDKPrivateKeySigner.generate() {
                ndk.signer = signer
                
                print("\n📢 Announcing demo mint...")
                let demoAnnouncement = NDKMintAnnouncement(
                    mintURL: URL(string: "https://mint.example.com")!,
                    name: "Demo Mint",
                    description: "A demonstration mint for testing",
                    units: ["sat", "usd"],
                    contact: [["email", "demo@example.com"], ["nostr", "npub1..."]]
                )
                
                let announcementEvent = try await wallet.mintDiscovery.announceMint(demoAnnouncement)
                print("✅ Published mint announcement: \(announcementEvent.id ?? "no-id")")
            }
            
            // 5. Discover specific mint by URL
            if let firstMint = discoveredMints.first {
                print("\n🔎 Looking up specific mint: \(firstMint.announcement.mintURL)")
                let specificMints = try await wallet.mintDiscovery.discoverMint(
                    url: firstMint.announcement.mintURL
                )
                print("Found \(specificMints.count) announcement(s) for this mint")
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print("\n✨ Demo completed!")
    }
}