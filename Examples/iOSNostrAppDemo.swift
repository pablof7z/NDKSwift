import Foundation
import NDKSwift

// Simple command-line demo of the iOS app functionality
@main
struct NostrAppDemo {
    static func main() async {
        print("🚀 Nostr App Demo")
        print("================")

        // Create NDK instance
        let ndk = NDK()

        // Generate new account
        print("\n1️⃣ Creating new Nostr account...")
        do {
            let signer = try NDKPrivateKeySigner.generate()
            ndk.signer = signer

            // Display keys
            let npub = try signer.npub
            let nsec = try signer.nsec

            print("✅ Account created!")
            print("📱 Public Key (npub): \(npub)")
            print("🔐 Private Key (nsec): \(nsec)")
            print("⚠️  Keep your private key secure!")
        } catch {
            print("❌ Failed to create account: \(error)")
            return
        }

        // Connect to relay
        print("\n2️⃣ Connecting to relay...")
        // Add relay
        _ = ndk.addRelay("wss://relay.primal.net")

        // Connect to relays
        await ndk.connect()
        print("✅ Connected to wss://relay.primal.net")

        // Publish a message
        print("\n3️⃣ Publishing message to Nostr...")
        let event = NDKEvent(content: "Hello Nostr! This is my first message from the iOS app demo 🎉")
        event.ndk = ndk // Set the NDK instance

        do {
            // Sign and publish
            try await event.sign()
            let publishedRelays = try await ndk.publish(event)

            print("✅ Message published successfully to \(publishedRelays.count) relay(s)!")
            print("📝 Event ID: \(event.id ?? "unknown")")
        } catch {
            print("❌ Failed to publish: \(error)")
        }

        // Wait a moment to ensure message is sent
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("\n✨ Demo completed!")
    }
}

// Helper extension for hex conversion
extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex

        for _ in 0 ..< len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    var bytes: [UInt8] {
        return Array(self)
    }
}
