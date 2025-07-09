import Foundation
import NDKSwift

/// Demo showing the new decoupled zap architecture
@main
struct ZapDemoV2 {
    static func main() async {
        print("🎯 NDKSwift Zap Demo V2 - Decoupled Architecture")
        print("================================================\n")
        
        do {
            // Create NDK instance
            let privateKey = generatePrivateKey()
            let signer = try NDKPrivateKeySigner(privateKey: privateKey)
            let ndk = NDK(signer: signer)
            
            // Connect to relays
            ndk.addRelay("wss://relay.damus.io")
            ndk.addRelay("wss://nos.lol")
            
            print("📡 Connecting to relays...")
            await ndk.connect()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Get the new zap manager
            let zapManager = ndk.zapManagerV2
            
            // Demo 1: Configure with NWC
            print("\n⚡ Demo 1: Lightning Zap with NWC")
            print("---------------------------------")
            
            // In a real app, you'd get this from user input
            let nwcURI = "nostr+walletconnect://..."
            if let nwcWallet = try? NDKNWCWallet(connectionURI: nwcURI, ndk: ndk) {
                // Register NWC as a payment provider
                zapManager.register(provider: NWCPaymentProvider(nwcWallet: nwcWallet))
                
                // Find a user to zap
                let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
                let jack = ndk.getUser(jackPubkey)
                
                // Zap will automatically use Lightning protocol + NWC payment
                let result = try await zapManager.zap(
                    to: jack,
                    amountSats: 1000,
                    comment: "Testing new architecture!"
                )
                
                print("✅ Zap sent via NWC!")
                print("   Event: \(result.sentEvent.id ?? "unknown")")
            }
            
            // Demo 2: QR Code fallback
            print("\n📱 Demo 2: Lightning Zap with QR Code")
            print("-------------------------------------")
            
            // Configure QR code provider with custom handlers
            let qrProvider = QRCodePaymentProvider(
                displayQRCode: { invoice in
                    print("\n┌─────────────────────────────┐")
                    print("│  Scan this QR code to pay:  │")
                    print("│                             │")
                    print("│  [QR CODE WOULD BE HERE]    │")
                    print("│                             │")
                    print("│  Invoice: \(invoice.prefix(20))...  │")
                    print("└─────────────────────────────┘")
                },
                waitForConfirmation: {
                    // In a real app, this would wait for user confirmation
                    print("\nWaiting for payment...")
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    
                    // Simulate payment
                    return "fake_preimage_123"
                }
            )
            
            // Clear providers and add only QR
            zapManager.paymentProviders.removeAll()
            zapManager.register(provider: qrProvider)
            
            // Try to zap - will use QR code since no wallet available
            let pablo = ndk.getUser("your_pubkey_here")
            
            do {
                let result = try await zapManager.zap(
                    to: pablo,
                    amountSats: 500,
                    comment: "QR code zap!"
                )
                
                print("✅ Zap sent after QR payment!")
            } catch {
                print("❌ QR zap cancelled or failed: \(error)")
            }
            
            // Demo 3: Multiple providers with selection
            print("\n🎯 Demo 3: Provider Selection")
            print("-----------------------------")
            
            // Register multiple providers
            zapManager.configureDefaults()  // Adds QR as fallback
            
            // Check available providers for a Lightning payment
            let dummyRequest = LightningInvoiceRequest(
                invoice: "lnbc...",
                amountSats: 100,
                recipient: "test"
            )
            
            let available = await zapManager.availableProviders(for: dummyRequest)
            print("Available payment providers:")
            for provider in available {
                print("  - \(provider.displayName) (id: \(provider.id))")
            }
            
            // Demo 4: Future Cashu wallet integration
            print("\n🥜 Demo 4: Future Cashu Integration")
            print("-----------------------------------")
            print("When NDKCashuWallet is ready, you can:")
            print("")
            print("// Register Cashu payment provider")
            print("let cashuProvider = CashuPaymentProvider(wallet: cashuWallet)")
            print("zapManager.register(provider: cashuProvider)")
            print("")
            print("// Now Lightning zaps can be paid with Cashu!")
            print("// And Nutzaps can be paid with Lightning!")
            
            print("\n✨ Demo complete!")
            print("\nKey benefits of new architecture:")
            print("- Any payment method can fund any zap type")
            print("- Easy to add new payment providers")
            print("- Clean separation of concerns")
            print("- Future-proof and extensible")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// Helper to generate a random private key
func generatePrivateKey() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}