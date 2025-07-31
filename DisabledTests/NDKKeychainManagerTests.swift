import XCTest
@testable import NDKSwift

final class NDKKeychainManagerTests: XCTestCase {
    var keychainManager: NDKKeychainManager!
    let testSessionId = UUID()
    
    override func setUp() async throws {
        try await super.setUp()
        keychainManager = NDKKeychainManager()
        // Clean up any existing test data
        await cleanupTestData()
    }
    
    override func tearDown() async throws {
        await cleanupTestData()
        try await super.tearDown()
    }
    
    private func cleanupTestData() async {
        // Clean up signer data
        try? await keychainManager.deleteSignerData(identifier: testSessionId.uuidString)
        
        // Clean up session metadata
        let sessionIds = (try? await keychainManager.getAllSessionIdentifiers()) ?? []
        for id in sessionIds {
            try? await keychainManager.deleteSessionMetadata(identifier: id)
        }
    }
    
    // MARK: - Signer Data Tests
    
    func testSaveAndRetrieveSignerData() async throws {
        let testData = "test-signer-data".data(using: .utf8)!
        
        try await keychainManager.storeSignerData(
            identifier: testSessionId.uuidString,
            data: testData
        )
        
        let retrievedData = try await keychainManager.retrieveSignerData(
            identifier: testSessionId.uuidString
        )
        XCTAssertEqual(retrievedData, testData)
    }
    
    func testSaveSignerDataWithBiometric() async throws {
        let testData = "biometric-signer-data".data(using: .utf8)!
        
        try await keychainManager.storeSignerData(
            identifier: testSessionId.uuidString,
            data: testData,
            requiresBiometric: .required
        )
        
        // Note: In a real test environment, retrieving biometric-protected data
        // would require user authentication. Here we're just testing the save operation.
        // The retrieval might fail in test environment without biometric context.
    }
    
    func testUpdateSignerData() async throws {
        let originalData = "original-data".data(using: .utf8)!
        let updatedData = "updated-data".data(using: .utf8)!
        
        try await keychainManager.storeSignerData(
            identifier: testSessionId.uuidString,
            data: originalData
        )
        
        let retrieved1 = try await keychainManager.retrieveSignerData(
            identifier: testSessionId.uuidString
        )
        XCTAssertEqual(retrieved1, originalData)
        
        try await keychainManager.storeSignerData(
            identifier: testSessionId.uuidString,
            data: updatedData
        )
        
        let retrieved2 = try await keychainManager.retrieveSignerData(
            identifier: testSessionId.uuidString
        )
        XCTAssertEqual(retrieved2, updatedData)
    }
    
    func testDeleteSignerData() async throws {
        let testData = "test-data".data(using: .utf8)!
        
        try await keychainManager.storeSignerData(
            identifier: testSessionId.uuidString,
            data: testData
        )
        
        // Verify it exists
        let exists = await keychainManager.hasSignerData(identifier: testSessionId.uuidString)
        XCTAssertTrue(exists)
        
        try await keychainManager.deleteSignerData(identifier: testSessionId.uuidString)
        
        // Verify it's deleted
        do {
            _ = try await keychainManager.retrieveSignerData(identifier: testSessionId.uuidString)
            XCTFail("Should have thrown an error")
        } catch NDKKeychainError.itemNotFound {
            // Expected
        }
    }
    
    func testGetNonExistentSignerData() async {
        do {
            _ = try await keychainManager.retrieveSignerData(identifier: UUID().uuidString)
            XCTFail("Should have thrown an error")
        } catch NDKKeychainError.itemNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Session Metadata Tests
    
    func testSaveAndRetrieveSessionMetadata() async throws {
        let metadata = [
            "id": testSessionId.uuidString,
            "pubkey": "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            "signerType": "privatekey",
            "createdAt": Timestamp.now
        ] as [String: Any]
        
        let data = try JSONSerialization.data(withJSONObject: metadata)
        try await keychainManager.storeSessionMetadata(
            identifier: testSessionId.uuidString,
            data: data
        )
        
        let retrievedData = try await keychainManager.retrieveSessionMetadata(
            identifier: testSessionId.uuidString
        )
        let retrievedMetadata = try JSONSerialization.jsonObject(with: retrievedData) as! [String: Any]
        
        XCTAssertEqual(retrievedMetadata["id"] as? String, testSessionId.uuidString)
        XCTAssertEqual(retrievedMetadata["pubkey"] as? String, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f")
        XCTAssertEqual(retrievedMetadata["signerType"] as? String, "privatekey")
    }
    
    func testSaveMultipleSessionMetadata() async throws {
        let id1 = UUID()
        let id2 = UUID()
        
        let metadata1 = [
            "id": id1.uuidString,
            "pubkey": "pubkey1",
            "signerType": "privatekey",
            "createdAt": Timestamp.now
        ] as [String: Any]
        
        let metadata2 = [
            "id": id2.uuidString,
            "pubkey": "pubkey2",
            "signerType": "nip46",
            "createdAt": Timestamp.now
        ] as [String: Any]
        
        let data1 = try JSONSerialization.data(withJSONObject: metadata1)
        let data2 = try JSONSerialization.data(withJSONObject: metadata2)
        
        try await keychainManager.storeSessionMetadata(identifier: id1.uuidString, data: data1)
        try await keychainManager.storeSessionMetadata(identifier: id2.uuidString, data: data2)
        
        let identifiers = try await keychainManager.getAllSessionIdentifiers()
        XCTAssertTrue(identifiers.contains(id1.uuidString))
        XCTAssertTrue(identifiers.contains(id2.uuidString))
    }
    
    func testUpdateSessionMetadata() async throws {
        let createdAt = Timestamp.now
        
        let originalMetadata = [
            "id": testSessionId.uuidString,
            "pubkey": "pubkey",
            "signerType": "privatekey",
            "createdAt": createdAt
        ] as [String: Any]
        
        let originalData = try JSONSerialization.data(withJSONObject: originalMetadata)
        try await keychainManager.storeSessionMetadata(
            identifier: testSessionId.uuidString,
            data: originalData
        )
        
        let updatedMetadata = [
            "id": testSessionId.uuidString,
            "pubkey": "pubkey",
            "profileName": "Updated Name",
            "signerType": "privatekey",
            "createdAt": createdAt
        ] as [String: Any]
        
        let updatedData = try JSONSerialization.data(withJSONObject: updatedMetadata)
        try await keychainManager.storeSessionMetadata(
            identifier: testSessionId.uuidString,
            data: updatedData
        )
        
        let retrievedData = try await keychainManager.retrieveSessionMetadata(
            identifier: testSessionId.uuidString
        )
        let retrievedMetadata = try JSONSerialization.jsonObject(with: retrievedData) as! [String: Any]
        
        XCTAssertEqual(retrievedMetadata["profileName"] as? String, "Updated Name")
    }
    
    func testDeleteSessionMetadata() async throws {
        let id1 = UUID()
        
        let metadata1 = [
            "id": id1.uuidString,
            "pubkey": "pubkey1",
            "signerType": "privatekey",
            "createdAt": Timestamp.now
        ] as [String: Any]
        
        let metadata2 = [
            "id": testSessionId.uuidString,
            "pubkey": "pubkey2",
            "signerType": "privatekey",
            "createdAt": Timestamp.now
        ] as [String: Any]
        
        let data1 = try JSONSerialization.data(withJSONObject: metadata1)
        let data2 = try JSONSerialization.data(withJSONObject: metadata2)
        
        try await keychainManager.storeSessionMetadata(identifier: id1.uuidString, data: data1)
        try await keychainManager.storeSessionMetadata(identifier: testSessionId.uuidString, data: data2)
        
        try await keychainManager.deleteSessionMetadata(identifier: testSessionId.uuidString)
        
        let identifiers = try await keychainManager.getAllSessionIdentifiers()
        XCTAssertEqual(identifiers.count, 1)
        XCTAssertTrue(identifiers.contains(id1.uuidString))
        XCTAssertFalse(identifiers.contains(testSessionId.uuidString))
    }
    
    func testGetEmptySessionMetadata() async throws {
        let identifiers = try await keychainManager.getAllSessionIdentifiers()
        XCTAssertTrue(identifiers.isEmpty)
    }
    
    // MARK: - Biometric Availability Tests
    
    func testBiometricAvailability() async {
        // This test might return different results based on the device/simulator
        // We're just testing that the method doesn't crash
        _ = await keychainManager.isBiometricAuthenticationAvailable()
    }
    
    // MARK: - Accessibility Level Tests
    
    func testDifferentAccessibilityLevels() async throws {
        let testData = "test-data".data(using: .utf8)!
        let sessionId1 = UUID()
        let sessionId2 = UUID()
        let sessionId3 = UUID()
        
        // Test afterFirstUnlock
        try await keychainManager.storeSignerData(
            identifier: sessionId1.uuidString,
            data: testData,
            accessibility: .afterFirstUnlock
        )
        
        // Test whenUnlocked
        try await keychainManager.storeSignerData(
            identifier: sessionId2.uuidString,
            data: testData,
            accessibility: .whenUnlocked
        )
        
        // Test whenUnlockedThisDeviceOnly
        try await keychainManager.storeSignerData(
            identifier: sessionId3.uuidString,
            data: testData,
            accessibility: .whenUnlockedThisDeviceOnly
        )
        
        // Clean up
        try? await keychainManager.deleteSignerData(identifier: sessionId1.uuidString)
        try? await keychainManager.deleteSignerData(identifier: sessionId2.uuidString)
        try? await keychainManager.deleteSignerData(identifier: sessionId3.uuidString)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAccess() async throws {
        await withTaskGroup(of: Error?.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let sessionId = UUID()
                    let data = "data-\(i)".data(using: .utf8)!
                    
                    do {
                        try await self.keychainManager.storeSignerData(
                            identifier: sessionId.uuidString,
                            data: data
                        )
                        
                        let retrieved = try await self.keychainManager.retrieveSignerData(
                            identifier: sessionId.uuidString
                        )
                        XCTAssertEqual(retrieved, data)
                        
                        try await self.keychainManager.deleteSignerData(
                            identifier: sessionId.uuidString
                        )
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            
            var errors: [Error] = []
            for await error in group {
                if let error = error {
                    errors.append(error)
                }
            }
            
            XCTAssertTrue(errors.isEmpty, "Concurrent access errors: \(errors)")
        }
    }
}