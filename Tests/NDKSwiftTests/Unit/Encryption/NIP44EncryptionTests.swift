import XCTest
@testable import NDKSwift

final class NIP44EncryptionTests: XCTestCase {
    
    // Test vectors
    let testPrivateKey1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let testPublicKey1 = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    
    let testPrivateKey2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let testPublicKey2 = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
    
    // MARK: - Padding Length Tests
    
    func testCalcPaddedLen_smallMessages() {
        // Messages <= 32 bytes should pad to 32
        XCTAssertEqual(NIP44.calcPaddedLen(1), 32)
        XCTAssertEqual(NIP44.calcPaddedLen(16), 32)
        XCTAssertEqual(NIP44.calcPaddedLen(32), 32)
        
        // Just over 32
        XCTAssertEqual(NIP44.calcPaddedLen(33), 64)
    }
    
    func testCalcPaddedLen_mediumMessages() {
        // Test power of 2 boundaries
        XCTAssertEqual(NIP44.calcPaddedLen(64), 64)
        XCTAssertEqual(NIP44.calcPaddedLen(65), 96)
        XCTAssertEqual(NIP44.calcPaddedLen(96), 96)
        XCTAssertEqual(NIP44.calcPaddedLen(97), 128)
        XCTAssertEqual(NIP44.calcPaddedLen(128), 128)
        XCTAssertEqual(NIP44.calcPaddedLen(129), 160)
    }
    
    func testCalcPaddedLen_largeMessages() {
        // After 256 bytes, chunk size changes
        XCTAssertEqual(NIP44.calcPaddedLen(256), 256)
        XCTAssertEqual(NIP44.calcPaddedLen(257), 320)
        XCTAssertEqual(NIP44.calcPaddedLen(320), 320)
        XCTAssertEqual(NIP44.calcPaddedLen(321), 384)
        
        // Larger sizes
        XCTAssertEqual(NIP44.calcPaddedLen(512), 512)
        XCTAssertEqual(NIP44.calcPaddedLen(513), 640)
        XCTAssertEqual(NIP44.calcPaddedLen(1024), 1024)
        XCTAssertEqual(NIP44.calcPaddedLen(1025), 1152)
    }
    
    func testCalcPaddedLen_veryLargeMessages() {
        // Test near max size
        XCTAssertEqual(NIP44.calcPaddedLen(65535), 65536)
        XCTAssertEqual(NIP44.calcPaddedLen(65536), 65536)
    }
    
    // MARK: - Shared Secret Tests
    
    func testComputeSharedSecret_validKeys() throws {
        // Compute conversation key from both sides
        let key1 = try NIP44.getConversationKey(privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let key2 = try NIP44.getConversationKey(privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        // Both should produce the same conversation key
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key1.count, 32) // Should be 32 bytes
    }
    
    func testComputeSharedSecret_deterministicOutput() throws {
        // Same keys should always produce same conversation key
        let key1 = try NIP44.getConversationKey(privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let key2 = try NIP44.getConversationKey(privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        XCTAssertEqual(key1, key2)
    }
    
    func testComputeSharedSecret_invalidKeys() {
        // Test with invalid private key
        XCTAssertThrowsError(try NIP44.getConversationKey(privateKey: "invalid", pubkey: testPublicKey2))
        
        // Test with invalid public key
        XCTAssertThrowsError(try NIP44.getConversationKey(privateKey: testPrivateKey1, pubkey: "invalid"))
    }
    
    // MARK: - Encryption/Decryption Tests
    
    func testEncryptDecrypt_simpleMessage() throws {
        let message = "Hello, NIP-44!"
        
        // Encrypt with key1 for key2
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Should be base64 encoded
        XCTAssertNotNil(Data(base64Encoded: encrypted))
        
        // Decrypt with key2
        let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    func testEncryptDecrypt_unicodeMessage() throws {
        let message = "Hello 👋 World 🌍! Testing émojis and spéciål characters €£¥ 你好世界"
        
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    func testEncryptDecrypt_emptyMessage() throws {
        // Empty message should fail with NIP-44 (min size is 1)
        XCTAssertThrowsError(try NIP44.encrypt(message: "", privateKey: testPrivateKey1, pubkey: testPublicKey2)) { error in
            guard let nip44Error = error as? NIP44.NIP44Error else {
                XCTFail("Expected NIP44Error")
                return
            }
            XCTAssertEqual(nip44Error, .invalidPayloadSize)
        }
    }
    
    func testEncryptDecrypt_singleCharMessage() throws {
        let message = "x"
        
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    func testEncryptDecrypt_longMessage() throws {
        let message = String(repeating: "This is a long message. ", count: 100)
        
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    func testEncryptDecrypt_maxSizeMessage() throws {
        // Test with maximum allowed size (65535 bytes)
        let message = String(repeating: "a", count: 65535)
        
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    func testEncrypt_messageTooLarge() {
        // Test with message larger than max size
        let message = String(repeating: "a", count: 65536)
        
        XCTAssertThrowsError(try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)) { error in
            guard let nip44Error = error as? NIP44.NIP44Error else {
                XCTFail("Expected NIP44Error")
                return
            }
            XCTAssertEqual(nip44Error, .invalidPayloadSize)
        }
    }
    
    func testEncrypt_producesUniqueOutputs() throws {
        let message = "Test message"
        
        // Encrypt the same message multiple times
        let encrypted1 = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let encrypted2 = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let encrypted3 = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Should produce different outputs due to random nonce
        XCTAssertNotEqual(encrypted1, encrypted2)
        XCTAssertNotEqual(encrypted2, encrypted3)
        XCTAssertNotEqual(encrypted1, encrypted3)
        
        // But all should decrypt to the same message
        let decrypted1 = try NIP44.decrypt(encrypted: encrypted1, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        let decrypted2 = try NIP44.decrypt(encrypted: encrypted2, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        let decrypted3 = try NIP44.decrypt(encrypted: encrypted3, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted1, message)
        XCTAssertEqual(decrypted2, message)
        XCTAssertEqual(decrypted3, message)
    }
    
    // MARK: - Decryption Error Tests
    
    func testDecrypt_invalidBase64() {
        XCTAssertThrowsError(try NIP44.decrypt(encrypted: "not-base64!@#$", privateKey: testPrivateKey2, pubkey: testPublicKey1))
    }
    
    func testDecrypt_wrongPrivateKey() throws {
        let message = "Secret message"
        
        // Encrypt with key1 for key2
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Try to decrypt with wrong key combination
        XCTAssertThrowsError(try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey1, pubkey: testPublicKey1))
    }
    
    func testDecrypt_tamperedCiphertext() throws {
        let message = "Original message"
        
        // Encrypt normally
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Decode and tamper with the data
        guard var data = Data(base64Encoded: encrypted) else {
            XCTFail("Failed to decode base64")
            return
        }
        
        // Flip a bit in the MAC (last 32 bytes)
        let macOffset = data.count - 32
        data[macOffset] ^= 0x01
        
        let tamperedEncrypted = data.base64EncodedString()
        
        // Decryption should fail with invalid MAC
        XCTAssertThrowsError(try NIP44.decrypt(encrypted: tamperedEncrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)) { error in
            guard let nip44Error = error as? NIP44.NIP44Error else {
                XCTFail("Expected NIP44Error, got \(error)")
                return
            }
            XCTAssertEqual(nip44Error, .invalidMAC)
        }
    }
    
    func testDecrypt_wrongVersion() throws {
        let message = "Test message"
        
        // Encrypt normally
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Decode and change version byte
        guard var data = Data(base64Encoded: encrypted) else {
            XCTFail("Failed to decode base64")
            return
        }
        
        // Change version from 0x02 to 0x03
        data[0] = 0x03
        
        let tamperedEncrypted = data.base64EncodedString()
        
        // Decryption should fail with unsupported version
        XCTAssertThrowsError(try NIP44.decrypt(encrypted: tamperedEncrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)) { error in
            guard let nip44Error = error as? NIP44.NIP44Error else {
                XCTFail("Expected NIP44Error")
                return
            }
            XCTAssertEqual(nip44Error, .unsupportedVersion)
        }
    }
    
    func testDecrypt_truncatedData() throws {
        let message = "Test message"
        
        // Encrypt normally
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        // Decode and truncate
        guard let data = Data(base64Encoded: encrypted) else {
            XCTFail("Failed to decode base64")
            return
        }
        
        // Truncate to make it too small
        let truncatedData = data.prefix(50) // Less than minimum required
        let truncatedEncrypted = truncatedData.base64EncodedString()
        
        // Should fail with invalid data size
        XCTAssertThrowsError(try NIP44.decrypt(encrypted: truncatedEncrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)) { error in
            guard let nip44Error = error as? NIP44.NIP44Error else {
                XCTFail("Expected NIP44Error, got \(error)")
                return
            }
            XCTAssertEqual(nip44Error, .invalidDataSize)
        }
    }
    
    // MARK: - Padding Validation Tests
    
    func testPadding_variousMessageSizes() throws {
        // Test that messages of various sizes encrypt/decrypt correctly
        // This indirectly tests the padding implementation
        let testSizes = [1, 15, 16, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 1000, 5000]
        
        for size in testSizes {
            let message = String(repeating: "x", count: size)
            
            let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
            let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
            
            XCTAssertEqual(decrypted, message, "Failed for message size \(size)")
        }
    }
    
    // MARK: - Crypto Extension Tests
    
    func testCryptoExtensions() throws {
        let message = "Testing Crypto extensions for NIP-44"
        
        // Test convenience methods
        let encrypted = try Crypto.nip44Encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        let decrypted = try Crypto.nip44Decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
        
        XCTAssertEqual(decrypted, message)
    }
    
    // MARK: - Key Validation Tests
    
    func testEncrypt_invalidPrivateKeyLength() {
        let message = "Test"
        
        // Too short
        XCTAssertThrowsError(try NIP44.encrypt(message: message, privateKey: "abc123", pubkey: testPublicKey2)) { error in
            guard let hexError = error as? HexValidator.HexValidationError else {
                XCTFail("Expected HexValidationError, got \(error)")
                return
            }
            if case .invalidLength = hexError {
                // Expected error
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
        
        // Too long
        let longKey = testPrivateKey1 + "00"
        XCTAssertThrowsError(try NIP44.encrypt(message: message, privateKey: longKey, pubkey: testPublicKey2)) { error in
            guard let hexError = error as? HexValidator.HexValidationError else {
                XCTFail("Expected HexValidationError, got \(error)")
                return
            }
            if case .invalidLength = hexError {
                // Expected error
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }
    
    func testEncrypt_invalidPublicKeyLength() {
        let message = "Test"
        
        // Too short
        XCTAssertThrowsError(try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: "abc123")) { error in
            guard let hexError = error as? HexValidator.HexValidationError else {
                XCTFail("Expected HexValidationError, got \(error)")
                return
            }
            if case .invalidLength = hexError {
                // Expected error
            } else {
                XCTFail("Expected invalidLength error")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testEncryptionPerformance() throws {
        let message = String(repeating: "Performance test message. ", count: 10)
        
        measure {
            do {
                for _ in 0..<100 {
                    _ = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
                }
            } catch {
                XCTFail("Encryption failed: \(error)")
            }
        }
    }
    
    func testDecryptionPerformance() throws {
        let message = String(repeating: "Performance test message. ", count: 10)
        let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
        
        measure {
            do {
                for _ in 0..<100 {
                    _ = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
                }
            } catch {
                XCTFail("Decryption failed: \(error)")
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testMessageBoundaries() throws {
        // Test messages at padding boundaries
        let boundaries = [
            31,  // Just under 32
            32,  // Exactly 32
            63,  // Just under 64
            64,  // Exactly 64
            95,  // Just under 96
            96,  // Exactly 96
            255, // Just under 256
            256, // Exactly 256 (chunk size changes here)
            319, // Just under 320
            320, // Exactly 320
        ]
        
        for size in boundaries {
            let message = String(repeating: "a", count: size)
            
            let encrypted = try NIP44.encrypt(message: message, privateKey: testPrivateKey1, pubkey: testPublicKey2)
            let decrypted = try NIP44.decrypt(encrypted: encrypted, privateKey: testPrivateKey2, pubkey: testPublicKey1)
            
            XCTAssertEqual(decrypted, message, "Failed at boundary size \(size)")
        }
    }
}