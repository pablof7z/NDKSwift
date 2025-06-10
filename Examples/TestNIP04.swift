import Foundation
import NDKSwift

@main
struct TestNIP04 {
    static func main() async {
        do {
            let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
            let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
            
            let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
            let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
            
            print("NIP-04 Encryption Test")
            print("=====================")
            print("Public key 1: \(publicKey1)")
            print("Public key 2: \(publicKey2)")
            
            // Test basic encryption/decryption
            let plaintext = "Hello, Nostr!"
            print("\nTest 1: Basic encryption/decryption")
            print("Original message: \(plaintext)")
            
            // User 1 encrypts for User 2
            let encrypted = try Crypto.nip04Encrypt(message: plaintext, privateKey: privateKey1, publicKey: publicKey2)
            print("Encrypted: \(encrypted)")
            
            // User 2 decrypts from User 1
            let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
            print("Decrypted: \(decrypted)")
            print("Success: \(decrypted == plaintext)")
            
            // Test with known test vector
            print("\nTest 2: Known test vector from nostr-tools")
            let testPlaintext = "nanana"
            let testCiphertext = "zJxfaJ32rN5Dg1ODjOlEew==?iv=EV5bUjcc4OX2Km/zPp4ndQ=="
            
            print("Expected plaintext: \(testPlaintext)")
            print("Ciphertext: \(testCiphertext)")
            
            let decryptedVector = try Crypto.nip04Decrypt(encrypted: testCiphertext, privateKey: privateKey2, publicKey: publicKey1)
            print("Decrypted: \(decryptedVector)")
            print("Success: \(decryptedVector == testPlaintext)")
            
            // Test symmetric encryption
            print("\nTest 3: Symmetric encryption")
            let symMessage = "Symmetric test"
            
            // User 2 encrypts for User 1
            let symEncrypted = try Crypto.nip04Encrypt(message: symMessage, privateKey: privateKey2, publicKey: publicKey1)
            print("User 2 encrypted: \(symEncrypted)")
            
            // User 1 decrypts from User 2
            let symDecrypted = try Crypto.nip04Decrypt(encrypted: symEncrypted, privateKey: privateKey1, publicKey: publicKey2)
            print("User 1 decrypted: \(symDecrypted)")
            print("Success: \(symDecrypted == symMessage)")
            
            print("\nAll tests completed!")
            
        } catch {
            print("Error: \(error)")
        }
    }
}