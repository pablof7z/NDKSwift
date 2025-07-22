import Foundation
import NDKSwift

struct Example02_PublishEvent {
    static func run() async throws {
        print("📝 NDKSwift Example: Publish Event")
        print("==================================\n")
        
        // Step 1: Create NDK and connect
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        
        // Step 2: Generate a new key pair for this example
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let pubkey = try await signer.pubkey
        print("✅ Generated new keypair")
        print("📍 Public key: \(String(pubkey.prefix(16)))...")
        
        // Step 3: Connect to relay
        print("\n📡 Connecting to relay...")
        await ndk.connect()
        
        // Step 4: Create and publish a simple text note
        print("\n📝 Publishing a text note...")
        
        let (event, publishResult) = try await ndk.publish { builder in
            builder
                .content("Hello Nostr! This is my first event published with NDKSwift 🚀")
                .tag(["client", "NDKSwift Example"])
        }
        
        print("✅ Event published!")
        print("📍 Event ID: \(event.id)")
        print("📊 Published to \(publishResult.count) relay(s)")
        
        // Step 5: Publish a different kind of event (kind 1 is text note, kind 0 is metadata)
        print("\n👤 Publishing profile metadata...")
        
        let metadata = NDKUserProfile(
            name: "NDKSwift Example User",
            displayName: "Example User",
            about: "This is a test profile created by NDKSwift examples",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: "https://github.com/nostr-dev-kit/ndk-swift"
        )
        
        // Create metadata event manually
        let profileContent = try JSONCoding.encode(metadata)
        let profileString = String(data: profileContent, encoding: .utf8)!
        
        let (metadataEvent, _) = try await ndk.publish { builder in
            builder
                .content(profileString)
                .kind(EventKind.metadata)
        }
        print("✅ Profile metadata published!")
        print("📍 Event ID: \(metadataEvent.id)")
        
        // Step 6: Disconnect
        await ndk.disconnect()
        
        print("\n📚 Key Concepts:")
        print("- Events need to be signed (NDK handles this automatically)")
        print("- The publish method returns both the event and publish results")
        print("- Different event kinds serve different purposes (kind 0 = metadata, kind 1 = text)")
        print("- Tags add metadata to events")
    }
}