@testable import NDKSwift
import XCTest

final class CryptoValidationTest: XCTestCase {
    func testSpecificKeyConversion() async throws {
        // Given: Known test vectors
        let testNsec = "nsec1j5sw4vtgzzvmrjtqynvre0fknyfyysjpul0t2eew50rngdgltxnq0efsa0"
        let expectedPrivateKey = "9520eab1681099b1c96024d83cbd369912424241e7deb5672ea3c734351f59a6"
        let expectedPublicKey = "f79a99714c761c0e0fea6777a70103d71d75fb7900b0894bfe6c64054807b573"
        let expectedNpub = "npub177dfju2vwcwqurl2vam6wqgr6uwht7meqzcgjjl7d3jq2jq8k4esskzh86"

        print("DEBUG Test: Starting key conversion test")
        print("DEBUG Test: Input nsec = '\(testNsec)'")

        // Test 1: Convert nsec to private key
        let privateKey = try Bech32.privateKey(from: testNsec)
        print("DEBUG Test: Decoded private key = '\(privateKey)' (length: \(privateKey.count))")
        XCTAssertEqual(privateKey, expectedPrivateKey, "Private key conversion failed")

        // Test 2: Derive public key from private key
        let publicKey = try Crypto.getPublicKey(from: privateKey)
        print("DEBUG Test: Derived public key = '\(publicKey)' (length: \(publicKey.count))")
        XCTAssertEqual(publicKey, expectedPublicKey, "Public key derivation failed")

        // Test 3: Convert public key to npub
        let npub = try Bech32.npub(from: publicKey)
        print("DEBUG Test: Encoded npub = '\(npub)'")
        XCTAssertEqual(npub, expectedNpub, "Npub encoding failed")

        // Test 4: Round-trip test with NDKPrivateKeySigner
        let signer = try NDKPrivateKeySigner(nsec: testNsec)
        let signerPublicKey = try await signer.pubkey
        print("DEBUG Test: Signer public key = '\(signerPublicKey)' (length: \(signerPublicKey.count))")
        XCTAssertEqual(signerPublicKey, expectedPublicKey, "Signer public key mismatch")

        let signerNpub = try Bech32.npub(from: signerPublicKey)
        print("DEBUG Test: Signer npub = '\(signerNpub)'")
        XCTAssertEqual(signerNpub, expectedNpub, "Signer npub mismatch")

        print("DEBUG Test: All conversions successful!")
    }

    func testGeneratedKeyConversion() async throws {
        // Test with a newly generated key
        print("DEBUG Test: Testing generated key conversion")

        let generatedSigner = try NDKPrivateKeySigner.generate()
        let generatedPublicKey = try await generatedSigner.pubkey
        print("DEBUG Test: Generated public key length = \(generatedPublicKey.count)")

        // Validate lengths
        XCTAssertEqual(generatedPublicKey.count, 64, "Generated public key should be 64 hex chars")

        // Test round-trip conversion
        let npub = try Bech32.npub(from: generatedPublicKey)
        print("DEBUG Test: Generated npub = '\(npub)'")

        // Verify we can get consistent public key from the same signer
        let recreatedPublicKey = try await generatedSigner.pubkey
        XCTAssertEqual(recreatedPublicKey, generatedPublicKey, "Public key should be consistent")

        print("DEBUG Test: Generated key round-trip successful!")
    }
}
