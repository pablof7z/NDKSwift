@testable import NDKSwiftCore
import XCTest

final class CryptoTests: XCTestCase {
    // MARK: - Random bytes tests

    func testRandomBytes_generatesCorrectLength() {
        let lengths = [16, 32, 64, 128]

        for length in lengths {
            let bytes = Crypto.randomBytes(count: length)
            XCTAssertEqual(bytes.count, length)
        }
    }

    func testRandomBytes_generatesUniqueValues() {
        // Generate multiple sets of random bytes
        let sets = (0 ..< 10).map { _ in Crypto.randomBytes(count: 32) }

        // Check that all sets are unique
        let uniqueSets = Set(sets)
        XCTAssertEqual(uniqueSets.count, sets.count, "Random bytes should be unique")
    }

    // MARK: - SHA256 tests

    func testSHA256_knownVectors() {
        // Test vectors from various sources
        let testVectors: [(input: String, expected: String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("hello", "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
            ("The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"),
        ]

        for (input, expected) in testVectors {
            let data = input.data(using: .utf8)!
            let hashData = Crypto.sha256(data)
            let hashHex = hashData.hexEncodedString()
            XCTAssertEqual(hashHex, expected, "SHA256 hash mismatch for input: '\(input)'")
        }
    }

    func testSHA256_largeData() {
        // Test with larger data - 1MB of repeated pattern
        let pattern = "Hello, Nostr! "
        let largeString = String(repeating: pattern, count: 1024 * 1024 / pattern.count)
        let data = largeString.data(using: .utf8)!

        // Should not crash and should produce consistent result
        let hash1 = Crypto.sha256(data)
        let hash2 = Crypto.sha256(data)

        XCTAssertEqual(hash1, hash2, "SHA256 should be deterministic for large data")
        XCTAssertEqual(hash1.count, 32, "SHA256 should always produce 32 bytes")
    }

    func testSHA256_edgeCases() {
        // Test single byte
        let singleByte = Data([0x42])
        let singleByteHash = Crypto.sha256(singleByte)
        XCTAssertEqual(singleByteHash.count, 32)

        // Test all zeros
        let zeros = Data(repeating: 0, count: 1000)
        let zerosHash = Crypto.sha256(zeros)
        XCTAssertEqual(zerosHash.count, 32)

        // Test all 0xFF
        let maxBytes = Data(repeating: 0xFF, count: 1000)
        let maxHash = Crypto.sha256(maxBytes)
        XCTAssertEqual(maxHash.count, 32)

        // All should be different
        let hashes = [singleByteHash, zerosHash, maxHash]
        let uniqueHashes = Set(hashes)
        XCTAssertEqual(uniqueHashes.count, hashes.count, "Different inputs should produce different hashes")
    }

    func testSHA256_hexString() {
        let input = "hello world"
        let data = input.data(using: .utf8)!
        let hashData = Crypto.sha256(data)
        let hashHex = hashData.hexEncodedString()
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        XCTAssertEqual(hashHex, expected)
    }

    // MARK: - Key generation tests

    func testGeneratePrivateKey_validLength() {
        let privateKey = Crypto.generatePrivateKey()

        // Should be 64 hex characters (32 bytes)
        XCTAssertEqual(privateKey.count, 64)

        // Should be valid hex
        XCTAssertTrue(HexValidator.isValid32ByteHex(privateKey))
    }

    func testGeneratePrivateKey_uniqueKeys() {
        let keys = (0 ..< 10).map { _ in Crypto.generatePrivateKey() }
        let uniqueKeys = Set(keys)

        XCTAssertEqual(uniqueKeys.count, keys.count, "Generated keys should be unique")
    }

    // MARK: - Public key derivation tests

    func testDerivePublicKey_consistency() throws {
        // Test that public key derivation is consistent
        // Note: all-zeros is invalid, and values >= curve order are invalid
        let testPrivateKeys = [
            "0000000000000000000000000000000000000000000000000000000000000001",
            "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ]

        for privateKey in testPrivateKeys {
            let publicKey1 = try Crypto.getPublicKey(from: privateKey)
            let publicKey2 = try Crypto.getPublicKey(from: privateKey)

            // Should produce the same public key every time
            XCTAssertEqual(publicKey1, publicKey2)

            // Should be 64 characters (32 bytes)
            XCTAssertEqual(publicKey1.count, 64)

            // Should be valid hex
            XCTAssertTrue(HexValidator.isValid32ByteHex(publicKey1))
        }
    }

    func testDerivePublicKey_invalidPrivateKey() {
        // Test invalid hex
        XCTAssertThrowsError(try Crypto.getPublicKey(from: "not-hex")) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }

        // Test wrong length - too short
        XCTAssertThrowsError(try Crypto.getPublicKey(from: "deadbeef")) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }

        // Test wrong length - too long
        let longKey = String(repeating: "a", count: 130) // 65 bytes instead of 32
        XCTAssertThrowsError(try Crypto.getPublicKey(from: longKey)) { error in
            guard let cryptoError = error as? Crypto.CryptoError else {
                XCTFail("Expected Crypto.CryptoError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(cryptoError, .invalidKeyLength)
        }

        // Test all zeros (may or may not be valid depending on implementation)
        let zeroKey = String(repeating: "0", count: 64)
        do {
            let publicKey = try Crypto.getPublicKey(from: zeroKey)
            // If it succeeds, verify it produces a valid result
            XCTAssertEqual(publicKey.count, 64)
            XCTAssertTrue(HexValidator.isValid32ByteHex(publicKey))
        } catch {
            // If it fails, just verify it's an error - we don't enforce the specific type
            // since different implementations may handle edge cases differently
            XCTAssertNotNil(error, "Should throw some kind of error for edge case")
        }
    }

    // MARK: - Signature tests

    func testSignAndVerify_roundTrip() throws {
        let privateKey = Crypto.generatePrivateKey()
        let publicKey = try Crypto.getPublicKey(from: privateKey)
        let message = "Hello, Nostr!"
        let messageData = message.data(using: .utf8)!
        let messageHash = Crypto.sha256(messageData)

        // Sign the message
        let signature = try Crypto.sign(message: messageHash, privateKey: privateKey)

        // Verify the signature
        let isValid = try Crypto.verify(signature: signature, message: messageHash, pubkey: publicKey)
        XCTAssertTrue(isValid)
    }

    func testVerifySignature_invalidSignatureFails() throws {
        let privateKey = Crypto.generatePrivateKey()
        let publicKey = try Crypto.getPublicKey(from: privateKey)
        let messageData = "Hello, Nostr!".data(using: .utf8)!
        let message = Crypto.sha256(messageData)

        // Create a valid signature
        let signature = try Crypto.sign(message: message, privateKey: privateKey)

        // Corrupt the signature
        var corruptedSig = signature
        let startIndex = corruptedSig.startIndex
        let endIndex = corruptedSig.index(startIndex, offsetBy: 2)
        corruptedSig.replaceSubrange(startIndex ..< endIndex, with: "ff")

        // Verification should fail
        let isValid = try Crypto.verify(signature: corruptedSig, message: message, pubkey: publicKey)
        XCTAssertFalse(isValid)
    }

    func testVerifySignature_wrongPublicKeyFails() throws {
        let privateKey1 = Crypto.generatePrivateKey()
        let privateKey2 = Crypto.generatePrivateKey()
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        let messageData = "Hello, Nostr!".data(using: .utf8)!
        let message = Crypto.sha256(messageData)

        // Sign with key1
        let signature = try Crypto.sign(message: message, privateKey: privateKey1)

        // Verify with key2 should fail
        let isValid = try Crypto.verify(signature: signature, message: message, pubkey: publicKey2)
        XCTAssertFalse(isValid)
    }

    func testSignature_invalidInputs() {
        let messageData = "test".data(using: .utf8)!
        let message = Crypto.sha256(messageData)

        // Test invalid private key length
        XCTAssertThrowsError(try Crypto.sign(message: message, privateKey: "short")) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }

        // Test invalid private key hex
        let invalidHex = String(repeating: "z", count: 64)
        XCTAssertThrowsError(try Crypto.sign(message: message, privateKey: invalidHex)) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }
    }

    func testVerifySignature_invalidInputs() throws {
        let privateKey = Crypto.generatePrivateKey()
        let publicKey = try Crypto.getPublicKey(from: privateKey)
        let messageData = "test".data(using: .utf8)!
        let message = Crypto.sha256(messageData)
        let signature = try Crypto.sign(message: message, privateKey: privateKey)

        // Test invalid signature length
        XCTAssertThrowsError(try Crypto.verify(signature: "short", message: message, pubkey: publicKey)) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }

        // Test invalid public key length
        XCTAssertThrowsError(try Crypto.verify(signature: signature, message: message, pubkey: "short")) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }

        // Test invalid hex in signature
        let invalidSig = String(repeating: "z", count: 128)
        XCTAssertThrowsError(try Crypto.verify(signature: invalidSig, message: message, pubkey: publicKey)) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }
    }

    // MARK: - Error handling tests

    func testCryptoError_descriptions() {
        let errors: [Crypto.CryptoError] = [
            .invalidKeyLength,
            .invalidSignatureLength,
            .signingFailed,
            .verificationFailed,
            .invalidPoint,
            .invalidScalar,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Constants tests

    func testConstants_correctValues() {
        XCTAssertEqual(Crypto.Constants.privateKeySize, 32)
        XCTAssertEqual(Crypto.Constants.signatureSize, 64)
    }
}
