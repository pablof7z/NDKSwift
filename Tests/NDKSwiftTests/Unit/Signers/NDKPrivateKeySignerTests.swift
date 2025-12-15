@testable import NDKSwiftCore
import XCTest

final class NDKPrivateKeySignerTests: XCTestCase {
    // Test private key (32 bytes hex) - use a well-known test vector
    let testPrivateKey = "0000000000000000000000000000000000000000000000000000000000000001"
    // Expected public key for the test private key (calculated using secp256k1)
    let testPublicKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    // Note: We'll skip nsec/npub tests since those require exact bech32 encoding
    // which is hard to predict without running the actual code

    // MARK: - Initialization Tests

    func testInitWithValidPrivateKey() throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)

        XCTAssertEqual(signer.privateKeyValue, testPrivateKey)
        XCTAssertEqual(signer.privateKeyForNIP59, testPrivateKey)
    }

    func testInitWithInvalidPrivateKeyLength() {
        // Too short
        XCTAssertThrowsError(try NDKPrivateKeySigner(privateKey: "abc123")) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            if case .invalidInput = ndkError {
                // Expected error (invalidDataFormat factory returns invalidInput)
            } else {
                XCTFail("Expected invalidInput error, got \(ndkError)")
            }
        }

        // Too long
        let longKey = testPrivateKey + "00"
        XCTAssertThrowsError(try NDKPrivateKeySigner(privateKey: longKey)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            if case .invalidInput = ndkError {
                // Expected error (invalidDataFormat factory returns invalidInput)
            } else {
                XCTFail("Expected invalidInput error, got \(ndkError)")
            }
        }
    }

    func testInitWithInvalidPrivateKeyCharacters() {
        let invalidKey = "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg" // 'g' is not valid hex

        XCTAssertThrowsError(try NDKPrivateKeySigner(privateKey: invalidKey)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            if case .invalidInput = ndkError {
                // Expected error (invalidDataFormat factory returns invalidInput)
            } else {
                XCTFail("Expected invalidInput error, got \(ndkError)")
            }
        }
    }

    func testInitWithNsec() throws {
        // Use a known good nsec from Bech32Tests
        let knownNsec = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"
        let expectedPrivKey = "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa"

        let signer = try NDKPrivateKeySigner(nsec: knownNsec)

        XCTAssertEqual(signer.privateKeyValue, expectedPrivKey)
    }

    func testInitWithInvalidNsec() {
        // Invalid bech32
        XCTAssertThrowsError(try NDKPrivateKeySigner(nsec: "invalid-nsec")) { error in
            XCTAssertNotNil(error)
        }

        // Wrong prefix
        XCTAssertThrowsError(try NDKPrivateKeySigner(nsec: "npub1abc")) { error in
            XCTAssertNotNil(error)
        }
    }

    func testGenerate() async throws {
        let signer1 = try NDKPrivateKeySigner.generate()
        let signer2 = try NDKPrivateKeySigner.generate()

        // Should generate different keys
        XCTAssertNotEqual(signer1.privateKeyValue, signer2.privateKeyValue)

        // Keys should be valid 32-byte hex
        XCTAssertEqual(signer1.privateKeyValue.count, 64)
        XCTAssertEqual(signer2.privateKeyValue.count, 64)

        // Should be able to get public keys
        let pubkey1 = try await signer1.pubkey
        let pubkey2 = try await signer2.pubkey
        XCTAssertNotEqual(pubkey1, pubkey2)
    }

    // MARK: - Public Key Tests

    func testPubkey() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let pubkey = try await signer.pubkey

        XCTAssertEqual(pubkey, testPublicKey)
    }

    func testNpubGeneration() throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let npub = try signer.npub

        // Just verify it's a valid npub format
        XCTAssertTrue(npub.hasPrefix("npub1"))
        XCTAssertTrue(npub.count > 60) // npub addresses are typically 63 chars
    }

    func testNsecGeneration() throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let nsec = try signer.nsec

        // Just verify it's a valid nsec format
        XCTAssertTrue(nsec.hasPrefix("nsec1"))
        XCTAssertTrue(nsec.count > 60) // nsec addresses are typically 63 chars

        // Verify round-trip
        let signer2 = try NDKPrivateKeySigner(nsec: nsec)
        XCTAssertEqual(signer2.privateKeyValue, testPrivateKey)
    }

    // MARK: - Signing Tests

    func testSignEvent() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)

        // Create a test event
        let event = NDKEvent(
            id: "",
            pubkey: testPublicKey,
            createdAt: 1_234_567_890,
            kind: EventKind.metadata,
            tags: [],
            content: "test content",
            sig: ""
        )

        // Generate the event ID
        let calculatedId = try event.calculateID()
        let mutableEvent = NDKEvent(
            id: calculatedId,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )

        // Sign the event
        let signature = try await signer.sign(mutableEvent)

        // Verify signature format (should be 128 character hex)
        XCTAssertEqual(signature.count, 128)
        XCTAssert(HexValidator.isValidHex(signature))

        // Verify the signature is valid
        let idData = try HexValidator.validate32ByteHex(mutableEvent.id)
        let isValid = try Crypto.verify(
            signature: signature,
            message: idData,
            pubkey: testPublicKey
        )
        XCTAssertTrue(isValid)
    }

    func testSignEventWithInvalidID() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)

        // Create test event data
        let eventData = NDKEvent(
            id: "",
            pubkey: testPublicKey,
            createdAt: 1_234_567_890,
            kind: EventKind.metadata,
            tags: [],
            content: "test content",
            sig: ""
        )

        // Create event with invalid ID
        let invalidEvent = NDKEvent(
            id: "invalid-id", // Not a valid 32-byte hex
            pubkey: eventData.pubkey,
            createdAt: eventData.createdAt,
            kind: eventData.kind,
            tags: eventData.tags,
            content: eventData.content,
            sig: eventData.sig
        )

        await XCTAssertThrowsAsyncError(try await signer.sign(invalidEvent)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            if case .invalidInput = ndkError {
                // Expected error (parseError factory returns invalidInput)
            } else {
                XCTFail("Expected invalidInput error, got \(ndkError)")
            }
        }
    }

    // MARK: - Always Ready Tests

    func testBlockUntilReady() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)

        // Should complete immediately without error
        try await signer.blockUntilReady()
    }

    // MARK: - Encryption Tests

    func testEncryptionEnabled() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let schemes = await signer.encryptionEnabled()

        XCTAssertEqual(schemes.count, 2)
        XCTAssertTrue(schemes.contains(.nip04))
        XCTAssertTrue(schemes.contains(.nip44))
    }

    func testEncryptDecryptNIP04() async throws {
        // Create two signers
        let signer1 = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let signer2 = try NDKPrivateKeySigner.generate()

        // Get pubkeys
        let pubkey1 = try await signer1.pubkey
        let pubkey2 = try await signer2.pubkey

        let message = "Hello, NIP-04!"

        // Encrypt with signer1 for pubkey2
        let encrypted = try await signer1.encrypt(recipientPubkey: pubkey2, value: message, scheme: .nip04)

        // Encrypted should be different from original
        XCTAssertNotEqual(encrypted, message)

        // Decrypt with signer2
        let decrypted = try await signer2.decrypt(senderPubkey: pubkey1, value: encrypted, scheme: .nip04)

        // Should match original
        XCTAssertEqual(decrypted, message)
    }

    func testEncryptDecryptNIP44() async throws {
        // Create two signers
        let signer1 = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let signer2 = try NDKPrivateKeySigner.generate()

        // Get pubkeys
        let pubkey1 = try await signer1.pubkey
        let pubkey2 = try await signer2.pubkey

        let message = "Hello, NIP-44! 🚀"

        // Encrypt with signer1 for pubkey2
        let encrypted = try await signer1.encrypt(recipientPubkey: pubkey2, value: message, scheme: .nip44)

        // Encrypted should be different from original
        XCTAssertNotEqual(encrypted, message)

        // Decrypt with signer2
        let decrypted = try await signer2.decrypt(senderPubkey: pubkey1, value: encrypted, scheme: .nip44)

        // Should match original
        XCTAssertEqual(decrypted, message)
    }

    func testCrossSchemeEncryptionFails() async throws {
        // Create two signers
        let signer1 = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let signer2 = try NDKPrivateKeySigner.generate()

        // Get pubkeys
        let pubkey1 = try await signer1.pubkey
        let pubkey2 = try await signer2.pubkey

        let message = "Test message"

        // Encrypt with NIP-04
        let encrypted = try await signer1.encrypt(recipientPubkey: pubkey2, value: message, scheme: .nip04)

        // Try to decrypt with NIP-44 (should fail)
        await XCTAssertThrowsAsyncError(try await signer2.decrypt(senderPubkey: pubkey1, value: encrypted, scheme: .nip44)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            // cryptoOperation factory can return various crypto errors
            switch ndkError {
            case .encryptionFailed, .decryptionFailed, .signingFailed, .verificationFailed, .keyDerivationFailed:
                // Expected crypto error
                break
            default:
                XCTFail("Expected crypto error, got \(ndkError)")
            }
        }
    }

    // MARK: - Serialization Tests

    func testSignerType() {
        XCTAssertEqual(NDKPrivateKeySigner.signerType, "privatekey")
    }

    func testSerialize() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let data = try await signer.serialize()

        // Deserialize the container to verify structure
        let container = try JSONCoding.parseDictionary(from: data)
        XCTAssertEqual(container["type"] as? String, "privatekey")

        // Extract and verify payload
        guard let payloadDict = container["payload"] as? [String: Any] else {
            XCTFail("Missing payload")
            return
        }

        XCTAssertEqual(payloadDict["privateKey"] as? String, testPrivateKey)
    }

    func testDeserialize() async throws {
        // Create and serialize a signer
        let originalSigner = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let serializedData = try await originalSigner.serialize()

        // Extract payload from container for deserialization
        let container = try JSONCoding.parseDictionary(from: serializedData)
        guard let payload = container["payload"] as? [String: Any] else {
            XCTFail("Missing payload")
            return
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        // Deserialize
        let deserializedSigner = try await NDKPrivateKeySigner.deserialize(payloadData, ndk: nil)

        // Verify it matches
        XCTAssertEqual(deserializedSigner.privateKeyValue, testPrivateKey)
        let pubkey = try await deserializedSigner.pubkey
        XCTAssertEqual(pubkey, testPublicKey)
    }

    func testDeserializeWithMissingPrivateKey() async throws {
        let invalidPayload: [String: Any] = [:]
        let payloadData = try JSONSerialization.data(withJSONObject: invalidPayload)

        do {
            _ = try await NDKPrivateKeySigner.deserialize(payloadData, ndk: nil)
            XCTFail("Expected error to be thrown")
        } catch {
            // Check for deserializationError
            XCTAssertTrue(error is NDKSignerRegistryError)
        }
    }

    // MARK: - Round Trip Tests

    func testSerializeDeserializeRoundTrip() async throws {
        // Generate a new signer
        let originalSigner = try NDKPrivateKeySigner.generate()
        let originalPubkey = try await originalSigner.pubkey

        // Serialize
        let serialized = try await originalSigner.serialize()

        // Extract payload from container
        let container = try JSONCoding.parseDictionary(from: serialized)
        guard let payload = container["payload"] as? [String: Any] else {
            XCTFail("Missing payload")
            return
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        // Deserialize
        let deserializedSigner = try await NDKPrivateKeySigner.deserialize(payloadData, ndk: nil)
        let deserializedPubkey = try await deserializedSigner.pubkey

        // Verify they match
        XCTAssertEqual(originalSigner.privateKeyValue, deserializedSigner.privateKeyValue)
        XCTAssertEqual(originalPubkey, deserializedPubkey)

        // Verify they can sign the same way
        let event = NDKEvent(
            id: "",
            pubkey: originalPubkey,
            createdAt: 1_234_567_890,
            kind: EventKind.metadata,
            tags: [],
            content: "test",
            sig: ""
        )
        let eventId = try event.calculateID()
        let eventWithId = NDKEvent(
            id: eventId,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )

        let sig1 = try await originalSigner.sign(eventWithId)
        let sig2 = try await deserializedSigner.sign(eventWithId)

        XCTAssertEqual(sig1, sig2)
    }

    // MARK: - Error Handling Tests

    func testEncryptWithInvalidRecipient() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let invalidPubkey = "invalid-pubkey"

        await XCTAssertThrowsAsyncError(try await signer.encrypt(recipientPubkey: invalidPubkey, value: "test", scheme: .nip04)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            // cryptoOperation factory can return various crypto errors
            switch ndkError {
            case .encryptionFailed, .decryptionFailed, .signingFailed, .verificationFailed, .keyDerivationFailed:
                // Expected crypto error
                break
            default:
                XCTFail("Expected crypto error, got \(ndkError)")
            }
        }
    }

    func testDecryptWithInvalidCiphertext() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)

        await XCTAssertThrowsAsyncError(try await signer.decrypt(senderPubkey: testPublicKey, value: "invalid-ciphertext", scheme: .nip04)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            // cryptoOperation factory can return various crypto errors
            switch ndkError {
            case .encryptionFailed, .decryptionFailed, .signingFailed, .verificationFailed, .keyDerivationFailed:
                // Expected crypto error
                break
            default:
                XCTFail("Expected crypto error, got \(ndkError)")
            }
        }
    }

    // MARK: - Pubkey Tests

    func testSignerPubkey() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: testPrivateKey)
        let pubkey = try await signer.pubkey

        XCTAssertEqual(pubkey, testPublicKey)
    }
}

// MARK: - Test Helpers

extension XCTestCase {
    func XCTAssertThrowsAsyncError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
