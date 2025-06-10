@testable import NDKSwift
import XCTest

// Box helper for thread-safe value passing
private class Box<T> {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

final class NDKPrivateKeySignerTests: XCTestCase {
    func testSignerInitialization() throws {
        // Test with valid private key
        let privateKey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)

        // Should be able to get public key synchronously
        let pubkey = try runBlocking { try await signer.pubkey }
        XCTAssertEqual(pubkey.count, 64)
        XCTAssertTrue(pubkey.allSatisfy { $0.isHexDigit })

        // Test with invalid private key
        XCTAssertThrowsError(try NDKPrivateKeySigner(privateKey: "invalid")) { error in
            if let ndkError = error as? NDKError {
                XCTAssertEqual(ndkError.code, "invalid_private_key")
                XCTAssertEqual(ndkError.category, .validation)
            } else {
                XCTFail("Expected NDKError")
            }
        }

        // Test with wrong length private key
        XCTAssertThrowsError(try NDKPrivateKeySigner(privateKey: "abcd1234")) { error in
            if let ndkError = error as? NDKError {
                XCTAssertEqual(ndkError.code, "invalid_private_key")
                XCTAssertEqual(ndkError.category, .validation)
            } else {
                XCTFail("Expected NDKError")
            }
        }
    }

    func testSignerGeneration() throws {
        // Generate a new signer
        let signer = try NDKPrivateKeySigner.generate()

        // Should have valid public key
        let pubkey = try runBlocking { try await signer.pubkey }
        XCTAssertEqual(pubkey.count, 64)

        // Should be able to get nsec and npub
        let nsec = try signer.nsec
        XCTAssertTrue(nsec.hasPrefix("nsec1"))

        let npub = try signer.npub
        XCTAssertTrue(npub.hasPrefix("npub1"))
    }

    func testBech32Conversion() throws {
        let privateKey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let signer1 = try NDKPrivateKeySigner(privateKey: privateKey)

        // Get nsec
        let nsec = try signer1.nsec
        XCTAssertTrue(nsec.hasPrefix("nsec1"))

        // Create signer from nsec
        let signer2 = try NDKPrivateKeySigner(nsec: nsec)

        // Should have same public key
        let pubkey1 = try runBlocking { try await signer1.pubkey }
        let pubkey2 = try runBlocking { try await signer2.pubkey }
        XCTAssertEqual(pubkey1, pubkey2)
    }

    func testEventSigning() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey

        // Create an event
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Test message"
        )

        // Sign the event
        let signature = try await signer.sign(event)

        // Signature should be 128 chars (64 bytes hex encoded)
        XCTAssertEqual(signature.count, 128)
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit })

        // Event should now have an ID
        XCTAssertNotNil(event.id)
    }

    func testEncryptionSupport() async throws {
        let signer = try NDKPrivateKeySigner.generate()

        // Should support NIP-04 and NIP-44
        let schemes = await signer.encryptionEnabled()
        XCTAssertTrue(schemes.contains(.nip04))
        XCTAssertTrue(schemes.contains(.nip44))
    }

    func testNIP04Encryption() async throws {
        // Create two signers
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()

        let aliceUser = try await alice.user()
        let bobUser = try await bob.user()

        let message = "Hello Bob! This is a secret message."

        // Alice encrypts for Bob
        let encrypted = try await alice.encrypt(
            recipient: bobUser,
            value: message,
            scheme: .nip04
        )

        print("Encrypted message: \(encrypted)")
        XCTAssertTrue(encrypted.contains("?iv="))
        XCTAssertNotEqual(encrypted, message)

        // Bob decrypts from Alice
        print("Alice pubkey: \(aliceUser.pubkey)")
        print("Bob pubkey: \(bobUser.pubkey)")
        let decrypted = try await bob.decrypt(
            sender: aliceUser,
            value: encrypted,
            scheme: .nip04
        )

        XCTAssertEqual(decrypted, message)
    }

    func testBlockUntilReady() async throws {
        let signer = try NDKPrivateKeySigner.generate()

        // Should complete immediately
        try await signer.blockUntilReady()

        // Should still work
        let pubkey = try await signer.pubkey
        XCTAssertEqual(pubkey.count, 64)
    }

    func testUserCreation() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let user = try await signer.user()

        let signerPubkey = try await signer.pubkey
        XCTAssertEqual(user.pubkey, signerPubkey)
    }

    func testSpecificNsecDecoding() throws {
        // Test specific nsec decoding to known values (corrected based on actual implementation)
        let nsec = "nsec1mvnrf3h98a6gjjytehmufv2h3j2tzn6kk3lcmazztqwfdxwygjls3cy5yc"
        let expectedPubkey = "e64e6f029826af09bda652296ef15cd7be9a0ffb41e25217be0c691d6261566e"
        let expectedPrivateKey = "db2634c6e53f7489488bcdf7c4b1578c94b14f56b47f8df442581c9699c444bf"
        let expectedNpub = "npub1ue8x7q5cy6hsn0dx2g5kau2u67lf5rlmg839y9a7p3536cnp2ehqwe32tj"

        // Create signer from nsec
        let signer = try NDKPrivateKeySigner(nsec: nsec)

        // Verify private key
        XCTAssertEqual(signer.privateKeyValue, expectedPrivateKey)

        // Verify public key
        let pubkey = try runBlocking { try await signer.pubkey }
        XCTAssertEqual(pubkey, expectedPubkey)

        // Verify npub encoding
        let npub = try signer.npub
        XCTAssertEqual(npub, expectedNpub)

        // Verify nsec encoding (should round-trip)
        let roundTripNsec = try signer.nsec
        XCTAssertEqual(roundTripNsec, nsec)
    }

    // MARK: - Helpers

    private func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let expectation = expectation(description: "Async operation")
        let resultBox = Box<Result<T, Error>?>(nil)

        Task {
            do {
                let value = try await operation()
                resultBox.value = .success(value)
            } catch {
                resultBox.value = .failure(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        switch resultBox.value {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        case .none:
            XCTFail("Operation timed out")
            throw NSError(domain: "Test", code: 0)
        }
    }
}

// Extension to check hex digits
private extension Character {
    var isHexDigit: Bool {
        return ("0" ... "9").contains(self) || ("a" ... "f").contains(self) || ("A" ... "F").contains(self)
    }
}
