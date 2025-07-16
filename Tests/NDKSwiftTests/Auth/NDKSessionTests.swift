import XCTest
@testable import NDKSwift

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
        XCTAssertNil(session.avatarURL)
        XCTAssertEqual(session.requiresBiometric, false)
        XCTAssertEqual(session.isHardwareBacked, false)
        XCTAssertNil(session.autoLockTimeout)
    }
    
    func testSessionWithCompleteInitialization() {
        let avatarURL = URL(string: "https://example.com/avatar.jpg")!
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey",
            requiresBiometric: true,
            isHardwareBacked: true,
            autoLockTimeout: 300
        )
        
        // Set additional properties
        session.isActive = true
        session.avatarURL = avatarURL
        session.about = "Test user profile"
        session.profileName = "Complete User"
        
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.avatarURL, avatarURL)
        XCTAssertEqual(session.profileName, "Complete User")
        XCTAssertTrue(session.requiresBiometric)
        XCTAssertTrue(session.isHardwareBacked)
        XCTAssertEqual(session.autoLockTimeout, 300)
        XCTAssertEqual(session.about, "Test user profile")
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
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        XCTAssertNil(session.profileName)
        XCTAssertNil(session.about)
        
        session.profileName = "Updated Name"
        session.about = "Updated bio"
        session.avatarURL = URL(string: "https://example.com/pic.jpg")
        
        XCTAssertEqual(session.profileName, "Updated Name")
        XCTAssertEqual(session.about, "Updated bio")
        XCTAssertEqual(session.avatarURL?.absoluteString, "https://example.com/pic.jpg")
    }
    
    func testAvatarURLUpdate() {
        var session = NDKSession(
            pubkey: "d30effaa4e7090322e07b7b95b2c2f42c23bb16b12582d358fb088993a26e53f",
            signerType: "privatekey"
        )
        
        XCTAssertNil(session.avatarURL)
        
        let newURL = URL(string: "https://example.com/avatar.jpg")!
        session.avatarURL = newURL
        
        XCTAssertEqual(session.avatarURL, newURL)
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
        originalSession.avatarURL = URL(string: "https://example.com/avatar.jpg")
        originalSession.profileName = "Test User"
        originalSession.about = "Bio"
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSession)
        
        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(NDKSession.self, from: data)
        
        XCTAssertEqual(originalSession.id, decodedSession.id)
        XCTAssertEqual(originalSession.pubkey, decodedSession.pubkey)
        XCTAssertEqual(originalSession.signerType, decodedSession.signerType)
        XCTAssertEqual(originalSession.isActive, decodedSession.isActive)
        XCTAssertEqual(originalSession.avatarURL, decodedSession.avatarURL)
        XCTAssertEqual(originalSession.profileName, decodedSession.profileName)
        XCTAssertEqual(originalSession.requiresBiometric, decodedSession.requiresBiometric)
        XCTAssertEqual(originalSession.about, decodedSession.about)
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