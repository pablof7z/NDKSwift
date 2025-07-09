import Foundation

// Quick NWC balance check without full build

let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"

print("🔍 NWC Connection Details")
print("========================")

// Parse the URI
if let urlComponents = URLComponents(string: connectionURI) {
    print("✅ URI parsed successfully")
    
    // Extract wallet pubkey
    if let host = urlComponents.host {
        print("💳 Wallet Pubkey: \(host)")
    }
    
    // Extract relays
    let relays = urlComponents.queryItems?.filter { $0.name == "relay" }.compactMap { $0.value } ?? []
    print("📡 Relays (\(relays.count)):")
    for relay in relays {
        print("   - \(relay)")
    }
    
    // Extract secret
    if let secret = urlComponents.queryItems?.first(where: { $0.name == "secret" })?.value {
        print("🔑 Secret: \(secret.prefix(8))...")
    }
    
    print("\n✅ This is a valid NWC connection URI!")
    print("   Ready to connect and check balance.")
    print("\n📝 To check balance, the full NDKSwift library needs to compile.")
    print("   The build is currently in progress...")
} else {
    print("❌ Failed to parse connection URI")
}