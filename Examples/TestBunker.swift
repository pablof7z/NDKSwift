import Foundation
import NDKSwift

// Simple test program for NIP-46 bunker connection
@main
struct TestBunker {
    static func main() async {
        print("🔐 Testing NDKSwift NIP-46 Bunker Connection")
        print("==========================================\n")
        
        // Bunker connection string provided by user
        let bunkerString = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"
        
        do {
            // Create NDK instance
            let ndk = NDK(relayUrls: ["wss://relay.nsec.app"])
            
            // Connect to relays
            try await ndk.connect()
            print("✅ Connected to relay")
            
            // Create bunker signer
            print("\n📡 Creating bunker signer...")
            let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerString)
            
            // Connect to bunker
            print("📡 Connecting to bunker...")
            let user = try await signer.connect()
            print("✅ Connected successfully!")
            print("   User pubkey: \(user.pubkey)")
            
            // Test getting public key
            print("\n🔑 Testing getPublicKey...")
            let pubkey = try await signer.pubkey
            print("✅ Public key: \(pubkey)")
            
            // Create and sign a test event
            print("\n📝 Creating and signing test event...")
            var event = NDKEvent(
                pubkey: pubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                tags: [],
                content: "Test message from NDKSwift NIP-46 implementation"
            )
            
            try await signer.sign(event: &event)
            print("✅ Event signed successfully!")
            print("   Event ID: \(event.id ?? "none")")
            print("   Signature: \(event.sig ?? "none")")
            
            // Test encryption/decryption
            print("\n🔐 Testing encryption...")
            let testRecipient = NDKUser(pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
            let plaintext = "Hello from NDKSwift!"
            let encrypted = try await signer.encrypt(recipient: testRecipient, value: plaintext, scheme: .nip04)
            print("✅ Encrypted message: \(encrypted.prefix(50))...")
            
            print("\n🔓 Testing decryption...")
            let decrypted = try await signer.decrypt(sender: testRecipient, value: encrypted, scheme: .nip04)
            print("✅ Decrypted message: \(decrypted)")
            
            print("\n✅ All tests passed! NIP-46 implementation is working correctly.")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}