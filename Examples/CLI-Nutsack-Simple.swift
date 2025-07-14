#!/usr/bin/env swift

import Foundation
import NDKSwift

@main
struct CLINutsackSimple {
    static func main() async throws {
        print("⚡ NIP-60 Wallet Calculator - Simple Demo")
        print("=========================================\n")
        
        // Create a test private key
        let privateKey = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Initialize NDK
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        ndk.signer = signer
        
        print("📡 Connecting to relay...")
        await ndk.connect()
        print("✅ Connected!\n")
        
        // Create wallet
        print("💰 Creating wallet...")
        let wallet = NDKCashuWallet(ndk: ndk)
        
        // Add test mints
        try await wallet.addMint(url: URL(string: "https://testnut.cashu.space")!)
        print("✅ Added test mint\n")
        
        // Load wallet
        try await wallet.load()
        
        // Check balance
        let balance = try await wallet.getBalance()
        print("💵 Current balance: \(balance) sats")
        
        // Get mints
        let mints = await wallet.getMintsInfo()
        print("🏦 Configured mints:")
        for mint in mints {
            print("   - \(mint.url)")
        }
        
        // Get P2PK pubkey for receiving
        if let p2pk = try? await wallet.getP2PKPubkey() {
            print("\n🔑 P2PK pubkey for receiving nutzaps:")
            print("   \(p2pk)")
        }
        
        print("\n✅ Wallet ready!")
        print("   Your pubkey: \(try await signer.pubkey)")
        
        // Keep the program running for a bit to see output
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }
}