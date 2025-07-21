import Foundation
import NDKSwift

/// Simple E2E Test to verify basic functionality
@main
struct E2ETestSimple {
    static func main() async {
        print("🧪 Simple E2E Test")
        print("==================")
        
        // Configure minimal logging
        NDKLogger.logLevel = .info
        
        do {
            // Step 1: Create NDK
            print("\n1. Creating NDK...")
            let ndk = NDK()
            print("✅ NDK created")
            
            // Step 2: Create signer
            print("\n2. Creating signer...")
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            ndk.signer = signer
            print("✅ Signer created: \(String(pubkey.prefix(8)))...")
            
            // Step 3: Add relay
            print("\n3. Adding relay...")
            await ndk.addRelay("wss://relay.damus.io")
            print("✅ Relay added")
            
            // Step 4: Connect
            print("\n4. Connecting...")
            await ndk.connect()
            
            // Give it a moment
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let relays = await ndk.relays
            print("✅ Relays: \(relays.count)")
            for relay in relays {
                print("   - \(relay.url): \(await relay.connectionState)")
            }
            
            // Step 5: Create and publish event
            print("\n5. Creating event...")
            let event = try await ndk.event()
                .content("Simple test - \(Date())")
                .kind(1)
                .build()
            print("✅ Event created: \(event.id)")
            
            // Step 6: Publish
            print("\n6. Publishing...")
            let publishedRelays = try await ndk.publish(event)
            print("✅ Published to \(publishedRelays.count) relays")
            
            // Step 7: Disconnect
            print("\n7. Disconnecting...")
            await ndk.disconnect()
            print("✅ Disconnected")
            
            print("\n✅ Test completed successfully!")
            
        } catch {
            print("\n❌ Error: \(error)")
        }
    }
}