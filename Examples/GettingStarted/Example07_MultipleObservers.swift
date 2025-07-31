import Foundation
import NDKSwift

// Test multiple observers on the same filter
// This example demonstrates that multiple data sources can observe the same filter
// and continue receiving events even after some observers are released

struct Example07_MultipleObservers {
    static func run() async throws {
        print("🧪 Testing Multiple Observers on Same Filter")
        print("=" * 50)
        
        // Create a test keypair and signer
        let signer = try NDKPrivateKeySigner.generate()
        let testPubkey = try await signer.pubkey
        print("📝 Test pubkey: \(testPubkey)")
        
        // Initialize NDK with the signer
        let relayURL = "wss://relay.primal.net"
        let ndk = NDK(relayUrls: [relayURL])
        ndk.signer = signer
        
        // Connect to relay
        print("\n🔌 Connecting to \(relayURL)...")
        await ndk.connect()
        print("✅ Connected!")
        
        // Allow time for connection to stabilize
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Create filter for kind:1 notes from our test pubkey
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1]
        )
        
        print("\n📊 Creating two observers for the same filter...")
        print("Filter: authors=[\(testPubkey.prefix(8))...], kinds=[1]")
        
        // Create first observer
        let observer1 = ndk.subscribe(
            filter: filter,
            maxAge: 0  // Real-time updates
        )
        print("👁️ Observer 1 created")
        
        // Create second observer
        let observer2 = ndk.subscribe(
            filter: filter,
            maxAge: 0  // Real-time updates
        )
        print("👁️ Observer 2 created")
        
        // Track received events
        var observer1Events: [NDKEvent] = []
        var observer2Events: [NDKEvent] = []
        
        // Start monitoring observer 1
        let observer1Task = Task {
            print("▶️ Observer 1 started monitoring")
            for await event in observer1.events {
                print("👁️1️⃣ Observer 1 received event: \(event.content)")
                observer1Events.append(event)
            }
            print("⏹️ Observer 1 stopped monitoring")
        }
        
        // Start monitoring observer 2
        let observer2Task = Task {
            print("▶️ Observer 2 started monitoring")
            for await event in observer2.events {
                print("👁️2️⃣ Observer 2 received event: \(event.content)")
                observer2Events.append(event)
            }
            print("⏹️ Observer 2 stopped monitoring")
        }
        
        // Give observers time to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Publish first note
        print("\n📤 Publishing first note...")
        let (note1, _) = try await ndk.publish { builder in
            builder
                .content("Test note 1 - Both observers should see this")
                .kind(1)
        }
        print("✅ First note published")
        
        // Wait for events to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check both observers received the event
        print("\n📊 Checking first note reception:")
        print("Observer 1 received \(observer1Events.count) events")
        print("Observer 2 received \(observer2Events.count) events")
        
        if observer1Events.count == 1 && observer2Events.count == 1 {
            print("✅ Both observers received the first note!")
        } else {
            print("❌ Not all observers received the first note")
        }
        
        // Cancel observer 1
        print("\n🛑 Cancelling Observer 1...")
        observer1Task.cancel()
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("✅ Observer 1 cancelled")
        
        // Publish second note
        print("\n📤 Publishing second note...")
        let (note2, _) = try await ndk.publish { builder in
            builder
                .content("Test note 2 - Only observer 2 should see this")
                .kind(1)
        }
        print("✅ Second note published")
        
        // Wait for events to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check observer 2 still receives events
        print("\n📊 Checking second note reception:")
        print("Observer 1 total events: \(observer1Events.count)")
        print("Observer 2 total events: \(observer2Events.count)")
        
        if observer1Events.count == 1 && observer2Events.count == 2 {
            print("✅ Perfect! Observer 1 stopped at 1 event, Observer 2 received both events")
            print("✅ Multiple observers work correctly - subscription remains active when one observer stops")
        } else {
            print("❌ Unexpected results:")
            print("   Observer 1: Expected 1, got \(observer1Events.count)")
            print("   Observer 2: Expected 2, got \(observer2Events.count)")
            if observer2Events.count < 2 {
                print("❌ ISSUE CONFIRMED: Subscription was closed when Observer 1 stopped!")
            }
        }
        
        // Clean up
        observer2Task.cancel()
        
        print("\n✅ Test complete!")
        print("=" * 50)
    }
}

// Helper to repeat string
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}