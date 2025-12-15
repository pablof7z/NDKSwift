@testable import NDKSwiftCore
import XCTest

final class NIP04EncryptionTests: XCTestCase {
    // Test vectors
    let testPrivateKey1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let testPublicKey1 = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    let testPrivateKey2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let testPublicKey2 = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

    // MARK: - Shared Secret Tests

    func testComputeSharedSecret_validKeys() throws {
        // Compute shared secret from both sides
        let secret1 = try NIP04.computeSharedSecret(privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let secret2 = try NIP04.computeSharedSecret(privateKey: testPrivateKey2, pubkey: testPublicKey1)

        // Both should produce the same shared secret
        XCTAssertEqual(secret1, secret2)
        XCTAssertEqual(secret1.count, 32) // Should be 32 bytes
    }

    func testComputeSharedSecret_invalidPrivateKeyLength() {
        // Too short
        XCTAssertThrowsError(try NIP04.computeSharedSecret(privateKey: "abc123", pubkey: testPublicKey2)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }

        // Too long
        let longKey = testPrivateKey1 + "00"
        XCTAssertThrowsError(try NIP04.computeSharedSecret(privateKey: longKey, pubkey: testPublicKey2)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }
    }

    func testComputeSharedSecret_invalidPublicKeyLength() {
        // Too short
        XCTAssertThrowsError(try NIP04.computeSharedSecret(privateKey: testPrivateKey1, pubkey: "abc123")) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }
    }

    func testComputeSharedSecret_invalidHexFormat() {
        // Invalid hex characters
        XCTAssertThrowsError(try NIP04.computeSharedSecret(privateKey: "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg", pubkey: testPublicKey2)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }
    }

    // MARK: - Encryption/Decryption Tests

    func testEncryptDecrypt_simpleMessage() throws {
        let message = "Hello, NIP-04!"

        // Encrypt with key1 for key2
        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)

        // Verify format: base64(ciphertext)?iv=base64(iv)
        XCTAssertTrue(encrypted.contains("?iv="))
        let parts = encrypted.split(separator: "?")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[1].hasPrefix("iv="))

        // Decrypt with key2
        let decrypted = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted, message)
    }

    func testEncryptDecrypt_unicodeMessage() throws {
        let message = "Hello 👋 World 🌍! Testing émojis and spéciål characters €£¥"

        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted, message)
    }

    func testEncryptDecrypt_emptyMessage() throws {
        let message = ""

        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted, message)
    }

    func testEncryptDecrypt_longMessage() throws {
        let message = String(repeating: "This is a long message. ", count: 100)

        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted, message)
    }

    func testEncrypt_producesUniqueOutputs() throws {
        let message = "Test message"

        // Encrypt the same message twice
        let encrypted1 = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let encrypted2 = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)

        // Should produce different outputs due to random IV
        XCTAssertNotEqual(encrypted1, encrypted2)

        // But both should decrypt to the same message
        let decrypted1 = try NIP04.decrypt(encrypted: encrypted1, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        let decrypted2 = try NIP04.decrypt(encrypted: encrypted2, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted1, message)
        XCTAssertEqual(decrypted2, message)
    }

    // MARK: - Decryption Error Tests

    func testDecrypt_invalidFormat() {
        // Missing IV parameter
        XCTAssertThrowsError(try NIP04.decrypt(encrypted: "somebase64data", privateKey: testPrivateKey2, pubkey: testPublicKey1)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidPoint)
        }

        // Invalid base64
        XCTAssertThrowsError(try NIP04.decrypt(encrypted: "not-base64!@#$?iv=dGVzdA==", privateKey: testPrivateKey2, pubkey: testPublicKey1))

        // Missing iv= prefix
        XCTAssertThrowsError(try NIP04.decrypt(encrypted: "dGVzdA==?dGVzdA==", privateKey: testPrivateKey2, pubkey: testPublicKey1)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError")
                return
            }
            XCTAssertEqual(cryptoError, .invalidPoint)
        }
    }

    func testDecrypt_wrongPrivateKey() throws {
        let message = "Secret message"

        // Encrypt with key1 for key2
        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)

        // Try to decrypt with wrong key (key1 instead of key2)
        XCTAssertThrowsError(try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey1, pubkey: testPublicKey1))
    }

    func testDecrypt_tamperedCiphertext() throws {
        let message = "Original message"

        // Encrypt normally
        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)

        // Tamper with the ciphertext
        let parts = encrypted.split(separator: "?")
        guard parts.count == 2,
              var ciphertextData = Data(base64Encoded: String(parts[0]))
        else {
            XCTFail("Failed to parse encrypted data")
            return
        }

        // Flip a bit in the ciphertext
        ciphertextData[0] ^= 0x01
        let tamperedEncrypted = "\(ciphertextData.base64EncodedString())?\(parts[1])"

        // Decryption should fail or produce garbage
        do {
            let decrypted = try NIP04.decrypt(encrypted: tamperedEncrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
            // If it doesn't throw, the decrypted text should be different
            XCTAssertNotEqual(decrypted, message)
        } catch {
            // Expected - tampered data should fail
        }
    }

    // MARK: - Padding Tests

    func testPKCS7Padding_correctlyPads() throws {
        // The internal padding is tested indirectly through encryption/decryption
        // Messages of various lengths should all work correctly
        let testMessages = [
            "1", // 1 byte - needs 15 bytes padding
            "12345678901234567", // 17 bytes - needs 15 bytes padding
            "1234567890123456", // 16 bytes - needs 16 bytes padding (full block)
            "123456789012345", // 15 bytes - needs 1 byte padding
            String(repeating: "a", count: 32), // 32 bytes - needs 16 bytes padding
            String(repeating: "b", count: 31), // 31 bytes - needs 1 byte padding
        ]

        for message in testMessages {
            let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
            let decrypted = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
            XCTAssertEqual(decrypted, message, "Failed for message of length \(message.count)")
        }
    }

    // MARK: - Crypto Extension Tests

    func testCryptoExtensions() throws {
        let message = "Testing Crypto extensions"

        // Test convenience methods
        let encrypted = try Crypto.nip04Encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)

        XCTAssertEqual(decrypted, message)

        // Test shared secret computation
        let secret = try Crypto.computeSharedSecret(privateKey: testPrivateKey1, pubkey: testPublicKey2)
        XCTAssertEqual(secret.count, 32)
    }

    // MARK: - Performance Tests

    func testEncryptionPerformance() throws {
        let message = String(repeating: "Performance test message. ", count: 10)

        measure {
            do {
                for _ in 0 ..< 100 {
                    _ = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
                }
            } catch {
                XCTFail("Encryption failed: \(error)")
            }
        }
    }

    func testDecryptionPerformance() throws {
        let message = String(repeating: "Performance test message. ", count: 10)
        let encrypted = try NIP04.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)

        measure {
            do {
                for _ in 0 ..< 100 {
                    _ = try NIP04.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
                }
            } catch {
                XCTFail("Decryption failed: \(error)")
            }
        }
    }
}
