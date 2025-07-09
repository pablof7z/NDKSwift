import Foundation
import NDKSwift

/// Demonstrates Lightning Zaps and Nutzaps with NDKSwift
@main
struct ZapDemo {
    static func main() async {
        print("⚡ NDKSwift Zap Demo (NIP-57 & NIP-61)")
        print("=" * 40)
        
        do {
            // Create NDK instance
            let ndk = NDK(relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol",
                "wss://relay.primal.net"
            ])
            
            // Generate a signer
            let signer = try NDKPrivateKeySigner.generate()
            ndk.signer = signer
            print("✅ Created signer")
            
            // Connect to relays
            await ndk.connect()
            print("✅ Connected to relays")
            
            // Example recipient (jack)
            let recipientPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
            let recipient = NDKUser(pubkey: recipientPubkey)
            recipient.ndk = ndk
            
            print("\n📊 Checking recipient's zap preferences...")
            
            // Check what zap types the recipient supports
            let lightningSupported = try await ndk.zapManager
                .zapProtocols[.lightning]?
                .canZap(user: recipient) ?? false
            
            let nutzapSupported = try await ndk.zapManager
                .zapProtocols[.nutzap]?
                .canZap(user: recipient) ?? false
            
            print("  Lightning zaps: \(lightningSupported ? "✅" : "❌")")
            print("  Nutzaps: \(nutzapSupported ? "✅" : "❌")")
            
            // Configure payment providers
            print("\n💳 Configuring payment providers...")
            
            // For demo, we'll use QR code provider as fallback
            ndk.zapManager.configureDefaults()
            print("✅ Configured QR code payment provider")
            
            // If you have NWC configured:
            // let nwcWallet = try NDKNWCWallet(uri: "nostr+walletconnect://...", ndk: ndk)
            // ndk.zapManager.configureDefaults(nwcWallet: nwcWallet)
            
            // If you have a Cashu wallet:
            // let cashuWallet = ndk.createCashuWallet()
            // try await cashuWallet.load()
            // ndk.zapManager.configureDefaults(wallet: cashuWallet)
            
            // Example 1: Zap a user
            print("\n⚡ Example 1: Zapping a user...")
            do {
                let zapResult = try await recipient.zap(
                    amountSats: 1000,
                    comment: "Great content! Zapped via NDKSwift 🚀"
                )
                
                print("✅ Zap sent!")
                print("   Type: \(zapResult.type)")
                print("   Amount: \(zapResult.amountSats) sats")
            } catch {
                print("ℹ️ Zap not completed: \(error)")
                print("   (This is expected in demo mode without a real wallet)")
            }
            
            // Example 2: Zap an event
            print("\n⚡ Example 2: Zapping an event...")
            
            // Fetch a recent event from the recipient
            let eventFilter = NDKFilter(
                authors: [recipientPubkey],
                kinds: [1], // Text note
                limit: 1
            )
            
            if let recentEvent = try await ndk.fetchEvent(eventFilter) {
                print("📝 Found event: \(await recentEvent.content.prefix(50))...")
                
                do {
                    let eventZap = try await recentEvent.zap(
                        amountSats: 500,
                        comment: "⚡ Zapping this note!"
                    )
                    
                    print("✅ Event zapped!")
                    print("   Amount: \(eventZap.amountSats) sats")
                } catch {
                    print("ℹ️ Event zap not completed: \(error)")
                }
            }
            
            // Example 3: Fetch zaps
            print("\n📊 Example 3: Fetching zaps...")
            
            let zaps = try await recipient.fetchZaps(includeNutzaps: true)
            print("📈 Found \(zaps.count) zaps for this user")
            
            // Show recent zaps
            for (index, zap) in zaps.prefix(5).enumerated() {
                print("\n  Zap #\(index + 1):")
                print("    Type: \(zap.type)")
                print("    Amount: \(zap.amountSats) sats")
                if let comment = zap.comment {
                    print("    Comment: \(comment)")
                }
                print("    From: \(zap.sender?.prefix(8) ?? "unknown")...")
                print("    Time: \(zap.timestamp)")
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