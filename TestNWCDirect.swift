#!/usr/bin/env swift -I .build/debug -L .build/debug -lNDKSwift -F .build/debug

import Foundation
import NDKSwift

print("Test started")

let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"

Task {
    do {
        print("Creating NDK...")
        let ndk = NDK()
        print("NDK created")
        
        print("Creating wallet...")
        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
        print("Wallet created")
        
        print("Connecting...")
        try await wallet.connect()
        print("Connected!")
        
        let balance: Int64 = try await wallet.getBalance()
        print("💰 Balance: \(balance) sats")
        
        exit(0)
    } catch {
        print("❌ Error: \(error)")
        exit(1)
    }
}

RunLoop.main.run()