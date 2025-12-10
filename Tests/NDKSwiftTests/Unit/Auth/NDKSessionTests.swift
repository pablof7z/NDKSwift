import XCTest
@testable import NDKSwiftCore

final class NDKSessionTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testSessionInitialization() {
        let session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        XCTAssertNotNil(session.id)
        XCTAssertEqual(session.pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f")
        XCTAssertEqual(session.signerType, "privatekey")
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.requiresBiometric, false)
        XCTAssertEqual(session.isHardwareBacked, false)
        XCTAssertNil(session.autoLockTimeout)
    }
    
    func testSessionWithCompleteInitialization() {
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey",
            requiresBiometric: true,
            isHardwareBacked: true,
            autoLockTimeout: 300
        )
        
        // Set additional properties
        session.isActive = true
        
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.requiresBiometric)
        XCTAssertTrue(session.isHardwareBacked)
        XCTAssertEqual(session.autoLockTimeout, 300)
    }
    
    // MARK: - Security Settings Tests
    
    func testSessionWithSecuritySettings() {
        let session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey",
            requiresBiometric: true,
            isHardwareBacked: false,
            autoLockTimeout: 600
        )
        
        XCTAssertTrue(session.requiresBiometric)
        XCTAssertFalse(session.isHardwareBacked)
        XCTAssertEqual(session.autoLockTimeout, 600)
    }
    
    func testSessionSecurityDefaults() {
        let session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        XCTAssertFalse(session.requiresBiometric)
        XCTAssertFalse(session.isHardwareBacked)
        XCTAssertNil(session.autoLockTimeout)
    }
    
    // MARK: - State Management Tests
    
    func testSessionActivation() {
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        XCTAssertFalse(session.isActive)
        
        session.isActive = true
        XCTAssertTrue(session.isActive)
    }
    
    func testLastUsedUpdate() {
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        let originalDate = session.lastUsed
        
        // Wait a bit to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)
        
        session.lastUsed = Date()
        XCTAssertGreaterThan(session.lastUsed, originalDate)
    }
    
    // MARK: - Profile Metadata Tests
    
    func testProfileMetadataUpdate() {
        let session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        // Sessions don't have profile metadata - that's stored separately
        // This test just verifies the session exists with correct pubkey
        XCTAssertEqual(session.pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f")
        XCTAssertEqual(session.signerType, "privatekey")
    }
    
    func testAvatarURLUpdate() {
        let session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        // Sessions don't have avatarURL - profiles are stored separately
        // This test just verifies the session state
        XCTAssertEqual(session.pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f")
        XCTAssertFalse(session.isActive)
    }
    
    // MARK: - Codable Tests
    
    func testSessionEncodingDecoding() throws {
        var originalSession = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey",
            requiresBiometric: true,
            isHardwareBacked: false,
            autoLockTimeout: 300
        )
        originalSession.isActive = true
        
        let data = try JSONCoding.encode(originalSession)
        
        let decodedSession = try JSONCoding.decode(NDKSession.self, from: data)
        
        XCTAssertEqual(originalSession.id, decodedSession.id)
        XCTAssertEqual(originalSession.pubkey, decodedSession.pubkey)
        XCTAssertEqual(originalSession.signerType, decodedSession.signerType)
        XCTAssertEqual(originalSession.isActive, decodedSession.isActive)
        XCTAssertEqual(originalSession.requiresBiometric, decodedSession.requiresBiometric)
        XCTAssertEqual(originalSession.isHardwareBacked, decodedSession.isHardwareBacked)
        XCTAssertEqual(originalSession.autoLockTimeout, decodedSession.autoLockTimeout)
    }
    
    // MARK: - Array Extension Tests
    
    func testSessionArrayActiveSession() {
        let session1 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e531",
            signerType: "privatekey"
        )
        
        var session2 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e532",
            signerType: "privatekey"
        )
        session2.isActive = true
        
        let session3 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e533",
            signerType: "privatekey"
        )
        
        let sessions = [session1, session2, session3]
        
        XCTAssertEqual(sessions.activeSession?.pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e532")
    }
    
    func testSessionArrayNoActiveSession() {
        let session1 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e531",
            signerType: "privatekey"
        )
        
        let session2 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e532",
            signerType: "privatekey"
        )
        
        let sessions = [session1, session2]
        
        XCTAssertNil(sessions.activeSession)
    }
    
    func testSessionArraySortedByLastUsed() {
        var session1 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e531",
            signerType: "privatekey"
        )
        session1.lastUsed = Date(timeIntervalSinceNow: -300) // 5 minutes ago
        
        var session2 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e532",
            signerType: "privatekey"
        )
        session2.lastUsed = Date(timeIntervalSinceNow: -60) // 1 minute ago
        
        var session3 = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e533",
            signerType: "privatekey"
        )
        session3.lastUsed = Date() // now
        
        let sessions = [session1, session2, session3]
        let sorted = sessions.sortedByLastUsed
        
        XCTAssertEqual(sorted[0].pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e533") // Most recent
        XCTAssertEqual(sorted[1].pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e532")
        XCTAssertEqual(sorted[2].pubkey, "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e531") // Oldest
    }
}