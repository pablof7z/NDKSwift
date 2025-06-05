import Foundation
import NDKSwift

// Example demonstrating NIP-46 remote signing with bunker:// and nostrconnect:// flows

@main
struct BunkerDemo {
    static func main() async {
        print("🔐 NDKSwift NIP-46 Bunker Demo")
        print("==============================\n")

        // Test bunker connection string from user
        let bunkerString = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"

        do {
            // Create NDK instance
            let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://nos.lol"])

            // Connect to relays
            try await ndk.connect()
            print("✅ Connected to relays")

            // Test 1: Bunker flow
            print("\n📡 Testing bunker:// flow...")
            try await testBunkerFlow(ndk: ndk, bunkerString: bunkerString)

            // Test 2: NostrConnect flow
            print("\n📡 Testing nostrconnect:// flow...")
            try await testNostrConnectFlow(ndk: ndk)

            // Keep the demo running for a moment
            try await Task.sleep(nanoseconds: 2_000_000_000)

        } catch {
            print("❌ Error: \(error)")
        }
    }

    static func testBunkerFlow(ndk: NDK, bunkerString: String) async throws {
        print("Creating bunker signer with connection string...")

        // Create bunker signer
        let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerString)

        // Set up auth URL handler
        Task {
            await signer.authUrlPublisher.sink { authUrl in
                print("🔗 Auth URL received: \(authUrl)")
                print("   Please open this URL in your browser to authorize the connection")
            }
        }

        // Connect to bunker
        print("Connecting to bunker...")
        do {
            let user = try await signer.connect()
            print("✅ Connected as: \(user.pubkey)")

            // Try to create and sign an event
            var event = NDKEvent(
                pubkey: user.pubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                tags: [],
                content: "Hello from NDKSwift NIP-46 bunker demo!"
            )

            print("\n📝 Signing event...")
            try await signer.sign(event: &event)
            print("✅ Event signed successfully!")
            print("   Signature: \(event.sig ?? "none")")

            // Test encryption
            print("\n🔐 Testing encryption...")
            let recipient = NDKUser(pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
            let encrypted = try await signer.encrypt(recipient: recipient, value: "Secret message", scheme: .nip04)
            print("✅ Encrypted: \(encrypted.prefix(50))...")

        } catch {
            print("❌ Bunker connection failed: \(error)")
        }
    }

    static func testNostrConnectFlow(ndk: NDK) async throws {
        print("Creating nostrconnect signer...")

        // Create nostrconnect signer
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "NDKSwift Demo",
            url: "https://github.com/pablof7z/NDKSwift",
            perms: "sign_event,nip04_encrypt,nip04_decrypt"
        )

        let signer = NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relay: "wss://relay.nsec.app",
            options: options
        )

        // Display the connect URI
        // Get the URI (it's generated asynchronously)
        try await Task.sleep(nanoseconds: 100_000_000) // Give it time to generate
        if let uri = await signer.nostrConnectUri {
            print("📱 NostrConnect URI generated:")
            print("   \(uri)")
            print("\n   Open this URI in a NIP-46 compatible app to authorize")

            // In a real app, you could display this as a QR code
            print("\n   Waiting for connection... (this will timeout after 30 seconds)")

            do {
                let user = try await signer.connect()
                print("✅ Connected as: \(user.pubkey)")
            } catch {
                print("⏱️  Connection timed out or failed: \(error)")
            }
        }
    }
}

// For Package.swift executable target
#if compiler(>=5.9)
    @available(macOS 14.0, *)
    extension BunkerDemo {
        static func run() async {
            await main()
        }
    }
#endif
