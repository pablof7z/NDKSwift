import XCTest
@testable import NDKSwift

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
        let sets = (0..<10).map { _ in Crypto.randomBytes(count: 32) }
        
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
            ("The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
        ]
        
        for (input, expected) in testVectors {
            let data = input.data(using: .utf8)!
            let hashData = Crypto.sha256(data)
            let hashHex = hashData.hexEncodedString()
            XCTAssertEqual(hashHex, expected, "SHA256 hash mismatch for input: '\(input)'")
        }
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
        let keys = (0..<10).map { _ in Crypto.generatePrivateKey() }
        let uniqueKeys = Set(keys)
        
        XCTAssertEqual(uniqueKeys.count, keys.count, "Generated keys should be unique")
    }
    
    // MARK: - Public key derivation tests
    
    func testDerivePublicKey_knownVectors() throws {
        // Test vectors from secp256k1 libraries
        let testVectors: [(privateKey: String, expectedPublicKey: String)] = [
            (
                "0000000000000000000000000000000000000000000000000000000000000001",
                "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
            ),
            (
                "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140",
                "03cee31223f5845915297f1afdc60cbf60a6019ac36f487dcbc8e1a5f790f6d1db"
            )
        ]
        
        for (privateKey, expectedPublicKey) in testVectors {
            let publicKey = try Crypto.getPublicKey(from: privateKey)
            XCTAssertEqual(publicKey, expectedPublicKey)
        }
    }
    
    func testDerivePublicKey_invalidPrivateKey() {
        // Test invalid hex
        XCTAssertThrowsError(try Crypto.getPublicKey(from: "not-hex")) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
        }
        
        // Test wrong length
        XCTAssertThrowsError(try Crypto.getPublicKey(from: "deadbeef")) { error in
            XCTAssertTrue(error is Crypto.CryptoError)
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
        corruptedSig.replaceSubrange(startIndex..<endIndex, with: "ff")
        
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
    
    // MARK: - Error handling tests
    
    func testCryptoError_descriptions() {
        let errors: [Crypto.CryptoError] = [
            .invalidKeyLength,
            .invalidSignatureLength,
            .signingFailed,
            .verificationFailed,
            .invalidPoint,
            .invalidScalar
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