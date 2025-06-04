import XCTest
@testable import NDKSwift

final class CryptoValidationTest: XCTestCase {
    
    func testSpecificKeyConversion() throws {
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
        print("DEBUG Test: Signer public key = '\(signer.publicKey)' (length: \(signer.publicKey.count))")
        XCTAssertEqual(signer.publicKey, expectedPublicKey, "Signer public key mismatch")
        
        let signerNpub = try Bech32.npub(from: signer.publicKey)
        print("DEBUG Test: Signer npub = '\(signerNpub)'")
        XCTAssertEqual(signerNpub, expectedNpub, "Signer npub mismatch")
        
        print("DEBUG Test: All conversions successful!")
    }
    
    func testGeneratedKeyConversion() throws {
        // Test with a newly generated key
        print("DEBUG Test: Testing generated key conversion")
        
        let generatedSigner = try NDKPrivateKeySigner.generate()
        print("DEBUG Test: Generated private key length = \(generatedSigner.privateKey.count)")
        print("DEBUG Test: Generated public key length = \(generatedSigner.publicKey.count)")
        
        // Validate lengths
        XCTAssertEqual(generatedSigner.privateKey.count, 64, "Generated private key should be 64 hex chars")
        XCTAssertEqual(generatedSigner.publicKey.count, 64, "Generated public key should be 64 hex chars")
        
        // Test round-trip conversion
        let nsec = try Bech32.nsec(from: generatedSigner.privateKey)
        print("DEBUG Test: Generated nsec = '\(nsec)'")
        
        let npub = try Bech32.npub(from: generatedSigner.publicKey)
        print("DEBUG Test: Generated npub = '\(npub)'")
        
        // Verify we can recreate the signer from the nsec
        let recreatedSigner = try NDKPrivateKeySigner(nsec: nsec)
        XCTAssertEqual(recreatedSigner.privateKey, generatedSigner.privateKey, "Round-trip private key failed")
        XCTAssertEqual(recreatedSigner.publicKey, generatedSigner.publicKey, "Round-trip public key failed")
        
        print("DEBUG Test: Generated key round-trip successful!")
    }
}