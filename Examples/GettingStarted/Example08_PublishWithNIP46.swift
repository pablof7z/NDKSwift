import Foundation
import NDKSwift

struct Example08_PublishWithNIP46 {
    static func run() async throws {
        print("🔐 NDKSwift Example: Publish with NIP-46 Remote Signer")
        print("======================================================\n")
        
        print("This example demonstrates publishing events using a remote signer (NIP-46)")
        print("You can use either bunker:// or nostrconnect:// URLs\n")
        
        // Step 1: Ask for connection string
        print("Please enter your bunker:// or nostrconnect:// connection string:")
        print("Example: bunker://pubkey?relay=wss://relay.url&secret=xxx")
        print("Example: nostrconnect://pubkey?relay=wss://relay.url&metadata=1")
        print("> ", terminator: "")
        
        guard let connectionString = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !connectionString.isEmpty else {
            print("❌ No connection string provided")
            return
        }
        
        // Step 2: Create NDK instance
        print("\n📡 Setting up NDK...")
        let ndk = NDK(relayUrls: ["wss://relay.primal.net", "wss://relay.damus.io"])
        
        // Step 3: Create bunker signer
        print("🔐 Creating bunker signer...")
        
        let bunkerSigner: NDKBunkerSigner
        
        do {
            if connectionString.hasPrefix("bunker://") {
                bunkerSigner = try NDKBunkerSigner.bunker(ndk: ndk, connectionToken: connectionString)
                print("✅ Created bunker signer")
            } else if connectionString.hasPrefix("nostrconnect://") {
                // For nostrconnect, we need to extract the relay from the URL
                if let url = URL(string: connectionString),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let relayItem = components.queryItems?.first(where: { $0.name == "relay" }),
                   let relay = relayItem.value {
                    
                    let options = NDKBunkerSigner.NostrConnectOptions(
                        name: "NDKSwift Example",
                        url: "https://github.com/nostr-dev-kit/ndk-swift",
                        perms: "sign_event:1"
                    )
                    
                    bunkerSigner = try NDKBunkerSigner.nostrConnect(
                        ndk: ndk,
                        relay: relay,
                        options: options
                    )
                    
                    print("✅ Created nostrconnect signer")
                    print("📋 Connection URI: \(await bunkerSigner.nostrConnectUri ?? "N/A")")
                } else {
                    print("❌ Invalid nostrconnect URL - missing relay parameter")
                    return
                }
            } else {
                print("❌ Invalid connection string. Must start with bunker:// or nostrconnect://")
                return
            }
        } catch {
            print("❌ Failed to create bunker signer: \(error)")
            return
        }
        
        // Set the signer
        ndk.signer = bunkerSigner
        
        // Step 4: Connect to relays
        print("\n📡 Connecting to relays...")
        await ndk.connect()
        
        // Step 5: Connect bunker signer
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
            let profileDataSource = ndk.observe(filter: NDKFilter(authors: [user.pubkey], kinds: [0]), maxAge: 3600)
            // Collect all profile events and use the most recent
            let profileEvents = await profileDataSource.collect(timeout: 3.0)
            if let profileEvent = profileEvents.sorted(by: { $0.createdAt > $1.createdAt }).first,
               let profileData = profileEvent.content.data(using: .utf8),
               let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
                print("📝 Your name: \(profile.name ?? "N/A")")
            }
        } catch {
            print("❌ Failed to connect to remote signer: \(error)")
            return
        }
        
        // Step 6: Publish a simple event
        print("\n📝 Publishing a 'Hello World' event...")
        
        do {
            let (event, publishResult) = try await ndk.publish { builder in
                builder
                    .content("Hello World! 🌍 This event was published using NIP-46 remote signing with NDKSwift")
                    .kind(1) // Text note
                    .tag(["client", "NDKSwift NIP-46 Example"])
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
            print("❌ Failed to publish event: \(error)")
        }
        
        // Step 7: Disconnect
        print("\n🔌 Disconnecting...")
        await bunkerSigner.disconnect()
        await ndk.disconnect()
        
        print("\n📚 Key Concepts:")
        print("- NIP-46 allows signing events with a remote signer")
        print("- Bunker signers can use bunker:// or nostrconnect:// URLs")
        print("- Remote signing may require user approval in the signer app")
        print("- The signer handles the private key securely")
    }
}