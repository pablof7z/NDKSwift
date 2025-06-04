import XCTest
@testable import NDKSwift

final class KeyDerivationTest: XCTestCase {
    
    func testSpecificKeyDerivation() async throws {
        // Test case provided by user
        let testNsec = "nsec1v2txyj42hwnupgafzjthe6qlz232en2lapzszga8nyk2zg59ckfs3rdtem"
        let expectedPrivateKey = "6296624aaabba7c0a3a914977ce81f12a2accd5fe8450123a7992ca12285c593"
        let expectedPubkey = "583e50994508feeee39035e86a2f6a73796c467813282d67380b1f3b5df76456"
        let expectedNpub = "npub1tql9px29prlwacusxh5x5tm2wdukc3nczv5z6eecpv0nkh0hv3tqe8xv77"
        
        print("=== Key Derivation Test ===")
        print("Input nsec: \(testNsec)")
        print("Expected private key: \(expectedPrivateKey)")
        print("Expected pubkey: \(expectedPubkey)")
        print("Expected npub: \(expectedNpub)")
        print()
        
        // Test 1: Decode nsec to private key
        print("=== Test 1: Decode nsec to private key ===")
        let decodedPrivateKey = try Bech32.privateKey(from: testNsec)
        print("Decoded private key: \(decodedPrivateKey)")
        print("Match: \(decodedPrivateKey == expectedPrivateKey)")
        XCTAssertEqual(decodedPrivateKey, expectedPrivateKey, "Private key should match")
        print()
        
        // Test 2: Direct crypto function
        print("=== Test 2: Direct crypto function ===")
        let directPubkey = try Crypto.getPublicKey(from: decodedPrivateKey)
        print("Direct crypto pubkey: \(directPubkey)")
        print("Direct crypto match: \(directPubkey == expectedPubkey)")
        
        // Test 3: Create signer and get pubkey
        print("=== Test 3: Create signer and get keys ===")
        let signer = try NDKPrivateKeySigner(nsec: testNsec)
        let derivedPubkey = try await signer.pubkey
        let derivedNpub = try signer.npub
        let derivedNsec = try signer.nsec
        
        print("Derived pubkey: \(derivedPubkey)")
        print("Derived npub: \(derivedNpub)")
        print("Derived nsec: \(derivedNsec)")
        print()
        
        print("=== Results ===")
        print("Private key match: \(decodedPrivateKey == expectedPrivateKey)")
        print("Pubkey match: \(derivedPubkey == expectedPubkey)")
        print("Npub match: \(derivedNpub == expectedNpub)")
        print("Nsec match: \(derivedNsec == testNsec)")
        
        if derivedPubkey != expectedPubkey {
            print()
            print("❌ PUBKEY MISMATCH!")
            print("Expected: \(expectedPubkey)")
            print("Got:      \(derivedPubkey)")
        } else {
            print()
            print("✅ PUBKEY MATCHES!")
        }
        
        if derivedNpub != expectedNpub {
            print()
            print("❌ NPUB MISMATCH!")
            print("Expected: \(expectedNpub)")
            print("Got:      \(derivedNpub)")
        } else {
            print()
            print("✅ NPUB MATCHES!")
        }
        
        // Assertions
        XCTAssertEqual(decodedPrivateKey, expectedPrivateKey, "Private key should match expected value")
        XCTAssertEqual(directPubkey, expectedPubkey, "Direct crypto public key should match expected value")
        XCTAssertEqual(derivedPubkey, expectedPubkey, "Public key should match expected value")
        XCTAssertEqual(derivedNpub, expectedNpub, "Npub should match expected value")
    }
}