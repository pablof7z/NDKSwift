import Foundation
import NDKSwift

// Simple test to verify NDKSwift relay connection and event publishing

@main
struct TestPublishFetch {
    static func main() async {
        print("🚀 Starting test...")
        
        do {
            // 1. Create a new nsec (private key)
            let privateKey = Crypto.generatePrivateKey()
            let publicKey = try Crypto.getPublicKey(from: privateKey)
            let nsec = try Bech32.nsec(from: privateKey)
            
            print("✅ Created new identity:")
            print("   nsec: \(nsec)")
            print("   pubkey: \(publicKey)")
            
            // Create signer
            let signer = try NDKPrivateKeySigner(privateKey: privateKey)
            
            // 2. Connect to one relay
            let ndk = NDK(
                relayUrls: ["wss://relay.damus.io"],
                signer: signer
            )
            
            print("\n📡 Connecting to relay...")
            await ndk.connect()
            
            // Wait for connection
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check connection status
            let relay = ndk.relays.first!
            print("   Relay status: \(relay.connectionState)")
            
            // 3. Publish a hello world message
            let helloEvent = NDKEvent(
                pubkey: publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Hello World from NDKSwift test! 🌍"
            )
            
            // Add timestamp tag to make it unique
            helloEvent.addTag(["timestamp", "\(Date().timeIntervalSince1970)"])
            
            // Generate ID and sign
            let eventId = try helloEvent.generateID()
            helloEvent.sig = try await signer.sign(helloEvent)
            
            print("\n📝 Publishing event:")
            print("   ID: \(eventId)")
            print("   Content: \(helloEvent.content)")
            
            // Publish the event
            let publishedRelays = try await ndk.publish(helloEvent)
            print("   Published to \(publishedRelays.count) relays")
            
            // Wait a moment for the event to propagate
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // 4. REQ all notes published by this nsec
            print("\n🔍 Fetching all notes from this pubkey...")
            
            let filter = NDKFilter(
                authors: [publicKey],
                kinds: [EventKind.textNote]
            )
            
            let fetchedEvents = try await ndk.fetchEvents(filter)
            
            print("📨 Found \(fetchedEvents.count) events:")
            for (index, event) in fetchedEvents.enumerated() {
                print("\nEvent #\(index + 1):")
                print("   ID: \(event.id ?? "unknown")")
                print("   Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
                print("   Content: \(event.content)")
                print("   Tags: \(event.tags)")
            }
            
            // Also try with a subscription to see live events
            print("\n📡 Starting subscription for new events...")
            let subscription = ndk.subscribe(filters: [filter])
            
            // Listen for a few seconds
            let subscriptionTask = Task {
                var count = 0
                do {
                    for try await event in subscription {
                        count += 1
                        print("🔔 Live event #\(count): \(event.content)")
                        if count >= 5 {
                            break // Exit after 5 events
                        }
                    }
                } catch {
                    print("❌ Subscription error: \(error)")
                }
                print("🏁 Subscription completed")
            }
            
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            subscriptionTask.cancel()
            
            print("\n✅ Test completed successfully!")
            
        } catch {
            print("❌ Test failed: \(error)")
        }
    }
}