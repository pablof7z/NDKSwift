import Foundation
import NDKSwift

/// Example demonstrating payment functionality with NIP-60/61
@main
struct PaymentDemo {
    static func main() async {
        // Initialize NDK
        let ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://relay.nostr.band"
        ])
        
        // Create a signer
        let privateKey = NDKPrivateKeySigner.generatePrivateKey()
        let signer = NDKPrivateKeySigner(privateKey: privateKey)
        ndk.signer = signer
        
        // Configure wallet with payment callbacks
        ndk.walletConfig = NDKWalletConfig(
            lnPay: { request, invoice in
                // This would integrate with a Lightning wallet
                print("Lightning payment requested:")
                print("  Amount: \(request.amount) sats")
                print("  Invoice: \(invoice)")
                print("  Recipient: \(request.recipient.pubkey)")
                
                // In a real implementation, this would:
                // 1. Pay the Lightning invoice
                // 2. Return the payment confirmation with preimage
                
                // For demo, return nil (payment failed)
                return nil
            },
            cashuPay: { request in
                // This would integrate with a Cashu wallet (e.g., CashuSwift)
                print("Cashu payment requested:")
                print("  Amount: \(request.amount) sats")
                print("  Recipient: \(request.recipient.pubkey)")
                
                // In a real implementation, this would:
                // 1. Create Cashu proofs for the amount
                // 2. Lock them to recipient's pubkey if P2PK is supported
                // 3. Return the payment confirmation
                
                // For demo, create a mock nutzap
                let nutzap = NDKNutzap(ndk: ndk)
                nutzap.proofs = [
                    CashuProof(
                        id: "mock-keyset-id",
                        amount: Int(request.amount),
                        secret: "mock-secret",
                        C: "mock-signature"
                    )
                ]
                nutzap.mint = "https://mint.example.com"
                nutzap.setRecipient(request.recipient.pubkey)
                nutzap.comment = request.comment
                
                return NDKCashuPaymentConfirmation(
                    amount: request.amount,
                    recipient: request.recipient.pubkey,
                    timestamp: Date(),
                    nutzap: nutzap
                )
            },
            nutzapAsFallback: true, // Enable automatic fallback to NIP-61
            onPaymentComplete: { confirmation, error in
                if let confirmation = confirmation {
                    print("Payment completed successfully!")
                    print("  Amount: \(confirmation.amount) sats")
                    print("  Recipient: \(confirmation.recipient)")
                } else if let error = error {
                    print("Payment failed: \(error)")
                }
            }
        )
        
        // Connect to relays
        await ndk.connect()
        
        // Example 1: Pay a user who supports Lightning
        print("\n=== Example 1: Lightning Payment ===")
        let lightningUser = ndk.getUser("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2") // jack
        
        do {
            let paymentMethods = try await lightningUser.getPaymentMethods()
            print("User supports payment methods: \(paymentMethods)")
            
            // This will attempt Lightning payment first
            let confirmation = try await lightningUser.pay(
                amount: 1000,
                comment: "Thanks for the great content!"
            )
            print("Payment sent: \(confirmation)")
        } catch {
            print("Payment failed: \(error)")
        }
        
        // Example 2: Pay a user who only supports Cashu
        print("\n=== Example 2: Cashu Payment ===")
        
        // First, let's create a user that signals NIP-61 support
        let cashuUser = ndk.getUser(try! await signer.pubkey)
        
        // Publish a mint list to signal NIP-61 support
        var mintList = NDKCashuMintList(ndk: ndk)
        mintList.addMint("https://mint.minibits.cash")
        mintList.addMint("https://mint.example.com")
        mintList.addRelay("wss://relay.damus.io")
        mintList.setP2PK(true) // Support P2PK
        
        do {
            try await mintList.sign()
            _ = try await ndk.publish(mintList.event)
            print("Published mint list for NIP-61 support")
            
            // Now try to pay this user
            let confirmation = try await cashuUser.pay(
                amount: 500,
                comment: "Here's a nutzap for you!"
            )
            print("Nutzap sent: \(confirmation)")
        } catch {
            print("Failed to send nutzap: \(error)")
        }
        
        // Example 3: Check payment methods for a user
        print("\n=== Example 3: Check Payment Methods ===")
        let randomUser = ndk.getUser("d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a") // fiatjaf
        
        do {
            let methods = try await randomUser.getPaymentMethods()
            if methods.isEmpty {
                print("User doesn't support any payment methods")
            } else {
                print("User supports: \(methods.map { $0.rawValue }.joined(separator: ", "))")
            }
        } catch {
            print("Failed to check payment methods: \(error)")
        }
        
        // Keep the program running for a bit to allow async operations to complete
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Disconnect
        await ndk.disconnect()
    }
}

// Note: In a real application, you would:
// 1. Integrate with CashuSwift for actual Cashu operations
// 2. Integrate with a Lightning wallet (via NWC or direct integration)
// 3. Properly handle wallet state persistence
// 4. Implement proper error handling and retry logic
// 5. Add UI for payment confirmations and wallet management