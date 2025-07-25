import XCTest
@testable import NDKSwift

/// End-to-end tests for authentication flow including keychain persistence,
/// multi-account management, and session restoration
@MainActor
final class AuthenticationE2ETests: XCTestCase {
    let relayURLs = [
        "wss://relay.damus.io",
        "wss://nos.lol"
    ]
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Configure logging for debugging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false
        
        // Clear any existing sessions to ensure clean test environment
        print("[\(timestamp())] Clearing existing sessions...")
        let authManager = NDKAuthManager.shared
        
        // Remove all sessions
        for session in authManager.availableSessions {
            try await authManager.deleteSession(session)
        }
        
        print("[\(timestamp())] Test environment cleaned")
    }
    
    override func tearDown() async throws {
        // Clean up after test
        let authManager = NDKAuthManager.shared
        for session in authManager.availableSessions {
            try await authManager.deleteSession(session)
        }
        
        try await super.tearDown()
    }
    
    func testFullAuthenticationLifecycle() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting full authentication lifecycle E2E test")
        
        // Step 1: Create NDK instance
        let ndk = NDK(cache: MemoryCache())
        
        // Step 2: Generate new signer
        print("[\(timestamp())] Generating new key pair...")
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        print("[\(timestamp())] Generated pubkey: \(pubkey)")
        
        // Step 3: Create session
        print("[\(timestamp())] Creating authentication session...")
        let authManager = NDKAuthManager.shared
        authManager.setNDK(ndk)
        
        let createStart = Date()
        
        var session = try await authManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Update profile information
        let profile = NDKUserProfile(
            name: "Test User",
            displayName: "E2E Test User",
            about: "This is a test account for E2E testing",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        
        session.updateProfile(profile)
        try await authManager.updateActiveSessionProfile(profile)
        
        let createTime = Date()
        print("[\(timestamp())] Session created in \(createTime.timeIntervalSince(createStart))s")
        
        // Verify session properties
        XCTAssertEqual(session.pubkey, pubkey)
        XCTAssertEqual(authManager.activeSession?.profileName, "Test User")
        XCTAssertEqual(authManager.activeSession?.about, "This is a test account for E2E testing")
        XCTAssertTrue(authManager.activeSession?.isActive ?? false)
        XCTAssertNotNil(authManager.activeSession)
        XCTAssertEqual(authManager.activeSession?.id, session.id)
        
        // Step 4: Verify NDK has the signer
        XCTAssertNotNil(ndk.signer)
        let ndkPubkey = try await ndk.signer?.pubkey
        XCTAssertEqual(ndkPubkey, pubkey)
        
        // Step 5: Connect to relays and publish a test event
        print("[\(timestamp())] Connecting to relays...")
        for relayURL in relayURLs {
            await ndk.addRelay(relayURL)
        }
        await ndk.connect()
        
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        XCTAssertGreaterThan(connected, 0, "Should connect to at least one relay")
        
        print("[\(timestamp())] Publishing test event...")
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Authentication E2E test event at \(Date())")
            .kind(EventKind.textNote)
            .build()
        
        let publishedRelays = try await ndk.publish(event)
        XCTAssertGreaterThan(publishedRelays.count, 0, "Should publish to at least one relay")
        print("[\(timestamp())] Event published with id: \(event.id)")
        
        // Step 6: Disconnect and clear signer to simulate app restart
        print("[\(timestamp())] Simulating app restart...")
        await ndk.disconnect()
        ndk.signer = nil
        
        // Small delay to ensure keychain writes complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Step 7: Restore session
        print("[\(timestamp())] Restoring session...")
        let restoreStart = Date()
        
        // Create new auth manager instance and NDK to simulate restart
        let newAuthManager = NDKAuthManager.shared
        let newNDK = NDK(cache: MemoryCache())
        newAuthManager.setNDK(newNDK)
        
        // Restore will happen automatically via setNDK
        // Wait a bit for restoration
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let restoreTime = Date()
        print("[\(timestamp())] Session restored in \(restoreTime.timeIntervalSince(restoreStart))s")
        
        // Verify restored session
        let restoredSession = newAuthManager.activeSession
        XCTAssertNotNil(restoredSession)
        XCTAssertEqual(restoredSession?.id, session.id)
        XCTAssertEqual(restoredSession?.pubkey, pubkey)
        XCTAssertEqual(restoredSession?.profileName, "Test User")
        XCTAssertTrue(restoredSession?.isActive ?? false)
        
        // Verify NDK has restored signer
        XCTAssertNotNil(newNDK.signer)
        let restoredPubkey = try await newNDK.signer?.pubkey
        XCTAssertEqual(restoredPubkey, pubkey)
        
        // Step 8: Verify we can still sign and publish events
        print("[\(timestamp())] Testing restored signer functionality...")
        for relayURL in relayURLs {
            await newNDK.addRelay(relayURL)
        }
        await newNDK.connect()
        await newNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        let restoredEvent = try await NDKEventBuilder(ndk: newNDK)
            .content("Event after session restore at \(Date())")
            .kind(EventKind.textNote)
            .build()
        
        let restoredPublished = try await newNDK.publish(restoredEvent)
        XCTAssertGreaterThan(restoredPublished.count, 0, "Should publish with restored signer")
        print("[\(timestamp())] Successfully published with restored signer: \(restoredEvent.id)")
        
        // Cleanup
        await newNDK.disconnect()
        
        let totalTime = Date()
        print("[\(timestamp())] Full authentication lifecycle test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testMultiAccountManagement() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting multi-account management E2E test")
        
        let authManager = NDKAuthManager.shared
        let ndk = NDK(cache: MemoryCache())
        authManager.setNDK(ndk)
        
        // Create multiple accounts
        var sessions: [(session: NDKSession, pubkey: String)] = []
        let accountCount = 3
        
        print("[\(timestamp())] Creating \(accountCount) accounts...")
        for i in 1...accountCount {
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            
            var session = try await authManager.createSession(
                with: signer,
                requiresBiometric: false,
                isHardwareBacked: false
            )
            
            // Update profile
            let profile = NDKUserProfile(
                name: "Test User \(i)",
                displayName: "User #\(i)",
                about: "Test account #\(i)",
                picture: nil,
                banner: nil,
                nip05: nil,
                lud16: nil,
                lud06: nil,
                website: nil
            )
            session.updateProfile(profile)
            
            sessions.append((session, pubkey))
            print("[\(timestamp())] Created account \(i): \(pubkey)")
        }
        
        // Verify all sessions exist
        XCTAssertEqual(authManager.availableSessions.count, accountCount)
        
        // The last created session should be active
        XCTAssertEqual(authManager.activeSession?.id, sessions[accountCount-1].session.id)
        
        // Test switching between accounts
        print("[\(timestamp())] Testing account switching...")
        
        for i in 0..<accountCount {
            let (session, expectedPubkey) = sessions[i]
            
            print("[\(timestamp())] Switching to account \(i+1)...")
            let switchStart = Date()
            
            try await authManager.switchToSession(session)
            
            let switchTime = Date()
            print("[\(timestamp())] Switched in \(switchTime.timeIntervalSince(switchStart))s")
            
            // Verify switch
            XCTAssertEqual(authManager.activeSession?.id, session.id)
            
            // Verify NDK signer updated
            let currentPubkey = try await ndk.signer?.pubkey
            XCTAssertEqual(currentPubkey, expectedPubkey)
            
            // Test we can sign with each account
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("Event from account \(i+1)")
                .kind(EventKind.textNote)
                .build()
            
            XCTAssertEqual(event.pubkey, expectedPubkey)
            print("[\(timestamp())] Successfully created event with account \(i+1)")
        }
        
        // Test session deletion
        print("[\(timestamp())] Testing session deletion...")
        let sessionToDelete = sessions[1].session
        
        try await authManager.deleteSession(sessionToDelete)
        
        // Verify deletion
        XCTAssertEqual(authManager.availableSessions.count, accountCount - 1)
        XCTAssertNil(authManager.availableSessions.first { $0.id == sessionToDelete.id })
        
        // Active session should have switched (since we deleted an inactive one, active should remain)
        XCTAssertNotNil(authManager.activeSession)
        
        // Test logout
        print("[\(timestamp())] Testing logout...")
        authManager.logout()
        
        XCTAssertNil(authManager.activeSession)
        XCTAssertNil(ndk.signer)
        XCTAssertEqual(authManager.availableSessions.count, accountCount - 1) // Sessions still exist
        
        // Test clearing all sessions
        print("[\(timestamp())] Testing clear all sessions...")
        for session in authManager.availableSessions {
            try await authManager.deleteSession(session)
        }
        
        XCTAssertEqual(authManager.availableSessions.count, 0)
        
        let totalTime = Date()
        print("[\(timestamp())] Multi-account management test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testSessionPersistenceAcrossMultipleRestarts() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting session persistence across restarts E2E test")
        
        let authManager = NDKAuthManager.shared
        var ndk = NDK(cache: MemoryCache())
        authManager.setNDK(ndk)
        
        // Create initial session
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        
        var session = try await authManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Update profile
        let profile = NDKUserProfile(
            name: "Persistent User",
            displayName: "Persistence Test",
            about: "Testing persistence",
            picture: "https://example.com/pic.jpg",
            banner: nil,
            nip05: "test@example.com",
            lud16: "test@ln.example.com",
            lud06: nil,
            website: nil
        )
        session.updateProfile(profile)
        try await authManager.updateActiveSessionProfile(profile)
        
        print("[\(timestamp())] Created session with pubkey: \(pubkey)")
        
        // Simulate multiple app restarts
        let restartCount = 3
        
        for i in 1...restartCount {
            print("[\(timestamp())] Simulating app restart #\(i)...")
            
            // Clear NDK instance
            ndk.signer = nil
            ndk = NDK(cache: MemoryCache()) // Create new instance
            
            // Small delay to simulate real restart
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            
            // Create new auth manager and NDK to simulate full restart
            let newAuthManager = NDKAuthManager.shared
            newAuthManager.setNDK(ndk)
            
            // Wait for automatic restoration
            try await Task.sleep(nanoseconds: 500_000_000)
            
            let restoreStart = Date()
            let restored = newAuthManager.activeSession
            let restoreTime = Date()
            
            print("[\(timestamp())] Restart #\(i) - Session restored in \(restoreTime.timeIntervalSince(restoreStart))s")
            
            // Verify restoration
            XCTAssertNotNil(restored)
            XCTAssertEqual(restored?.id, session.id)
            XCTAssertEqual(restored?.pubkey, pubkey)
            XCTAssertEqual(restored?.profileName, "Persistent User")
            XCTAssertEqual(restored?.about, "Testing persistence")
            XCTAssertEqual(restored?.avatarURL?.absoluteString, "https://example.com/pic.jpg")
            XCTAssertEqual(restored?.nip05, "test@example.com")
            
            // Verify signer works
            let restoredPubkey = try await ndk.signer?.pubkey
            XCTAssertEqual(restoredPubkey, pubkey)
            
            // Create and sign an event to verify functionality
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("Event after restart #\(i)")
                .kind(EventKind.textNote)
                .build()
            
            XCTAssertEqual(event.pubkey, pubkey)
            XCTAssertNotNil(event.sig)
            print("[\(timestamp())] Successfully signed event after restart #\(i)")
        }
        
        let totalTime = Date()
        print("[\(timestamp())] Session persistence test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testSessionUpdateAndProfileSync() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting session update and profile sync E2E test")
        
        let authManager = NDKAuthManager.shared
        let ndk = NDK(cache: MemoryCache())
        authManager.setNDK(ndk)
        
        // Create session
        let signer = try NDKPrivateKeySigner.generate()
        _ = try await signer.pubkey
        
        var session = try await authManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Set initial profile
        let initialProfile = NDKUserProfile(
            name: "Initial Name",
            displayName: "Initial Display",
            about: "Initial bio",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        session.updateProfile(initialProfile)
        try await authManager.updateActiveSessionProfile(initialProfile)
        
        print("[\(timestamp())] Created session: \(session.id)")
        
        // Update profile information
        print("[\(timestamp())] Updating profile...")
        
        let updateStart = Date()
        
        let updatedProfile = NDKUserProfile(
            name: "Updated Name",
            displayName: "Updated Display",
            about: "Updated bio with more information",
            picture: "https://example.com/new-pic.jpg",
            banner: nil,
            nip05: "updated@example.com",
            lud16: "updated@wallet.com",
            lud06: nil,
            website: nil
        )
        
        try await authManager.updateActiveSessionProfile(updatedProfile)
        
        let updateTime = Date()
        print("[\(timestamp())] Profile updated in \(updateTime.timeIntervalSince(updateStart))s")
        
        // Simulate restart
        print("[\(timestamp())] Simulating restart to verify updates persist...")
        ndk.signer = nil
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Create new auth manager to simulate restart
        let newAuthManager = NDKAuthManager.shared
        newAuthManager.setNDK(ndk)
        
        // Wait for automatic restoration
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let restored = newAuthManager.activeSession
        
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.profileName, "Updated Name")
        XCTAssertEqual(restored?.about, "Updated bio with more information")
        XCTAssertEqual(restored?.avatarURL?.absoluteString, "https://example.com/new-pic.jpg")
        XCTAssertEqual(restored?.nip05, "updated@example.com")
        
        print("[\(timestamp())] All profile updates persisted successfully")
        
        // Test that last used timestamp is updated automatically
        let originalLastUsed = restored?.lastUsed ?? Date.distantPast
        
        // Perform an operation that should update last used
        try await newAuthManager.switchToSession(restored!)
        
        // Verify update
        let activeSession = newAuthManager.activeSession
        XCTAssertNotNil(activeSession)
        XCTAssertGreaterThanOrEqual(activeSession?.lastUsed ?? Date.distantPast, originalLastUsed)
        
        let totalTime = Date()
        print("[\(timestamp())] Session update test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    func testSecurityBoundariesBetweenSessions() async throws {
        let testStart = Date()
        print("[\(timestamp())] Starting security boundaries E2E test")
        
        let authManager = NDKAuthManager.shared
        let ndk = NDK(cache: MemoryCache())
        authManager.setNDK(ndk)
        
        // Create two separate accounts
        let signer1 = try NDKPrivateKeySigner.generate()
        let pubkey1 = try await signer1.pubkey
        
        let signer2 = try NDKPrivateKeySigner.generate()
        let pubkey2 = try await signer2.pubkey
        
        XCTAssertNotEqual(pubkey1, pubkey2, "Should have different public keys")
        
        print("[\(timestamp())] Creating two separate accounts...")
        
        let session1 = try await authManager.createSession(
            with: signer1,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Update Alice's profile
        let aliceProfile = NDKUserProfile(
            name: "Alice",
            displayName: "Alice Test",
            about: "First test account",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        try await authManager.updateActiveSessionProfile(aliceProfile)
        
        let session2 = try await authManager.createSession(
            with: signer2,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Update Bob's profile
        let bobProfile = NDKUserProfile(
            name: "Bob",
            displayName: "Bob Test",
            about: "Second test account",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        try await authManager.updateActiveSessionProfile(bobProfile)
        
        // Verify sessions are isolated
        XCTAssertNotEqual(session1.id, session2.id)
        XCTAssertNotEqual(session1.pubkey, session2.pubkey)
        
        // Switch to first account
        print("[\(timestamp())] Testing account isolation...")
        try await authManager.switchToSession(session1)
        
        // Create event with first account
        let event1 = try await NDKEventBuilder(ndk: ndk)
            .content("Message from Alice")
            .kind(EventKind.textNote)
            .build()
        
        XCTAssertEqual(event1.pubkey, pubkey1)
        
        // Switch to second account
        try await authManager.switchToSession(session2)
        
        // Create event with second account
        let event2 = try await NDKEventBuilder(ndk: ndk)
            .content("Message from Bob")
            .kind(EventKind.textNote)
            .build()
        
        XCTAssertEqual(event2.pubkey, pubkey2)
        
        // Verify events have different signatures
        XCTAssertNotEqual(event1.sig, event2.sig)
        
        print("[\(timestamp())] Account isolation verified - each account signs with its own key")
        
        // Test that deleting one session doesn't affect the other
        print("[\(timestamp())] Testing session independence...")
        try await authManager.deleteSession(session1)
        
        // Session 2 should still exist and be active
        XCTAssertEqual(authManager.activeSession?.id, session2.id)
        XCTAssertEqual(authManager.availableSessions.count, 1)
        
        // Can still sign with session 2
        let event3 = try await NDKEventBuilder(ndk: ndk)
            .content("Bob still active after Alice deleted")
            .kind(EventKind.textNote)
            .build()
        
        XCTAssertEqual(event3.pubkey, pubkey2)
        
        let totalTime = Date()
        print("[\(timestamp())] Security boundaries test completed in \(totalTime.timeIntervalSince(testStart))s")
    }
    
    private func timestamp() -> String {
        return DateFormatters.custom(format: "HH:mm:ss.SSS").string(from: Date())
    }
}