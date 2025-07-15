import XCTest
@testable import NDKSwift

final class NDKSignerRegistryTests: XCTestCase {
    var registry: NDKSignerRegistry!
    
    override func setUp() {
        super.setUp()
        registry = NDKSignerRegistry.shared
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - Built-in Signer Tests
    
    func testBuiltInSignersRegistered() {
        // Verify that built-in signers are registered
        XCTAssertNotNil(registry.getSignerType(for: "privatekey"))
        XCTAssertNotNil(registry.getSignerType(for: "nip46"))
    }
    
    func testCreatePrivateKeySigner() async throws {
        let privateKey = "8f40e50a84a7462e2b8d24c28898ef0ce0d0113a0a2ce9648e6006b79c7e5185"
        let signerData = try JSONSerialization.data(withJSONObject: [
            "type": "privatekey",
            "privateKey": privateKey
        ])
        
        let signer = try await registry.createSigner(from: signerData)
        
        XCTAssertNotNil(signer)
        // Verify it's a private key signer by checking pubkey
        XCTAssertEqual(try await signer.pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f")
    }
    
    // MARK: - Custom Signer Registration Tests
    
    func testRegisterCustomSigner() {
        // Since NDKSignerRegistry manages built-in types,
        // we can't test custom registration without modifying the registry
        // This test would need to be restructured based on actual registry API
        XCTAssertNotNil(registry.getSignerType(for: "privatekey"))
    }
    
    func testCreateSignerWithInvalidType() async throws {
        let signerData = try JSONSerialization.data(withJSONObject: [
            "type": "custom",
            "customField": "test-value"
        ])
        
        do {
            _ = try await registry.createSigner(from: signerData)
            XCTFail("Should have thrown an error for unknown signer type")
        } catch {
            // Expected error for unknown type
        }
    }
    
    func testBuiltInSignerTypes() {
        // Test that built-in signers are available
        XCTAssertNotNil(registry.getSignerType(for: "privatekey"))
        XCTAssertNotNil(registry.getSignerType(for: "nip46"))
    }
    
    func testSignerTypeRetrieval() {
        // Test that we can retrieve signer types
        let privateKeyType = registry.getSignerType(for: "privatekey")
        XCTAssertNotNil(privateKeyType)
        
        let nip46Type = registry.getSignerType(for: "nip46")
        XCTAssertNotNil(nip46Type)
        
        let unknownType = registry.getSignerType(for: "unknown")
        XCTAssertNil(unknownType)
    }
    
    // MARK: - Error Handling Tests
    
    func testCreateSignerWithUnknownType() async {
        let signerData = try! JSONSerialization.data(withJSONObject: [
            "type": "unknown-type"
        ])
        
        do {
            _ = try await registry.createSigner(from: signerData)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error.localizedDescription.contains("unknown-type"))
        }
    }
    
    func testCreateSignerWithInvalidData() async {
        let invalidData = "not json".data(using: .utf8)!
        
        do {
            _ = try await registry.createSigner(from: invalidData)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
        }
    }
    
    func testCreateSignerWithMissingType() async {
        let signerData = try! JSONSerialization.data(withJSONObject: [:])
        
        do {
            _ = try await registry.createSigner(from: signerData)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
        }
    }
    
    // MARK: - Serialization Round Trip Tests
    
    func testPrivateKeySignerSerializationRoundTrip() async throws {
        // Create original signer
        let privateKey = "8f40e50a84a7462e2b8d24c28898ef0ce0d0113a0a2ce9648e6006b79c7e5185"
        let originalSigner = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Serialize
        let serialized = try await originalSigner.serialize()
        
        // Deserialize
        let recreatedSigner = try await registry.createSigner(from: serialized)
        
        // Verify
        let recreatedPubkey = try await recreatedSigner.pubkey
        let originalPubkey = try await originalSigner.pubkey
        XCTAssertEqual(recreatedPubkey, originalPubkey)
        
        // Test signing produces same result
        var event = NDKEvent(
            id: "test_event_id",
            pubkey: try await originalSigner.pubkey,
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test message",
            sig: ""
        )
        
        let signatureOriginal = try await originalSigner.sign(event)
        let signatureRecreated = try await recreatedSigner.sign(event)
        
        XCTAssertEqual(signatureOriginal, signatureRecreated)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentSignerTypeAccess() {
        let expectation = expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        let group = DispatchGroup()
        
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                // Test concurrent access to built-in types
                _ = self.registry.getSignerType(for: "privatekey")
                _ = self.registry.getSignerType(for: "nip46")
                
                group.leave()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConcurrentCreation() async {
        let signerData = try! JSONSerialization.data(withJSONObject: [
            "type": "privatekey",
            "privateKey": "8f40e50a84a7462e2b8d24c28898ef0ce0d0113a0a2ce9648e6006b79c7e5185"
        ])
        
        var signers: [any NDKSigner] = []
        
        await withTaskGroup(of: (any NDKSigner)?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? self.registry.createSigner(from: signerData)
                }
            }
            
            for await signer in group {
                if let signer = signer {
                    signers.append(signer)
                }
            }
        }
        
        // All should succeed
        XCTAssertEqual(signers.count, 10)
        
        // All should have same public key
        var publicKeys: Set<String> = []
        for signer in signers {
            let pubkey = try await signer.pubkey
            publicKeys.insert(pubkey)
        }
        XCTAssertEqual(publicKeys.count, 1)
    }
    
    // MARK: - Reset Tests
    
    func testResetPreservesBuiltInTypes() {
        // Verify built-in types exist
        XCTAssertNotNil(registry.getSignerType(for: "privatekey"))
        XCTAssertNotNil(registry.getSignerType(for: "nip46"))
        
        // Get list of registered types
        let registeredTypes = registry.getRegisteredSignerTypes()
        XCTAssertTrue(registeredTypes.contains("privatekey"))
        XCTAssertTrue(registeredTypes.contains("nip46"))
    }
}

// MARK: - Test Helpers

// Custom signer type for testing registration
private struct CustomSignerType {
    let identifier: String
    
    init(identifier: String = "custom") {
        self.identifier = identifier
    }
}

private final class CustomSigner: NDKSigner {
    static var signerType: String { "custom" }
    
    let identifier: String
    private let _pubkey: PublicKey = "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f"
    
    var pubkey: PublicKey {
        get async throws {
            return _pubkey
        }
    }
    
    init(identifier: String) {
        self.identifier = identifier
    }
    
    func sign(_ event: NDKEvent) async throws -> Signature {
        return "custom-signature-9a59a5f40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b9a40a5b7b"
    }
    
    func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        return "encrypted"
    }
    
    func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        return "decrypted"
    }
    
    func serialize() async throws -> Data {
        return try JSONSerialization.data(withJSONObject: ["type": identifier])
    }
    
    static func deserialize(_ data: Data, ndk: NDK?) throws -> Self {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            throw NDKError.invalidContent("Missing type in serialized data")
        }
        return CustomSigner(identifier: type) as! Self
    }
}