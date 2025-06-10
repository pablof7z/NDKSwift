@testable import NDKSwift
import XCTest

final class CryptoTests: XCTestCase {
    
    // MARK: - Key Conversion Tests
    
    func testBasicKeyConversions() async throws {
        // Test vectors from multiple disabled tests
        let testCases = [
            (
                nsec: "nsec1j5sw4vtgzzvmrjtqynvre0fknyfyysjpul0t2eew50rngdgltxnq0efsa0",
                privateKey: "9520eab1681099b1c96024d83cbd369912424241e7deb5672ea3c734351f59a6",
                publicKey: "f79a99714c761c0e0fea6777a70103d71d75fb7900b0894bfe6c64054807b573",
                npub: "npub177dfju2vwcwqurl2vam6wqgr6uwht7meqzcgjjl7d3jq2jq8k4esskzh86"
            ),
            (
                nsec: "nsec1v2txyj42hwnupgafzjthe6qlz232en2lapzszga8nyk2zg59ckfs3rdtem",
                privateKey: "6296624aaabba7c0a3a914977ce81f12a2accd5fe8450123a7992ca12285c593",
                publicKey: "583e50994508feeee39035e86a2f6a73796c467813282d67380b1f3b5df76456",
                npub: "npub1tql9px29prlwacusxh5x5tm2wdukc3nczv5z6eecpv0nkh0hv3tqe8xv77"
            ),
            (
                nsec: "nsec1pnfm84sp6ed974zj7qsqqcn692hgnf9s48jk8x0psagucv6yy3ys5qqx7c",
                privateKey: "", // Not provided in original test
                publicKey: "2bfe63136e95ef81b137bd814405dfcaeeabd4bab04388f2167318001fb71473",
                npub: "" // Not provided in original test
            )
        ]
        
        for testCase in testCases {
            // Test nsec to private key conversion
            if !testCase.privateKey.isEmpty {
                let decodedPrivateKey = try Bech32.privateKey(from: testCase.nsec)
                XCTAssertEqual(decodedPrivateKey, testCase.privateKey,
                             "Private key mismatch for nsec: \(testCase.nsec)")
                
                // Test private key to public key derivation
                let derivedPublicKey = try Crypto.getPublicKey(from: decodedPrivateKey)
                XCTAssertEqual(derivedPublicKey, testCase.publicKey,
                             "Public key mismatch for nsec: \(testCase.nsec)")
            }
            
            // Test with NDKPrivateKeySigner
            let signer = try NDKPrivateKeySigner(nsec: testCase.nsec)
            let signerPublicKey = try await signer.pubkey
            XCTAssertEqual(signerPublicKey, testCase.publicKey,
                         "Signer public key mismatch for nsec: \(testCase.nsec)")
            
            // Test npub encoding if provided
            if !testCase.npub.isEmpty {
                let encodedNpub = try Bech32.npub(from: testCase.publicKey)
                XCTAssertEqual(encodedNpub, testCase.npub,
                             "Npub mismatch for public key: \(testCase.publicKey)")
                
                let signerNpub = try signer.npub
                XCTAssertEqual(signerNpub, testCase.npub,
                             "Signer npub mismatch for nsec: \(testCase.nsec)")
            }
        }
    }
    
    func testKeyGeneration() async throws {
        // Test key generation
        let signer = try NDKPrivateKeySigner.generate()
        let publicKey = try await signer.pubkey
        let npub = try signer.npub
        let nsec = try signer.nsec
        
        // Verify key formats
        XCTAssertEqual(publicKey.count, 64, "Public key should be 64 hex characters")
        XCTAssertTrue(nsec.hasPrefix("nsec1"), "Nsec should have correct prefix")
        XCTAssertTrue(npub.hasPrefix("npub1"), "Npub should have correct prefix")
        
        // Test consistency
        let publicKeyAgain = try await signer.pubkey
        XCTAssertEqual(publicKey, publicKeyAgain, "Public key should be consistent")
        
        // Test round-trip conversion
        let decodedPrivateKey = try Bech32.privateKey(from: nsec)
        let derivedPublicKey = try Crypto.getPublicKey(from: decodedPrivateKey)
        XCTAssertEqual(derivedPublicKey, publicKey, "Round-trip conversion should work")
    }
    
    func testInvalidInputs() async throws {
        // Test invalid nsec
        XCTAssertThrowsError(try Bech32.privateKey(from: "invalid_nsec")) { error in
            // Verify it's a proper error
            XCTAssertNotNil(error)
        }
        
        // Test invalid private key
        XCTAssertThrowsError(try Crypto.getPublicKey(from: "invalid_hex")) { error in
            XCTAssertNotNil(error)
        }
        
        // Test invalid public key for npub
        XCTAssertThrowsError(try Bech32.npub(from: "short")) { error in
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Signature Tests
    
    func testEventSigning() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let publicKey = try await signer.pubkey
        
        // Create an event
        let event = NDKEvent(
            pubkey: publicKey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test message"
        )
        
        // Sign the event
        let signature = try await signer.sign(event)
        
        // The signature is returned but event might not be modified
        XCTAssertEqual(signature.count, 128, "Signature should be 128 hex characters")
        
        // For in-place signing, we need to use the mutating version
        var mutableEvent = NDKEvent(
            pubkey: publicKey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test message"
        )
        
        try await signer.sign(event: &mutableEvent)
        
        // Now verify the mutable event has been signed
        XCTAssertNotNil(mutableEvent.id)
        XCTAssertNotNil(mutableEvent.sig)
        XCTAssertEqual(mutableEvent.id?.count, 64, "Event ID should be 64 hex characters")
        XCTAssertEqual(mutableEvent.sig?.count, 128, "Signature should be 128 hex characters")
    }
    
    func testEventSerializationForSigning() async throws {
        // Test that events can be properly serialized for signing
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        // Event should not have ID or signature before signing
        XCTAssertNil(event.id)
        XCTAssertNil(event.sig)
    }
}