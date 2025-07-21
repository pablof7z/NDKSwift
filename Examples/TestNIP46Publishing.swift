#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test bunker URL
let bunkerURL = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.primal.net&secret=MswbYwmcYptZ"

@main
struct TestNIP46Publishing {
    static func main() async throws {
        print("🔐 Testing NIP-46 Publishing with NDKSwift")
        print("==========================================\n")
        
        print("Using bunker URL: \(bunkerURL)")
        
        // Create NDK instance
        print("\n📡 Setting up NDK...")
        let ndk = NDK(relayUrls: ["wss://relay.primal.net", "wss://relay.damus.io"])
        
        // Create bunker signer
        print("🔐 Creating bunker signer...")
        
        do {
            let bunkerSigner = try NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerURL)
            print("✅ Created bunker signer")
            
            // Set the signer
            ndk.signer = bunkerSigner
            
            // Connect to relays
            print("\n📡 Connecting to relays...")
            await ndk.connect()
            
            // Connect bunker signer
            print("🔐 Connecting to remote signer...")
            print("⏳ This may require approval in your signer app...")
            
            // Listen for auth URL in case user needs to approve
            Task {
                for await authUrl in await bunkerSigner.authUrlPublisher.values {
                    print("\n🔗 Authorization required!")
                    print("📱 Open this URL in your signer app: \(authUrl)")
                }
            }
            
            do {
                let user = try await bunkerSigner.connect()
                print("✅ Connected to remote signer!")
                print("👤 Your pubkey: \(user.pubkey)")
                
                // Fetch and display user profile if available
                if let profile = try? await user.fetchProfile(ndk) {
                    print("📝 Your name: \(profile.name ?? "N/A")")
                }
                
                // Publish a simple event
                print("\n📝 Publishing a 'Hello World' event...")
                
                let (event, publishResult) = try await ndk.publish { builder in
                    builder
                        .content("Hello World! 🌍 This event was published using NIP-46 remote signing with NDKSwift")
                        .kind(1) // Text note
                        .tag(["client", "NDKSwift NIP-46 Test"])
                }
                
                print("✅ Event published successfully!")
                print("📍 Event ID: \(event.id)")
                print("📊 Published to \(publishResult.count) relay(s):")
                for relay in publishResult {
                    print("   • \(relay.url)")
                }
                
                // Wait a moment before disconnecting
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
            } catch {
                print("❌ Failed to connect to remote signer: \(error)")
            }
            
            // Disconnect
            print("\n🔌 Disconnecting...")
            await bunkerSigner.disconnect()
            await ndk.disconnect()
            
        } catch {
            print("❌ Failed to create bunker signer: \(error)")
        }
        
        print("\n✅ Test completed!")
    }
}