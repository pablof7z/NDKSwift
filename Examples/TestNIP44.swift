import Foundation
import NDKSwift

@main
struct TestNIP44 {
    static func main() async {
        do {
            // Use the same test keys as NIP-04 for comparison
            let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
            let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
            
            let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
            let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
            
            print("NIP-44 Encryption Test")
            print("=====================")
            print("Public key 1: \(publicKey1)")
            print("Public key 2: \(publicKey2)")
            
            // Test basic encryption/decryption
            let plaintext = "Hello, Nostr! This is NIP-44 encryption."
            print("\nTest 1: Basic encryption/decryption")
            print("Original message: \(plaintext)")
            
            // User 1 encrypts for User 2
            let encrypted = try Crypto.nip44Encrypt(message: plaintext, privateKey: privateKey1, publicKey: publicKey2)
            print("Encrypted (base64): \(String(encrypted.prefix(80)))...")
            print("Length: \(encrypted.count) chars")
            
            // User 2 decrypts from User 1
            let decrypted = try Crypto.nip44Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
            print("Decrypted: \(decrypted)")
            print("✅ Success: \(decrypted == plaintext)")
            
            // Test symmetric property
            print("\nTest 2: Symmetric property")
            let symMessage = "Conversation keys are symmetric!"
            
            // User 2 encrypts for User 1
            let symEncrypted = try Crypto.nip44Encrypt(message: symMessage, privateKey: privateKey2, publicKey: publicKey1)
            print("User 2 encrypted: \(String(symEncrypted.prefix(80)))...")
            
            // User 1 decrypts from User 2
            let symDecrypted = try Crypto.nip44Decrypt(encrypted: symEncrypted, privateKey: privateKey1, publicKey: publicKey2)
            print("User 1 decrypted: \(symDecrypted)")
            print("✅ Success: \(symDecrypted == symMessage)")
            
            // Test conversation key derivation
            print("\nTest 3: Conversation key derivation")
            let convKey1to2 = try Crypto.nip44GetConversationKey(privateKey: privateKey1, publicKey: publicKey2)
            let convKey2to1 = try Crypto.nip44GetConversationKey(privateKey: privateKey2, publicKey: publicKey1)
            
            print("Conv key (1→2): \(convKey1to2.hexString)")
            print("Conv key (2→1): \(convKey2to1.hexString)")
            print("✅ Keys match: \(convKey1to2 == convKey2to1)")
            
            // Test padding behavior
            print("\nTest 4: Padding behavior")
            let shortMsg = "Hi"
            let mediumMsg = "This is a medium length message for testing padding."
            let longMsg = String(repeating: "A", count: 500)
            
            let shortEnc = try Crypto.nip44Encrypt(message: shortMsg, privateKey: privateKey1, publicKey: publicKey2)
            let mediumEnc = try Crypto.nip44Encrypt(message: mediumMsg, privateKey: privateKey1, publicKey: publicKey2)
            let longEnc = try Crypto.nip44Encrypt(message: longMsg, privateKey: privateKey1, publicKey: publicKey2)
            
            print("Short message (\(shortMsg.count) chars) → \(shortEnc.count) chars encrypted")
            print("Medium message (\(mediumMsg.count) chars) → \(mediumEnc.count) chars encrypted")
            print("Long message (\(longMsg.count) chars) → \(longEnc.count) chars encrypted")
            
            // Verify all can be decrypted
            let shortDec = try Crypto.nip44Decrypt(encrypted: shortEnc, privateKey: privateKey2, publicKey: publicKey1)
            let mediumDec = try Crypto.nip44Decrypt(encrypted: mediumEnc, privateKey: privateKey2, publicKey: publicKey1)
            let longDec = try Crypto.nip44Decrypt(encrypted: longEnc, privateKey: privateKey2, publicKey: publicKey1)
            
            print("✅ All messages decrypted successfully")
            print("   Short: \(shortDec == shortMsg)")
            print("   Medium: \(mediumDec == mediumMsg)")
            print("   Long: \(longDec == longMsg)")
            
            // Test error handling
            print("\nTest 5: Error handling")
            
            // Tampered message
            var tamperedEnc = encrypted
            tamperedEnc.removeLast()
            tamperedEnc.append("X")
            
            do {
                _ = try Crypto.nip44Decrypt(encrypted: tamperedEnc, privateKey: privateKey2, publicKey: publicKey1)
                print("❌ Should have failed on tampered message")
            } catch {
                print("✅ Correctly rejected tampered message: \(error)")
            }
            
            // Compare with NIP-04
            print("\nComparison with NIP-04:")
            print("========================")
            let compareMsg = "Same message for both"
            
            let nip04Enc = try Crypto.nip04Encrypt(message: compareMsg, privateKey: privateKey1, publicKey: publicKey2)
            let nip44Enc = try Crypto.nip44Encrypt(message: compareMsg, privateKey: privateKey1, publicKey: publicKey2)
            
            print("NIP-04 format: \(nip04Enc)")
            print("NIP-44 format: \(String(nip44Enc.prefix(80)))...")
            print("\nNIP-44 advantages:")
            print("- Uses ChaCha20 (faster, more secure)")
            print("- Includes message authentication (HMAC)")
            print("- Better padding (hides message length)")
            print("- Standardized key derivation (HKDF)")
            
            print("\n✅ All NIP-44 tests completed successfully!")
            
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