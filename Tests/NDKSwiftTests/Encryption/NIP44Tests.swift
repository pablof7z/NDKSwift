import XCTest
import CryptoSwift
@testable import NDKSwift

final class NIP44Tests: XCTestCase {
    
    // MARK: - Test Vectors from nostr-tools
    
    // Test vector structure matching nostr-tools format
    struct ConversationKeyVector {
        let sec1: String
        let pub2: String
        let conversationKey: String
        let note: String?
    }
    
    struct EncryptionVector {
        let conversationKey: String
        let nonce: String
        let plaintext: String
        let payload: String
    }
    
    // Conversation key test vectors from nostr-tools official test vectors
    let conversationKeyVectors = [
        ConversationKeyVector(
            sec1: "315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268",
            pub2: "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133",
            conversationKey: "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1",
            note: nil
        ),
        ConversationKeyVector(
            sec1: "a1e37752c9fdc1273be53f68c5f74be7c8905728e8de75800b94262f9497c86e",
            pub2: "03bb7947065dde12ba991ea045132581d0954f042c84e06d8c00066e23c1a800",
            conversationKey: "4d14f36e81b8452128da64fe6f1eae873baae2f444b02c950b90e43553f2178b",
            note: nil
        ),
        ConversationKeyVector(
            sec1: "98a5902fd67518a0c900f0fb62158f278f94a21d6f9d33d30cd3091195500311",
            pub2: "aae65c15f98e5e677b5050de82e3aba47a6fe49b3dab7863cf35d9478ba9f7d1",
            conversationKey: "9c00b769d5f54d02bf175b7284a1cbd28b6911b06cda6666b2243561ac96bad7",
            note: nil
        ),
        ConversationKeyVector(
            sec1: "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139",
            pub2: "0000000000000000000000000000000000000000000000000000000000000002",
            conversationKey: "8b6392dbf2ec6a2b2d5b1477fc2be84d63ef254b667cadd31bd3f444c44ae6ba",
            note: "sec1 = n-2, pub2: random, 0x02"
        ),
        ConversationKeyVector(
            sec1: "0000000000000000000000000000000000000000000000000000000000000002",
            pub2: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdeb",
            conversationKey: "be234f46f60a250bef52a5ee34c758800c4ca8e5030bf4cc1a31d37ba2104d43",
            note: "sec1 = 2, pub2: rand"
        ),
        ConversationKeyVector(
            sec1: "0000000000000000000000000000000000000000000000000000000000000001",
            pub2: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
            conversationKey: "3b4610cb7189beb9cc29eb3716ecc6102f1247e8f3101a03a1787d8908aeb54e",
            note: "sec1 == pub2"
        )
    ]
    
    // Encryption test vectors from nostr-tools
    let encryptionVectors = [
        EncryptionVector(
            conversationKey: "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d",
            nonce: "0000000000000000000000000000000000000000000000000000000000000001",
            plaintext: "a",
            payload: "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"
        ),
        EncryptionVector(
            conversationKey: "352c7cf7934b6ccc8e3068b970b3c8bd9f1557a60e8187b0adc2b1e3a0b104f1",
            nonce: "74d60ccfe0793a6d80b0eb4290170275ac577e9e837bb10ec1601441a5d6eb09",
            plaintext: "🍕🫃",
            payload: "Ak10YMz+B5Om2AsOtCkBcCesV36eg3uxDsFgFBpdbrYJpqUGfQINSjlsGnAXvYKNjrk5K2qHvvWg5O6ZadJ6HRs39PfjNa4oMGWdmJ3vTpeTNw16mCMhE3V8SPXr6Q/d"
        ),
        EncryptionVector(
            conversationKey: "5254827d29177622d40a862c13e1d09f93664f34b80289fa80fd217991e882ef",
            nonce: "b826e191aded3bf865f2f5c6f21cf3b7808b3c06b4b1fb07c4a087ecff95b607",
            plaintext: "ability🤝的",
            payload: "AguCbhka3tO/hl8vXG8hzzuAizwGtLH7B8Sgh+z/lbYHQg/1pTjeIGZ3tKVHyhtIJm5swpOVecPq3GHPOpKPM3K8Fv1DN+N5ecAGxDYEJLFXVcMCdTNrI3wx8dLl7Xqp"
        ),
        EncryptionVector(
            conversationKey: "acac3fdc81f4f8a523a98ab5319d608630bbc2f73b0f0cb2f1eb88a91d07c615",
            nonce: "c7cbcdc967eb57e69cf188e1240167ec93a838c72c4bb29de08e09dc3354e56f",
            plaintext: "pepper👀їжак",
            payload: "AsfLzcln61fmnPGI4SQBZ+yTqDjHLEuyneCOCd3DVOVvBcO9kRa/gIhjMzdjGJBi8xvMJx6Zh1gP8OJN9vQa7xhuuJ1sgtFy3n8rVMqFxTNBCOQgZJBvhvzOe/XLCrQ6"
        ),
        EncryptionVector(
            conversationKey: "8f40e50a84a7462e2b8d24c28898ef1f23359fff50d8c509e6fb7ce06e142f9c",
            nonce: "b1a707519495e7fe7a473a2da0946a849c655ca412255fbc76ea9937a5e1abe9",
            plaintext: "( ͡° ͜ʖ ͡°)",
            payload: "ArGnB1GUlef+ekc6LaKUaoScZVykEiVfvHbqmTel4avpPHBe+IToZNb5B7tVA2Ax0zFCQZ8hsnpNUKV4UpMt+gNhkOMXJJKdmkos6g1H6NYiCQI1Y6ebPTQbJD8Hkd72"
        ),
        EncryptionVector(
            conversationKey: "fea39aca64dba911825c1f5b2ef6fb9c027cf3a96028ebe88e7585a4d44c9140",
            nonce: "7f4a2e45af75ec370c358b9677c70ae5c2e5baf5adadb69e0e402569e8bca884",
            plaintext: "مُنَاقَشَةُ سُبُلِ اِسْتِخْدَامِ اللُّغَةِ فِي النُّظُمِ الْقَائِمَةِ وَفِيم يَخُصَّ التَّطْبِيقَاتُ الْحاسُوبِيَّةُ،",
            payload: "An9KLkWvdew3A1i5Z3xwrlwuW69a2rtuDgQCVp6LyohELQvf2DKrSs0dXMOJGPBGJZrI/5Ksf2bNhT6VaJCDnJQyXq3qLZMOO7ET7w7f75Vomf2eMCiJDgNqWRIpFzGzC7gPS0LAU5UATIw4bWUHTNXMPRKTMfYvvBHDx9x2ueHBFQnh3RktqipSfJKdXKQnZOmKsT5fN8BIE3VObmxUd6KtYMf9uf5soJWNNbcdLUgAQZ1IZN5xLfnaHNEnsXEIqRJnPqrBqzFsFm/sAn5UXfXs6F7QFEb/cxzD7R0Mef2C3bNZxvfPqxXqPUJI8x2084vKLO5BM7ccLuIOACzRQGN/N9sR1mUV9xEwChmK7HAyqTrEnty+hIkgAWT2FGx8wH3E"
        ),
        EncryptionVector(
            conversationKey: "860b3deaba8d5e578e2dc45033b5ce5af37bcc58c86fc70c4cd4e9eef39b97c0",
            nonce: "3d437198053cd0e5f96fea622c4f4fc08e886bde0292e6b60c678148f2a57363",
            plaintext: "الكون",
            payload: "Aj1DcZgFPNDl+W/qYixPT8COiGveApKOa2DGeBSPKlc2MwCt2v7AlJR0GTVe7OaKkYNk5iLF5P8l2MbiU1X2g2OerJRAkUrQJhBqkT3QRO5I7mzHGGTYFHjh3cVv9Fwh"
        ),
        EncryptionVector(
            conversationKey: "b16ab8a3f8196ec2e533c7fb7b3c0a0ad9163b38fcef12cc26f460e22e0fa651",
            nonce: "0e63011f3f573e2fb656b75cc2a10c7f3026ad3f4e1f41db9c3154f0c3797d23",
            plaintext: "🥎",
            payload: "Ag5jAR8/Vz4vtla3XMKhDH8wJq0/Th9B25wxVPDDeX0jo5A3pAQxSXQ6M7Xh+rEZJLkBCJsOcMN1gLXtdEo8c4bu0HtYqxsbKnHjXWN/qYoq5uMttJLyWpmeb5ghEZsX"
        ),
        EncryptionVector(
            conversationKey: "8cd4b389a4fb9980ccca7b14ca3c0b5f275b606b77b1216fdfec198899452b68",
            nonce: "a06f8a5b089d7fb816dc96004c156e0c96e6e8b9e906cf263d8af72709bb6292",
            plaintext: "لا أحد يحب الألم بذاته، يسعى ورائه أو يبتغيه، ببساطة لأنه الألم...",
            payload: "AqBvilsInX+4FtyWAEwVbgyW5ui56QbPJj2K9ycJu2KSBJBs7dHcVrPy9cG5p9K2YYKnTRcfLnYdpjipvYRJcBypI1k4q8haRglBaLL7hhL1J8xMM9AqOXBM8J1NkQ8koH+8MZGgUiEYLEb4NI8XYx5xqMU7sYQDzQVJ1CkHcAdSf6eRtsK5Z1KGLCOgIgN4"
        ),
        EncryptionVector(
            conversationKey: "9e266d776ec1957bb7a3533b9727d5fb1ada3e19aeafb15ffd0ebb080c28fe15",
            nonce: "4dd87928f44b8ddaa37c62c96378e4cc652c8b97ea17ee3f2dfaee5e2bb723c5",
            plaintext: "' 𝖠𝗇𝖽 𝗂𝖿 𝗒𝗈𝗎 𝗀𝖺𝗓𝖾 𝖿𝗈𝗋 𝗅𝗈𝗇𝗀 𝖾𝗇𝗈𝗎𝗀𝗁 𝗂𝗇𝗍𝗈 𝖺𝗇 𝖺𝖻𝗒𝗌𝗌, 𝗍𝗁𝖾 𝖺𝖻𝗒𝗌𝗌 𝗀𝖺𝗓𝖾𝗌 𝖺𝗅𝗌𝗈 𝗂𝗇𝗍𝗈 𝗒𝗈𝗎. '",
            payload: "Ak3YeShEuN2qN8YsljeOTMZSyLl+oX7j8t+u5eK7cjxVYD0cXa5yfk0L0RKna5Etrx5sCA1vAyB3nRGgPFBKr2Wug4OJtLjBGSl7Wjf4Xakb5AcaLMJmOOIRDvfJnEoLNODTJsaGYJU3i5fT9JNrWq+xNd7kLDr8Tb5aZJGZMNwoOKzGBBUHGIDL8Nk8LXvCClyU7TJhPKCxv7lKSCPxLWE8P/cHe2UYzyNNA6IH5Y9DjFl5mMWMLlP1nA8cRH9S5e6hnCQZEUFjcVs0wPMT7hJ1oFEMJTBv3F1GTWZN7TETxAM="
        )
    ]
    
    // Invalid conversation key test vectors
    struct InvalidConversationKeyVector {
        let sec1: String
        let pub2: String
        let note: String
    }
    
    let invalidConversationKeyVectors = [
        InvalidConversationKeyVector(
            sec1: "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
            pub2: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            note: "sec1 higher than curve.n"
        ),
        InvalidConversationKeyVector(
            sec1: "0000000000000000000000000000000000000000000000000000000000000000",
            pub2: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            note: "sec1 is 0"
        ),
        InvalidConversationKeyVector(
            sec1: "0a2b6e90f03c1c3407f7ee89c1f2995cf15f6f96b825c432d8ad1be4b1e43b69",
            pub2: "0000000000000000000000000000000000000000000000000000000000000000",
            note: "pub2 is 0"
        ),
        InvalidConversationKeyVector(
            sec1: "0a2b6e90f03c1c3407f7ee89c1f2995cf15f6f96b825c432d8ad1be4b1e43b69",
            pub2: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            note: "pub2 is invalid"
        )
    ]
    
    // Padding test vectors
    struct PaddingTestVector {
        let unpadded: Int
        let padded: Int
    }
    
    // Official padding test vectors from nostr-tools
    let paddingTestVectors = [
        PaddingTestVector(unpadded: 16, padded: 32),
        PaddingTestVector(unpadded: 32, padded: 32),
        PaddingTestVector(unpadded: 33, padded: 64),
        PaddingTestVector(unpadded: 37, padded: 64),
        PaddingTestVector(unpadded: 45, padded: 64),
        PaddingTestVector(unpadded: 49, padded: 64),
        PaddingTestVector(unpadded: 64, padded: 64),
        PaddingTestVector(unpadded: 65, padded: 96),
        PaddingTestVector(unpadded: 100, padded: 128),
        PaddingTestVector(unpadded: 111, padded: 128),
        PaddingTestVector(unpadded: 200, padded: 224),
        PaddingTestVector(unpadded: 250, padded: 256),
        PaddingTestVector(unpadded: 320, padded: 320),
        PaddingTestVector(unpadded: 383, padded: 384),
        PaddingTestVector(unpadded: 384, padded: 384),
        PaddingTestVector(unpadded: 400, padded: 448),
        PaddingTestVector(unpadded: 500, padded: 512),
        PaddingTestVector(unpadded: 512, padded: 512),
        PaddingTestVector(unpadded: 515, padded: 640),
        PaddingTestVector(unpadded: 700, padded: 768),
        PaddingTestVector(unpadded: 800, padded: 896),
        PaddingTestVector(unpadded: 900, padded: 1024),
        PaddingTestVector(unpadded: 1020, padded: 1024),
        PaddingTestVector(unpadded: 65536, padded: 65536)
    ]
    
    // MARK: - Tests
    
    
    func testConversationKeys() throws {
        for (index, vector) in conversationKeyVectors.enumerated() {
            do {
                let conversationKey = try NIP44.getConversationKey(
                    privateKey: vector.sec1,
                    publicKey: vector.pub2
                )
                
                let expectedKey = Data(hexString: vector.conversationKey)!
                XCTAssertEqual(
                    conversationKey, 
                    expectedKey,
                    "Conversation key mismatch for vector \(index): \(vector.note ?? "unnamed")"
                )
            } catch {
                XCTFail("Failed on vector \(index) (\(vector.note ?? "unnamed")): \(error)")
            }
        }
    }
    
    func testInvalidConversationKeys() {
        for vector in invalidConversationKeyVectors {
            XCTAssertThrowsError(
                try NIP44.getConversationKey(
                    privateKey: vector.sec1,
                    publicKey: vector.pub2
                ),
                "Should throw error for: \(vector.note)"
            )
        }
    }
    
    func testEncryptionDecryption() throws {
        // Test just the first vector to debug
        let vector = encryptionVectors.first!
        let conversationKey = Data(hexString: vector.conversationKey)!
        let nonce = Data(hexString: vector.nonce)!
        
        // Test encryption with known nonce
        let encrypted = try NIP44.encrypt(
            plaintext: vector.plaintext,
            conversationKey: conversationKey,
            nonce: nonce
        )
        
        XCTAssertEqual(
            encrypted,
            vector.payload,
            "Encrypted payload mismatch for plaintext: \(vector.plaintext)"
        )
        
        // Test decryption
        let decrypted = try NIP44.decrypt(
            payload: vector.payload,
            conversationKey: conversationKey
        )
        
        XCTAssertEqual(
            decrypted,
            vector.plaintext,
            "Decrypted plaintext mismatch for: \(vector.plaintext)"
        )
    }
    
    func testPadding() {
        for vector in paddingTestVectors {
            let calculated = NIP44.calcPaddedLen(vector.unpadded)
            XCTAssertEqual(
                calculated,
                vector.padded,
                "Padding mismatch for unpadded length: \(vector.unpadded)"
            )
        }
    }
    
    func testHighLevelEncryptionDecryption() throws {
        // Test with actual key pairs
        let privateKey1 = "0a2b6e90f03c1c3407f7ee89c1f2995cf15f6f96b825c432d8ad1be4b1e43b69"
        let publicKey1 = try Crypto.getPublicKey(from: privateKey1)
        
        let privateKey2 = "7e31828ff72fa197b3ab2741284feec89752b48c67e82e09b5c2bce5b60caa33"
        let publicKey2 = try Crypto.getPublicKey(from: privateKey2)
        
        let plaintext = "Hello, NIP-44! 🚀"
        
        // User 1 encrypts for User 2
        let encrypted = try NIP44.encrypt(
            message: plaintext,
            privateKey: privateKey1,
            publicKey: publicKey2
        )
        
        // User 2 decrypts from User 1
        let decrypted = try NIP44.decrypt(
            encrypted: encrypted,
            privateKey: privateKey2,
            publicKey: publicKey1
        )
        
        XCTAssertEqual(decrypted, plaintext)
    }
    
    func testIntegrationWithCrypto() throws {
        // Test integration with Crypto wrapper functions
        let privateKey = "0a2b6e90f03c1c3407f7ee89c1f2995cf15f6f96b825c432d8ad1be4b1e43b69"
        let publicKey = "5dd17a853b43cf5b3aefa4ee9c9ba5ae09bda4c88b70b017f0e28e8fdc6ece56"
        
        let plaintext = "Testing Crypto.nip44Encrypt integration"
        
        // Test through Crypto wrapper
        let encrypted = try Crypto.nip44Encrypt(
            message: plaintext,
            privateKey: privateKey,
            publicKey: publicKey
        )
        
        let decrypted = try Crypto.nip44Decrypt(
            encrypted: encrypted,
            privateKey: privateKey,
            publicKey: publicKey
        )
        
        XCTAssertEqual(decrypted, plaintext)
    }
    
    func testInvalidPayloads() {
        let conversationKey = Data(hexString: "0000000000000000000000000000000000000000000000000000000000000001")!
        
        // Test invalid base64
        XCTAssertThrowsError(
            try NIP44.decrypt(payload: "not-valid-base64!", conversationKey: conversationKey)
        )
        
        // Test too short payload
        XCTAssertThrowsError(
            try NIP44.decrypt(payload: "dGVzdA==", conversationKey: conversationKey)
        )
        
        // Test future version (starts with #)
        XCTAssertThrowsError(
            try NIP44.decrypt(payload: "#future-version", conversationKey: conversationKey)
        )
    }
    
    func testEdgeCases() throws {
        let privateKey = "0a2b6e90f03c1c3407f7ee89c1f2995cf15f6f96b825c432d8ad1be4b1e43b69"
        let publicKey = "5dd17a853b43cf5b3aefa4ee9c9ba5ae09bda4c88b70b017f0e28e8fdc6ece56"
        
        // Test empty string - should throw error as min plaintext size is 1
        let empty = ""
        XCTAssertThrowsError(
            try NIP44.encrypt(message: empty, privateKey: privateKey, publicKey: publicKey),
            "Empty string should throw error"
        )
        
        // Test single character
        let single = "a"
        let encryptedSingle = try NIP44.encrypt(message: single, privateKey: privateKey, publicKey: publicKey)
        let decryptedSingle = try NIP44.decrypt(encrypted: encryptedSingle, privateKey: privateKey, publicKey: publicKey)
        XCTAssertEqual(decryptedSingle, single)
        
        // Test long string (should work up to 65535 bytes)
        let long = String(repeating: "x", count: 10000)
        let encryptedLong = try NIP44.encrypt(message: long, privateKey: privateKey, publicKey: publicKey)
        let decryptedLong = try NIP44.decrypt(encrypted: encryptedLong, privateKey: privateKey, publicKey: publicKey)
        XCTAssertEqual(decryptedLong, long)
    }
}

extension Data {
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}