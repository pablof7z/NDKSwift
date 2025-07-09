import Foundation
import NDKSwift

/// Demonstrates Cashu wallet usage with NDKSwift
@main
struct CashuDemo {
    static func main() async {
        print("🏦 NDKSwift Cashu Wallet Demo")
        print("=" * 40)
        
        do {
            // Create NDK instance
            let ndk = NDK(relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol"
            ])
            
            // Generate or load a signer
            let signer = try NDKPrivateKeySigner.generate()
            ndk.signer = signer
            print("✅ Created signer with pubkey: \(try await signer.pubkey)")
            
            // Connect to relays
            await ndk.connect()
            print("✅ Connected to relays")
            
            // Create a Cashu wallet
            let wallet = ndk.createCashuWallet(walletId: "demo-wallet")
            print("\n📱 Created Cashu wallet")
            
            // Try to load existing wallet state
            print("🔄 Loading wallet state...")
            do {
                try await wallet.load()
                let balance = try await wallet.getBalance()
                print("✅ Wallet loaded, balance: \(balance) sats")
            } catch {
                print("ℹ️ No existing wallet found, starting fresh")
            }
            
            // Example: Mint tokens from a test mint
            print("\n🪙 Minting tokens from test mint...")
            print("⚡ Please pay the Lightning invoice that will be displayed")
            print("💡 For testing, you can use https://testnut.cashu.space which auto-settles")
            
            let mintAmount: Int64 = 100
            let testMint = "https://testnut.cashu.space"
            
            do {
                try await wallet.mintTokens(amount: mintAmount, mintURL: testMint)
                print("✅ Successfully minted \(mintAmount) sats!")
                
                let newBalance = try await wallet.getBalance()
                print("💰 New balance: \(newBalance) sats")
                
                // Save wallet state
                try await wallet.save()
                print("💾 Wallet state saved to Nostr")
            } catch {
                print("❌ Failed to mint tokens: \(error)")
            }
            
            // Example: Send a nutzap
            print("\n⚡ Sending a nutzap...")
            
            // Create a recipient (could be any Nostr user)
            let recipientPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2" // jack
            let recipient = NDKUser(pubkey: recipientPubkey)
            recipient.ndk = ndk
            
            // Configure zap manager
            ndk.zapManager.configureDefaults(wallet: wallet)
            
            // Send a nutzap
            do {
                let zapResult = try await ndk.zapManager.zap(
                    to: recipient,
                    amountSats: 21,
                    comment: "Testing nutzaps with NDKSwift! 🎉",
                    preferredType: .nutzap
                )
                
                print("✅ Nutzap sent!")
                print("   Amount: \(zapResult.amountSats) sats")
                print("   Type: \(zapResult.type)")
                if let nutzapEvent = zapResult.nutzapEvent {
                    print("   Event ID: \(await nutzapEvent.id ?? "unknown")")
                }
                
                let finalBalance = try await wallet.getBalance()
                print("💰 Final balance: \(finalBalance) sats")
            } catch {
                print("❌ Failed to send nutzap: \(error)")
            }
            
            // Disconnect
            await ndk.disconnect()
            print("\n👋 Demo completed!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// Helper to repeat a string
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}