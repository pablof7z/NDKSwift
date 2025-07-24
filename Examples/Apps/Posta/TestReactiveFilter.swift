import Foundation
import NDKSwift

// Simple test to verify reactive filter works
@main
struct TestReactiveFilter {
    static func main() async {
        print("🚀 Starting reactive filter test...")
        
        // Create NDK instance
        let ndk = NDK(relayUrls: ["wss://relay.damus.io"])
        
        // Create test signer
        let signer = try! NDKPrivateKeySigner.generate()
        
        // Connect to relays
        print("📡 Connecting to relays...")
        await ndk.connect()
        
        // Wait a moment for connection
        try! await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Start session
        print("🔐 Starting session...")
        let sessionData = try! await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .progressive
            )
        )
        
        print("✅ Session started - follows: \(sessionData.followList.count)")
        
        // Create reactive filter
        print("🔍 Creating reactive filter...")
        let filter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                print("🏗️ ReactiveFilter builder called - follows: \(sessionData.followList.count)")
                return NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [1],
                    limit: 10
                )
            }
        )
        
        // Observe with reactive filter
        print("👁️ Starting observation...")
        let stream = ndk.observe(filter)
        
        // Consume events
        print("📨 Waiting for events...")
        var eventCount = 0
        for await event in stream {
            eventCount += 1
            print("📝 Event \(eventCount): \(event.id) from \(event.pubkey.prefix(8))...")
            
            if eventCount >= 5 {
                print("✅ Received 5 events, stopping...")
                break
            }
        }
        
        print("🔚 Test complete")
    }
}