#!/usr/bin/env swift

import Foundation
import NDKSwift

// NIP-44 Event-based Encryption Demo
// Shows how to create encrypted direct messages using NIP-44

@main
struct NIP44EventDemo {
    static func main() async {
        print("📨 NIP-44 Direct Message Demo")
        print("=============================\n")
        
        do {
            // Initialize NDK
            let ndk = NDK()
            
            // Create signers for Alice and Bob
            let aliceSigner = try NDKPrivateKeySigner.generate()
            let bobSigner = try NDKPrivateKeySigner.generate()
            
            // Set Alice as the active signer
            ndk.signer = aliceSigner
            
            let alicePubkey = try await aliceSigner.pubkey
            let bobPubkey = try await bobSigner.pubkey
            
            print("👤 Alice: \(String(alicePubkey.prefix(16)))...")
            print("👤 Bob: \(String(bobPubkey.prefix(16)))...\n")
            
            // Create a direct message event (kind 14 for NIP-44 DMs)
            print("Creating encrypted direct message event...")
            
            let messageContent = "Hey Bob! This is a private message using NIP-44 encryption. 🚀"
            
            // Encrypt the message content
            let encryptedContent = try await aliceSigner.encrypt(
                recipient: NDKUser(pubkey: bobPubkey),
                value: messageContent,
                scheme: .nip44
            )
            
            // Create the event
            let dmEvent = NDKEvent(
                pubkey: alicePubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 14, // NIP-44 encrypted direct message
                tags: [
                    ["p", bobPubkey] // Tag the recipient
                ],
                content: encryptedContent
            )
            
            // Sign the event
            try await dmEvent.sign(using: aliceSigner)
            
            print("Event created and signed:")
            print("  ID: \(dmEvent.id ?? "none")")
            print("  Kind: \(dmEvent.kind)")
            print("  Content (encrypted): \(String(dmEvent.content.prefix(50)))...")
            print("  Signature: \(String(dmEvent.sig?.prefix(32) ?? "none"))...\n")
            
            // Simulate Bob receiving and decrypting the event
            print("Bob receives the event and decrypts it...")
            
            // Verify the event signature first
            let isValid = try dmEvent.verify()
            print("  Signature valid: \(isValid ? "✅" : "❌")")
            
            if isValid {
                // Decrypt the content
                let decryptedContent = try await bobSigner.decrypt(
                    sender: NDKUser(pubkey: alicePubkey),
                    value: dmEvent.content,
                    scheme: .nip44
                )
                
                print("  Decrypted message: \"\(decryptedContent)\"\n")
            }
            
            // Show event JSON structure
            print("📄 Event JSON structure:")
            print("========================")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonData = try? encoder.encode(dmEvent),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                // Truncate content for display
                let truncated = jsonString.replacingOccurrences(
                    of: dmEvent.content,
                    with: String(dmEvent.content.prefix(50)) + "..."
                )
                print(truncated)
            }
            
            print("\n💡 Notes:")
            print("- Kind 14 is proposed for NIP-44 encrypted direct messages")
            print("- The 'p' tag identifies the recipient")
            print("- Content is fully encrypted and authenticated")
            print("- Only the sender and recipient can decrypt the message")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}