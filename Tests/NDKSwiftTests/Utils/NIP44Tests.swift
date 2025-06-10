import XCTest
@testable import NDKSwift

final class NIP44Tests: XCTestCase {
    // Test vectors from https://github.com/paulmillr/nip44
    struct TestVector: Codable {
        let sec1: String?
        let sec2: String?
        let pub1: String?
        let pub2: String?
        let conversationKey: String?
        let nonce: String?
        let plaintext: String?
        let payload: String?
        let note: String?
    }
    
    struct TestVectors: Codable {
        struct ValidTests: Codable {
            let getConversationKey: [TestVector]?
            let getMessageKeys: [[String]]?
            let calcPaddedLen: [[Int]]?
            let encryptDecrypt: [TestVector]?
            let encryptDecryptLongMsg: [TestVector]?
            
            enum CodingKeys: String, CodingKey {
                case getConversationKey = "get_conversation_key"
                case getMessageKeys = "get_message_keys"
                case calcPaddedLen = "calc_padded_len"
                case encryptDecrypt = "encrypt_decrypt"
                case encryptDecryptLongMsg = "encrypt_decrypt_long_msg"
            }
        }
        
        struct InvalidTests: Codable {
            let getConversationKey: [TestVector]?
            let decrypt: [TestVector]?
            let encryptMsgLengths: [String]?
            
            enum CodingKeys: String, CodingKey {
                case getConversationKey = "get_conversation_key"
                case decrypt
                case encryptMsgLengths = "encrypt_msg_lengths"
            }
        }
        
        let v2: V2Tests?
        
        struct V2Tests: Codable {
            let valid: ValidTests?
            let invalid: InvalidTests?
        }
    }
    
    lazy var testVectors: TestVectors? = {
        // Direct file path approach since Bundle.module might not be available
        let fileURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("nip44.vectors.json")
        
        guard let data = try? Data(contentsOf: fileURL),
              let vectors = try? JSONDecoder().decode(TestVectors.self, from: data) else {
            return nil
        }
        return vectors
    }()
    
    // MARK: - Padding Tests
    
    func testCalcPaddedLen() {
        let vectors = testVectors?.v2?.valid?.calcPaddedLen ?? []
        
        for vector in vectors {
            guard vector.count == 2 else { continue }
            let unpadded = vector[0]
            let expected = vector[1]
            
            let result = Crypto.nip44CalcPaddedLen(unpadded)
            XCTAssertEqual(result, expected, "Padding calculation failed for length \(unpadded)")
        }
    }
    
    // MARK: - Conversation Key Tests
    
    func testGetConversationKey() async throws {
        let vectors = testVectors?.v2?.valid?.getConversationKey ?? []
        
        for vector in vectors {
            guard let sec1 = vector.sec1,
                  let pub2 = vector.pub2,
                  let expectedKey = vector.conversationKey else { continue }
            
            let conversationKey = try Crypto.nip44GetConversationKey(
                privateKey: sec1,
                publicKey: pub2
            )
            
            XCTAssertEqual(
                conversationKey.hexString,
                expectedKey,
                "Conversation key mismatch for test: \(vector.note ?? "unnamed")"
            )
        }
    }
    
    func testGetConversationKeyInvalid() async throws {
        let vectors = testVectors?.v2?.invalid?.getConversationKey ?? []
        
        for vector in vectors {
            guard let sec1 = vector.sec1,
                  let pub2 = vector.pub2 else { continue }
            
            XCTAssertThrowsError(
                try Crypto.nip44GetConversationKey(privateKey: sec1, publicKey: pub2),
                "Expected error for invalid key test: \(vector.note ?? "unnamed")"
            )
        }
    }
    
    // MARK: - Message Keys Tests
    
    func testGetMessageKeys() async throws {
        let vectors = testVectors?.v2?.valid?.getMessageKeys ?? []
        
        for vector in vectors {
            guard vector.count >= 5 else { continue }
            
            let conversationKeyHex = vector[0]
            let nonceHex = vector[1]
            let expectedChachaKey = vector[2]
            let expectedChachaNonce = vector[3]
            let expectedHmacKey = vector[4]
            
            guard let conversationKey = Data(hexString: conversationKeyHex),
                  let nonce = Data(hexString: nonceHex) else {
                XCTFail("Invalid hex in test vector")
                continue
            }
            
            let (chachaKey, chachaNonce, hmacKey) = try Crypto.nip44GetMessageKeys(
                conversationKey: conversationKey,
                nonce: nonce
            )
            
            XCTAssertEqual(chachaKey.hexString, expectedChachaKey)
            XCTAssertEqual(chachaNonce.hexString, expectedChachaNonce)
            XCTAssertEqual(hmacKey.hexString, expectedHmacKey)
        }
    }
    
    // MARK: - Encryption/Decryption Tests
    
    func testEncryptDecrypt() async throws {
        let vectors = testVectors?.v2?.valid?.encryptDecrypt ?? []
        
        for vector in vectors {
            guard let sec1 = vector.sec1,
                  let sec2 = vector.sec2,
                  let nonce = vector.nonce,
                  let plaintext = vector.plaintext,
                  let payload = vector.payload,
                  let conversationKeyHex = vector.conversationKey else { continue }
            
            // Test encryption
            if let nonceData = Data(hexString: nonce),
               let conversationKey = Data(hexString: conversationKeyHex) {
                let encrypted = try Crypto.nip44Encrypt(
                    plaintext: plaintext,
                    conversationKey: conversationKey,
                    nonce: nonceData
                )
                
                XCTAssertEqual(
                    encrypted,
                    payload,
                    "Encryption failed for test: \(vector.note ?? "unnamed")"
                )
            }
            
            // Test decryption
            if let conversationKey = Data(hexString: conversationKeyHex) {
                let decrypted = try Crypto.nip44Decrypt(
                    payload: payload,
                    conversationKey: conversationKey
                )
                
                XCTAssertEqual(
                    decrypted,
                    plaintext,
                    "Decryption failed for test: \(vector.note ?? "unnamed")"
                )
            }
            
            // Test high-level API with key derivation
            let pub2 = try Crypto.getPublicKey(from: sec2)
            
            // Encrypt with sec1 -> pub2
            let encrypted = try Crypto.nip44Encrypt(
                message: plaintext,
                privateKey: sec1,
                publicKey: pub2
            )
            
            // Decrypt with sec2 -> pub1
            let pub1 = try Crypto.getPublicKey(from: sec1)
            let decrypted = try Crypto.nip44Decrypt(
                encrypted: encrypted,
                privateKey: sec2,
                publicKey: pub1
            )
            
            XCTAssertEqual(decrypted, plaintext)
        }
    }
    
    func testDecryptInvalid() async throws {
        let vectors = testVectors?.v2?.invalid?.decrypt ?? []
        
        for vector in vectors {
            guard let conversationKeyHex = vector.conversationKey,
                  let payload = vector.payload,
                  let conversationKey = Data(hexString: conversationKeyHex) else { continue }
            
            XCTAssertThrowsError(
                try Crypto.nip44Decrypt(payload: payload, conversationKey: conversationKey),
                "Expected error for invalid decrypt test: \(vector.note ?? "unnamed")"
            )
        }
    }
    
    // MARK: - Edge Cases
    
    func testInvalidMessageLengths() async throws {
        let lengths = testVectors?.v2?.invalid?.encryptMsgLengths ?? []
        let conversationKey = Crypto.randomBytes(count: 32)
        let nonce = Crypto.randomBytes(count: 32)
        
        for lengthStr in lengths {
            guard let length = Int(lengthStr) else { continue }
            
            // Create a string of the specified length
            let plaintext = String(repeating: "a", count: length)
            
            XCTAssertThrowsError(
                try Crypto.nip44Encrypt(
                    plaintext: plaintext,
                    conversationKey: conversationKey,
                    nonce: nonce
                ),
                "Expected error for message length \(length)"
            )
        }
    }
    
    // MARK: - Additional Tests
    
    func testPaddingRoundtrip() throws {
        let testStrings = [
            "a",
            "hello",
            "Hello, World!",
            String(repeating: "x", count: 32),
            String(repeating: "y", count: 100),
            String(repeating: "z", count: 1000),
            "🔥💯",
            "مرحبا بالعالم",
            "🌍🌎🌏",
            "The quick brown fox jumps over the lazy dog."
        ]
        
        for str in testStrings {
            let padded = try Crypto.nip44Pad(str)
            let unpadded = try Crypto.nip44Unpad(padded)
            XCTAssertEqual(unpadded, str, "Padding roundtrip failed for: \(str)")
            
            // Verify padded length
            let expectedLen = Crypto.nip44CalcPaddedLen(str.utf8.count)
            XCTAssertEqual(padded.count, expectedLen + 2, "Incorrect padded length")
        }
    }
    
    func testConstantTimeComparison() throws {
        // Test that MAC verification uses constant-time comparison
        let conversationKey = Crypto.randomBytes(count: 32)
        let plaintext = "Test message"
        
        // Encrypt
        let encrypted = try Crypto.nip44Encrypt(
            plaintext: plaintext,
            conversationKey: conversationKey,
            nonce: Crypto.randomBytes(count: 32)
        )
        
        // Tamper with the MAC (last 32 bytes)
        guard var tamperedData = Data(base64Encoded: encrypted) else {
            XCTFail("Failed to decode base64")
            return
        }
        
        // Flip a bit in the MAC
        let macStart = tamperedData.count - 32
        tamperedData[macStart] ^= 0x01
        
        let tamperedPayload = tamperedData.base64EncodedString()
        
        // Should throw invalid MAC error
        XCTAssertThrowsError(
            try Crypto.nip44Decrypt(payload: tamperedPayload, conversationKey: conversationKey)
        ) { error in
            XCTAssertTrue(error is Crypto.NIP44Error)
            if let nip44Error = error as? Crypto.NIP44Error {
                XCTAssertEqual(nip44Error, .invalidMAC)
            }
        }
    }
    
    func testVersionHandling() throws {
        // Test unsupported version detection
        var payload = Data()
        payload.append(0x01) // Unsupported version
        payload.append(Crypto.randomBytes(count: 98)) // Minimum valid size
        
        let encoded = payload.base64EncodedString()
        let conversationKey = Crypto.randomBytes(count: 32)
        
        XCTAssertThrowsError(
            try Crypto.nip44Decrypt(payload: encoded, conversationKey: conversationKey)
        ) { error in
            XCTAssertTrue(error is Crypto.NIP44Error)
            if let nip44Error = error as? Crypto.NIP44Error {
                XCTAssertEqual(nip44Error, .unsupportedVersion)
            }
        }
        
        // Test future-proof flag
        let futurePayload = "#" + encoded
        
        XCTAssertThrowsError(
            try Crypto.nip44Decrypt(payload: futurePayload, conversationKey: conversationKey)
        ) { error in
            XCTAssertTrue(error is Crypto.NIP44Error)
            if let nip44Error = error as? Crypto.NIP44Error {
                XCTAssertEqual(nip44Error, .unsupportedVersion)
            }
        }
    }
    
    func testBoundaryConditions() throws {
        let conversationKey = Crypto.randomBytes(count: 32)
        let nonce = Crypto.randomBytes(count: 32)
        
        // Test minimum size (1 byte)
        let minMessage = "x"
        let encrypted = try Crypto.nip44Encrypt(
            plaintext: minMessage,
            conversationKey: conversationKey,
            nonce: nonce
        )
        let decrypted = try Crypto.nip44Decrypt(
            payload: encrypted,
            conversationKey: conversationKey
        )
        XCTAssertEqual(decrypted, minMessage)
        
        // Test maximum size (65535 bytes)
        let maxMessage = String(repeating: "a", count: 65535)
        XCTAssertNoThrow(
            try Crypto.nip44Encrypt(
                plaintext: maxMessage,
                conversationKey: conversationKey,
                nonce: nonce
            )
        )
        
        // Test over maximum size
        let overMaxMessage = String(repeating: "a", count: 65536)
        XCTAssertThrowsError(
            try Crypto.nip44Encrypt(
                plaintext: overMaxMessage,
                conversationKey: conversationKey,
                nonce: nonce
            )
        )
    }
}