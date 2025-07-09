import Foundation
import NDKSwift

// Simple balance check without @main

print("🚀 Simple Balance Check")
print("======================")

let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"

// Use Task to run async code
Task {
    do {
        print("\n1️⃣ Initializing NDK...")
        let ndk = NDK()
        
        print("2️⃣ Adding relays...")
        ndk.addRelay("wss://relay.primal.net")
        ndk.addRelay("wss://relay.damus.io")
        ndk.addRelay("wss://relay.8333.space/")
        ndk.addRelay("wss://nos.lol")
        
        print("3️⃣ Connecting to relays...")
        await ndk.connect()
        
        print("4️⃣ Creating NWC wallet...")
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
        
        print("5️⃣ Connecting to wallet...")
        try await wallet.connect()
        
        print("6️⃣ Getting balance...")
        let balance = try await wallet.getBalance()
        print("\n💰 Balance: \(balance) sats")
        
        print("\n✅ Success!")
        exit(0)
        
    } catch {
        print("\n❌ Error: \(error)")
        exit(1)
    }
}

// Keep the program running
RunLoop.main.run()