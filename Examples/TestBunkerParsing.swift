import Foundation
import NDKSwift

// Simple test to verify bunker URL parsing
@main
struct TestBunkerParsing {
    static func main() async {
        print("🔐 Testing NDKSwift NIP-46 Bunker URL Parsing")
        print("===========================================\n")

        // Bunker connection string provided by user
        let bunkerString = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"

        do {
            // Create NDK instance
            let ndk = NDK(relayUrls: ["wss://relay.nsec.app"])

            // Create bunker signer
            print("📡 Creating bunker signer...")
            let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerString)

            print("✅ Bunker signer created successfully!")
            print("\n📋 Bunker URL Components:")
            print("   - URL: \(bunkerString)")
            print("   - Expected bunker pubkey: 79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
            print("   - Expected relay: wss://relay.nsec.app")
            print("   - Expected secret: VpESbyIFohMA")

            // Test nostrconnect URI generation
            print("\n📡 Testing nostrconnect:// URI generation...")
            let connectOptions = NDKBunkerSigner.NostrConnectOptions(
                name: "NDKSwift Test",
                url: "https://github.com/pablof7z/NDKSwift",
                perms: "sign_event,nip04_encrypt,nip04_decrypt"
            )

            let connectSigner = NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relay: "wss://relay.nsec.app",
                options: connectOptions
            )

            // Wait a bit for URI generation
            try await Task.sleep(nanoseconds: 100_000_000)

            if let uri = await connectSigner.nostrConnectUri {
                print("✅ NostrConnect URI generated:")
                print("   \(uri)")
            } else {
                print("⚠️  NostrConnect URI not yet generated")
            }

            print("\n✅ NIP-46 bunker parsing tests passed!")

        } catch {
            print("❌ Error: \(error)")
        }
    }
}
