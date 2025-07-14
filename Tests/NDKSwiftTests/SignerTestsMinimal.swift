import XCTest
@testable import NDKSwift

// Minimal test file to verify signer functionality
final class SignerTestsMinimal: XCTestCase {
    
    func test_privateKeySigner_basic() async throws {
        // Test key initialization
        let privateKey = "5dab4439106cf3d98a77b18835a5c830dfa1cb2d08c6a7ea7a3b0de0e35b47f7"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Test public key derivation
        let pubkey = try await signer.pubkey
        XCTAssertEqual(pubkey, TestKeys.alicePublicKey)
        
        // Test event signing
        let event = NDKEvent(
            id: "4b697394206581b03ca5222b37449a9cdca1741b122d78defc177444e2536f49",
            pubkey: pubkey,
            createdAt: 1640995200,
            kind: 1,
            tags: [],
            content: "Hello, Nostr!",
            sig: ""
        )
        
        let signature = try await signer.sign(event)
        XCTAssertFalse(signature.isEmpty)
        XCTAssertEqual(signature.count, 128)
    }
    
    func test_privateKeySigner_generate() throws {
        let signer = try NDKPrivateKeySigner.generate()
        XCTAssertNotNil(signer)
        XCTAssertEqual(signer.privateKeyValue.count, 64)
    }
}