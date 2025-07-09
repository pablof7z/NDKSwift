import Foundation
import NDKSwift

// MARK: - E2E Cashu Test (Simplified)

@main
struct E2ECashuTest {
    static func main() async {
        print("🎯 NDKSwift NIP-60 Wallet E2E Test (Simplified)")
        print("===============================================\n")
        
        do {
            // 1. Initialize NDK
            let signer = try await createOrLoadSigner()
            let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
            ndk.signer = signer
            
            print("📡 Connecting to relay...")
            try await ndk.connect()
            print("✅ Connected!")
            
            let userPubkey = try await signer.pubkey
            print("👤 User: \(userPubkey)\n")
            
            // 2. Create wallet using simplified approach
            print("🔨 Creating Cashu wallet...")
            let wallet = ndk.createCashuWallet()
            
            // 3. Test basic wallet methods
            print("\n⚡ Testing wallet support...")
            let supportsNutzap = wallet.supports(method: NDKPaymentMethod(rawValue: "nip61")!)
            print("Supports nutzap: \(supportsNutzap)")
            
            // 4. Check balance (should be 0 initially)
            print("\n💰 Checking balance...")
            let balance = try await wallet.getBalance()
            print("Balance: \(balance) sats")
            
            // 5. Add test mints (without actual CashuSwift integration)
            print("\n🏪 Adding test mints...")
            try await wallet.mintTokens(amount: 0, mintURL: "https://testnut.cashu.space")
            print("✅ Added testnut mint")
            
            // 6. Save wallet
            print("\n💾 Saving wallet...")
            try await wallet.save()
            print("✅ Wallet saved to Nostr")
            
            // 7. Test wallet reload
            print("\n🔍 Testing wallet reload...")
            try await wallet.load()
            print("✅ Wallet loaded successfully")
            
            print("\n✅ Basic E2E test completed!")
            print("\nNote: This is a simplified test without full CashuSwift integration.")
            print("Full implementation would include:")
            print("- Real token minting from Lightning payments")
            print("- P2PK locking for nutzaps")
            print("- Proof state management")
            print("- Token swapping and transfers")
            
        } catch {
            print("\n❌ Error: \(error)")
            exit(1)
        }
    }
}

// MARK: - Helper Functions

func createOrLoadSigner() async throws -> NDKSigner {
    // Check for existing key in environment
    if let nsec = ProcessInfo.processInfo.environment["NSEC"] {
        print("📑 Using nsec from environment")
        return try NDKPrivateKeySigner(privateKey: nsec)
    }
    
    // Generate a new key for testing
    print("🔑 Generating new test key...")
    let signer = try NDKPrivateKeySigner.generate()
    let pubkey = try await signer.pubkey
    print("   Public key: \(pubkey)")
    
    return signer
}