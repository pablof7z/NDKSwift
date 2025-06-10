#!/usr/bin/env swift

import Foundation
import NDKSwift

// NIP-44 Encryption Demo
// This demo shows how to use NIP-44 encryption for secure messaging

@main
struct NIP44Demo {
    static func main() async {
        print("🔐 NIP-44 Encryption Demo")
        print("========================\n")
        
        do {
            // Create two users with their own signers
            print("Creating two users (Alice and Bob)...")
            let aliceSigner = try NDKPrivateKeySigner.generate()
            let bobSigner = try NDKPrivateKeySigner.generate()
            
            let alicePubkey = try await aliceSigner.pubkey
            let bobPubkey = try await bobSigner.pubkey
            
            print("Alice's pubkey: \(String(alicePubkey.prefix(16)))...")
            print("Bob's pubkey: \(String(bobPubkey.prefix(16)))...\n")
            
            // Create NDK instance
            let ndk = NDK()
            
            // Create user objects
            let alice = NDKUser(pubkey: alicePubkey)
            let bob = NDKUser(pubkey: bobPubkey)
            
            // Test message
            let originalMessage = "Hello Bob! This is a secret message encrypted with NIP-44 🔒"
            print("Original message: \(originalMessage)\n")
            
            // Alice encrypts a message for Bob using NIP-44
            print("Alice encrypting message for Bob using NIP-44...")
            let encryptedMessage = try await aliceSigner.encrypt(
                recipient: bob,
                value: originalMessage,
                scheme: .nip44
            )
            print("Encrypted (base64): \(String(encryptedMessage.prefix(50)))...\n")
            
            // Bob decrypts the message from Alice
            print("Bob decrypting message from Alice...")
            let decryptedMessage = try await bobSigner.decrypt(
                sender: alice,
                value: encryptedMessage,
                scheme: .nip44
            )
            print("Decrypted message: \(decryptedMessage)\n")
            
            // Verify the message matches
            if decryptedMessage == originalMessage {
                print("✅ Success! Messages match perfectly.")
            } else {
                print("❌ Error: Decrypted message doesn't match original.")
            }
            
            // Compare with NIP-04 (deprecated)
            print("\n📊 Comparison with NIP-04:")
            print("==========================")
            
            // NIP-04 encryption
            let nip04Encrypted = try await aliceSigner.encrypt(
                recipient: bob,
                value: originalMessage,
                scheme: .nip04
            )
            
            print("NIP-04 format: \(nip04Encrypted)")
            print("NIP-44 format: \(String(encryptedMessage.prefix(100)))...")
            
            print("\n🔍 Key differences:")
            print("- NIP-44 uses ChaCha20 (faster, more secure)")
            print("- NIP-44 has better padding (hides message length)")
            print("- NIP-44 uses HMAC for authentication")
            print("- NIP-44 is the modern standard for Nostr encryption")
            
            // Demonstrate conversation key derivation
            print("\n🔑 Technical Details:")
            print("=====================")
            
            let conversationKey = try Crypto.nip44GetConversationKey(
                privateKey: aliceSigner.privateKeyValue,
                publicKey: bobPubkey
            )
            print("Conversation key (hex): \(conversationKey.hexString)")
            print("Note: Same key is derived by both parties (Alice->Bob = Bob->Alice)")
            
            // Show supported encryption schemes
            print("\n📋 Supported encryption schemes:")
            let supportedSchemes = await aliceSigner.encryptionEnabled()
            for scheme in supportedSchemes {
                print("  - \(scheme.rawValue)")
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// Extension to make Data printable as hex
extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}