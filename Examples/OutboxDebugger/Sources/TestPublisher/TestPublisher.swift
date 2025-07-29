import Foundation
import NDKSwift

@main
struct TestPublisher {
    static func main() async throws {
        // Configure logger
        NDKLogger.configure(logLevel: .info, enabledCategories: [
            .relay,
            .subscription
        ])
        
        print("🚀 Starting Test Event Publisher")
        
        // Get npub from command line arguments or use default
        let args = CommandLine.arguments
        let testSeckey = args.count > 1 ? args[1] : "nsec1j4c6269y9w0q2er2xjw8sv2ehyrtfxq3jwgdlxj6qfn8z4gjsq5qfvfk99"
        
        print("🔑 Using secret key: \(testSeckey)")
        
        // Initialize NDK
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://relay.primal.net",
                "wss://f7z.io"
            ]
        )
        
        // Create signer
        let signer = try NDKPrivateKeySigner(privateKey: testSeckey)
        ndk.signer = signer
        
        print("\n📡 Connecting to relays...")
        await ndk.connect()
        
        // Wait for connections
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("✅ Connected to relays")
        print("📝 Publishing test event...")
        
        // Create and publish test event using builder pattern
        let (event, results) = try await ndk.publish { builder in
            builder
                .kind(1)
                .content("Test event from OutboxDebugger at \(Date())")
        }
        
        print("\n📤 Published to \(results.count) relays:")
        for relay in results {
            print("   • \(relay.url): ✅")
        }
        
        print("\n✅ Event published!")
        print("   ID: \(event.id)")
        print("   Pubkey: \(event.pubkey)")
    }
}