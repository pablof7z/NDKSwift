#!/usr/bin/env swift

import Foundation
import NDKSwift

// Simple NWC balance check with timeout and debugging

@main
struct SimpleNWCTest {
    static func main() async {
        print("🚀 Simple NWC Test")
        print("==================\n")
        
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        do {
            // Initialize NDK with explicit relay configuration
            print("1️⃣ Initializing NDK...")
            let ndk = NDK()
            
            // Add relays before creating wallet
            print("2️⃣ Adding relays...")
            let relayUrls = [
                "wss://relay.primal.net",
                "wss://relay.damus.io", 
                "wss://relay.8333.space/",
                "wss://nos.lol"
            ]
            
            for url in relayUrls {
                try await ndk.addRelay(url)
            }
            
            print("3️⃣ Connecting to relays...")
            try await ndk.connect()
            
            // Wait a bit for connections
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            print("4️⃣ Creating NWC wallet...")
            let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
            
            print("5️⃣ Attempting to connect to wallet service...")
            
            // Create a timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw NDKError.timeout(message: "Connection timeout after 10 seconds")
            }
            
            // Race between connect and timeout
            let connectTask = Task {
                try await wallet.connect()
            }
            
            // Wait for either to complete
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        try await connectTask.value
                        print("✅ Connected successfully!")
                        timeoutTask.cancel()
                    } catch {
                        print("❌ Connect error: \(error)")
                    }
                }
                
                group.addTask {
                    do {
                        try await timeoutTask.value
                        print("⏱️ Connection timed out")
                        connectTask.cancel()
                    } catch {
                        // Ignore cancellation
                    }
                }
            }
            
            // If connected, try to get balance
            if wallet.status == .connected {
                print("\n6️⃣ Fetching balance...")
                let balance = try await wallet.getBalance()
                print("💰 Balance: \(balance) sats")
            }
            
        } catch {
            print("\n❌ Error: \(error)")
        }
        
        print("\n✅ Test completed")
    }
}