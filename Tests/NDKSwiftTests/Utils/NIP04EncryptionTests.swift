import XCTest
@testable import NDKSwift

final class NIP04EncryptionTests: XCTestCase {
    
    // MARK: - Test Vectors from nostr-tools
    
    struct TestVector {
        let privateKey1: String
        let privateKey2: String
        let plaintext: String
        let expectedCiphertext: String?
        
        var publicKey1: String {
            get throws {
                try Crypto.getPublicKey(from: privateKey1)
            }
        }
        
        var publicKey2: String {
            get throws {
                try Crypto.getPublicKey(from: privateKey2)
            }
        }
    }
    
    let testVectors = [
        // Test Vector 1: Basic encryption/decryption
        TestVector(
            privateKey1: "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe",
            privateKey2: "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220",
            plaintext: "nanana",
            expectedCiphertext: "zJxfaJ32rN5Dg1ODjOlEew==?iv=EV5bUjcc4OX2Km/zPp4ndQ=="
        ),
        
        // Test Vector 2: Empty string
        TestVector(
            privateKey1: "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe",
            privateKey2: "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220",
            plaintext: "",
            expectedCiphertext: nil  // Will test round-trip
        ),
        
        // Test Vector 3: Unicode text
        TestVector(
            privateKey1: "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe",
            privateKey2: "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220",
            plaintext: "Hello 👋 Nostr! 🚀",
            expectedCiphertext: nil  // Will test round-trip
        ),
        
        // Test Vector 4: Long text (800 chars)
        TestVector(
            privateKey1: "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe",
            privateKey2: "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220",
            plaintext: String(repeating: "z", count: 800),
            expectedCiphertext: nil  // Will test round-trip
        )
    ]
    
    // MARK: - Basic Encryption/Decryption Tests
    
    func testBasicEncryptionDecryption() async throws {
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let plaintext = "Hello, Nostr!"
        
        // User 1 encrypts for User 2
        let encrypted = try Crypto.nip04Encrypt(message: plaintext, privateKey: privateKey1, publicKey: publicKey2)
        XCTAssertTrue(encrypted.contains("?iv="), "Encrypted message should contain IV separator")
        
        // User 2 decrypts from User 1
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
        XCTAssertEqual(decrypted, plaintext, "Decrypted message should match original")
    }
    
    func testSymmetricEncryption() async throws {
        // Test that encryption is symmetric (either party can encrypt/decrypt)
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let plaintext = "Symmetric test message"
        
        // User 2 encrypts for User 1
        let encrypted = try Crypto.nip04Encrypt(message: plaintext, privateKey: privateKey2, publicKey: publicKey1)
        
        // User 1 decrypts from User 2
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey1, publicKey: publicKey2)
        XCTAssertEqual(decrypted, plaintext, "Symmetric decryption should work")
    }
    
    // MARK: - Test Vector Validation
    
    func testNostrToolsVectors() async throws {
        for (index, vector) in testVectors.enumerated() {
            let publicKey1 = try vector.publicKey1
            let publicKey2 = try vector.publicKey2
            
            // Test encryption and decryption round-trip
            let encrypted = try Crypto.nip04Encrypt(
                message: vector.plaintext,
                privateKey: vector.privateKey1,
                publicKey: publicKey2
            )
            
            let decrypted = try Crypto.nip04Decrypt(
                encrypted: encrypted,
                privateKey: vector.privateKey2,
                publicKey: publicKey1
            )
            
            XCTAssertEqual(decrypted, vector.plaintext, "Round-trip failed for test vector \(index)")
            
            // If we have an expected ciphertext, verify decryption
            // (Note: We can't verify encryption output due to random IV)
            if let expectedCiphertext = vector.expectedCiphertext {
                let decryptedExpected = try Crypto.nip04Decrypt(
                    encrypted: expectedCiphertext,
                    privateKey: vector.privateKey2,
                    publicKey: publicKey1
                )
                XCTAssertEqual(decryptedExpected, vector.plaintext, "Decryption of expected ciphertext failed for vector \(index)")
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyMessage() async throws {
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let encrypted = try Crypto.nip04Encrypt(message: "", privateKey: privateKey1, publicKey: publicKey2)
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
        
        XCTAssertEqual(decrypted, "", "Empty message should encrypt/decrypt properly")
    }
    
    func testLongMessage() async throws {
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let longMessage = String(repeating: "This is a long message. ", count: 100)
        
        let encrypted = try Crypto.nip04Encrypt(message: longMessage, privateKey: privateKey1, publicKey: publicKey2)
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
        
        XCTAssertEqual(decrypted, longMessage, "Long message should encrypt/decrypt properly")
    }
    
    func testUnicodeMessage() async throws {
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let unicodeMessage = "Hello 👋 Nostr! 🚀 测试 テスト"
        
        let encrypted = try Crypto.nip04Encrypt(message: unicodeMessage, privateKey: privateKey1, publicKey: publicKey2)
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey2, publicKey: publicKey1)
        
        XCTAssertEqual(decrypted, unicodeMessage, "Unicode message should encrypt/decrypt properly")
    }
    
    // MARK: - Error Cases
    
    func testInvalidCiphertextFormat() async throws {
        let privateKey1 = "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220"
        
        // Missing IV separator
        XCTAssertThrowsError(try Crypto.nip04Decrypt(
            encrypted: "invalidciphertext",
            privateKey: privateKey2,
            publicKey: publicKey1
        ))
        
        // Invalid base64
        XCTAssertThrowsError(try Crypto.nip04Decrypt(
            encrypted: "not-base64!@#$?iv=alsonotbase64!@#$",
            privateKey: privateKey2,
            publicKey: publicKey1
        ))
    }
    
    // MARK: - Integration Tests
    
    func testWithNDKPrivateKeySigner() async throws {
        let signer1 = try NDKPrivateKeySigner(privateKey: "91ba716fa9e7ea2fcbad360cf4f8e0d312f73984da63d90f524ad61a6a1e7dbe")
        let signer2 = try NDKPrivateKeySigner(privateKey: "96f6fa197aa07477ab88f6981118466ae3a982faab8ad5db9d5426870c73d220")
        
        let user1 = try await signer1.user()
        let user2 = try await signer2.user()
        
        let plaintext = "Test message via signer"
        
        // Check encryption is enabled
        let schemes = await signer1.encryptionEnabled()
        XCTAssertTrue(schemes.contains(.nip04), "NIP-04 should be enabled")
        
        // User 1 encrypts for User 2
        let encrypted = try await signer1.encrypt(recipient: user2, value: plaintext, scheme: .nip04)
        XCTAssertTrue(encrypted.contains("?iv="), "Encrypted message should contain IV separator")
        
        // User 2 decrypts from User 1
        let decrypted = try await signer2.decrypt(sender: user1, value: encrypted, scheme: .nip04)
        XCTAssertEqual(decrypted, plaintext, "Decrypted message should match original")
    }
}