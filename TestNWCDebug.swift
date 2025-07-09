import Foundation
import NDKSwift

// Debug NWC connection

@main
struct TestNWCDebug {
    static func main() async {
        print("🔍 NWC Debug Test")
        print("=================\n")
        
        let connectionURI = "nostr+walletconnect://80b93a43f0cd322ebdf4ef349baba9970881298976cfd393cfcec85024f6744c?relay=wss://relay.primal.net&relay=wss://relay.damus.io&relay=wss://relay.8333.space/&relay=wss://nos.lol&secret=a6af65b6b002efeed42cd99b93c7dd3f7642e8708910ff6a233b2d2f77f2b06a"
        
        do {
            // Test URI parsing
            print("1️⃣ Testing URI parsing...")
            let parsedURI = try NWCConnectionURI(uri: connectionURI)
            print("✅ Wallet pubkey: \(parsedURI.walletPubkey)")
            print("✅ Secret: \(parsedURI.secret.prefix(8))...")
            print("✅ Relays: \(parsedURI.relayURLs.count)")
            
            // Test client pubkey derivation
            print("\n2️⃣ Testing client pubkey derivation...")
            let clientPubkey = try parsedURI.clientPubkey()
            print("✅ Client pubkey: \(clientPubkey)")
            
            // Test signer creation
            print("\n3️⃣ Testing signer creation...")
            let signer = try parsedURI.createSigner()
            let signerPubkey = try await signer.pubkey
            print("✅ Signer pubkey: \(signerPubkey)")
            
            // Initialize NDK
            print("\n4️⃣ Initializing NDK...")
            let ndk = NDK()
            
            // Test with explicit signer
            print("\n5️⃣ Creating request builder with explicit signer...")
            let requestBuilder = NWCRequestBuilder(
                ndk: ndk,
                walletPubkey: parsedURI.walletPubkey,
                signer: signer
            )
            
            print("\n✅ All components initialized successfully!")
            print("   Ready to create wallet and connect.")
            
        } catch {
            print("\n❌ Error: \(error)")
            if let ndkError = error as? NDKError {
                print("   Type: \(ndkError)")
            }
        }
    }
}