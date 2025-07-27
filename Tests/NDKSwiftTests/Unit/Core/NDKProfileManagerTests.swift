import XCTest
@testable import NDKSwift

final class NDKProfileManagerTests: NDKTestCase {
    
    var sut: NDKProfileManager!
    var cache: MemoryCache!
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        cache = MemoryCache()
        ndk = NDK(relayUrls: [], cache: cache)
        sut = NDKProfileManager(ndk: ndk, cache: cache)
    }
    
    override func tearDown() async throws {
        sut = nil
        cache = nil
        ndk = nil
        try await super.tearDown()
    }
    
    // MARK: - Profile Loading Tests
    
    func testLoadProfileFromCache() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let profile = NDKUserProfile(
            name: "Test User",
            displayName: "Test Display Name",
            about: "Test about",
            picture: "https://example.com/pic.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "test@example.com",
            lud16: "test@walletofsatoshi.com",
            lud06: nil,
            website: "https://example.com"
        )
        
        // Cache the profile
        await cache.saveProfile(profile, for: pubkey)
        
        // When
        let loadedProfile = await sut.loadProfile(for: pubkey)
        
        // Then
        XCTAssertNotNil(loadedProfile)
        XCTAssertEqual(loadedProfile?.name, profile.name)
        XCTAssertEqual(loadedProfile?.displayName, profile.displayName)
        XCTAssertEqual(loadedProfile?.about, profile.about)
        XCTAssertEqual(loadedProfile?.picture, profile.picture)
        XCTAssertEqual(loadedProfile?.nip05, profile.nip05)
    }
    
    func testLoadProfileNotInCache() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        
        // When
        let loadedProfile = await sut.loadProfile(for: pubkey)
        
        // Then
        XCTAssertNil(loadedProfile)
    }
    
    // MARK: - Profile Saving Tests
    
    func testSaveProfile() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let profile = NDKUserProfile(
            name: "New User",
            displayName: "New Display Name",
            about: "New about",
            picture: "https://example.com/newpic.jpg",
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        
        // When
        await sut.saveProfile(profile, for: pubkey)
        
        // Then
        let cachedProfile = await cache.getProfile(for: pubkey)
        XCTAssertNotNil(cachedProfile)
        XCTAssertEqual(cachedProfile?.name, profile.name)
        XCTAssertEqual(cachedProfile?.displayName, profile.displayName)
        XCTAssertEqual(cachedProfile?.about, profile.about)
    }
    
    // MARK: - Profile Update Tests
    
    func testUpdateExistingProfile() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let originalProfile = NDKUserProfile(
            name: "Original Name",
            displayName: nil,
            about: "Original about",
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        await cache.saveProfile(originalProfile, for: pubkey)
        
        let updatedProfile = NDKUserProfile(
            name: "Updated Name",
            displayName: "Updated Display",
            about: "Updated about",
            picture: "https://example.com/updated.jpg",
            banner: nil,
            nip05: "updated@example.com",
            lud16: nil,
            lud06: nil,
            website: "https://updated.com"
        )
        
        // When
        await sut.saveProfile(updatedProfile, for: pubkey)
        
        // Then
        let cachedProfile = await cache.getProfile(for: pubkey)
        XCTAssertEqual(cachedProfile?.name, updatedProfile.name)
        XCTAssertEqual(cachedProfile?.displayName, updatedProfile.displayName)
        XCTAssertEqual(cachedProfile?.about, updatedProfile.about)
        XCTAssertEqual(cachedProfile?.picture, updatedProfile.picture)
        XCTAssertEqual(cachedProfile?.nip05, updatedProfile.nip05)
        XCTAssertEqual(cachedProfile?.website, updatedProfile.website)
    }
    
    // MARK: - Batch Operations Tests
    
    func testLoadMultipleProfiles() async throws {
        // Given
        let profiles = [
            (pubkey: try generateRandomHex(32), profile: NDKUserProfile(name: "User 1", displayName: nil, about: nil, picture: nil, banner: nil, nip05: nil, lud16: nil, lud06: nil, website: nil)),
            (pubkey: try generateRandomHex(32), profile: NDKUserProfile(name: "User 2", displayName: nil, about: nil, picture: nil, banner: nil, nip05: nil, lud16: nil, lud06: nil, website: nil)),
            (pubkey: try generateRandomHex(32), profile: NDKUserProfile(name: "User 3", displayName: nil, about: nil, picture: nil, banner: nil, nip05: nil, lud16: nil, lud06: nil, website: nil))
        ]
        
        // Cache all profiles
        for (pubkey, profile) in profiles {
            await cache.saveProfile(profile, for: pubkey)
        }
        
        // When
        let pubkeys = profiles.map { $0.pubkey }
        let loadedProfiles = await sut.loadProfiles(for: pubkeys)
        
        // Then
        XCTAssertEqual(loadedProfiles.count, 3)
        for (pubkey, profile) in profiles {
            XCTAssertEqual(loadedProfiles[pubkey]?.name, profile.name)
        }
    }
    
    // MARK: - Profile Event Processing Tests
    
    func testProcessProfileEvent() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let metadata = [
            "name": "Event User",
            "about": "From event",
            "picture": "https://example.com/event.jpg"
        ]
        let content = String(data: try JSONEncoder().encode(metadata), encoding: .utf8)!
        let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
        
        // When
        await sut.processProfileEvent(event)
        
        // Then
        let cachedProfile = await cache.getProfile(for: pubkey)
        XCTAssertNotNil(cachedProfile)
        XCTAssertEqual(cachedProfile?.name, "Event User")
        XCTAssertEqual(cachedProfile?.about, "From event")
        XCTAssertEqual(cachedProfile?.picture, "https://example.com/event.jpg")
    }
    
    func testProcessInvalidProfileEvent() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let event = EventTestFactory.createEvent(kind: 0, content: "invalid json", pubkey: pubkey)
        
        // When
        await sut.processProfileEvent(event)
        
        // Then
        let cachedProfile = await cache.getProfile(for: pubkey)
        XCTAssertNil(cachedProfile)
    }
    
    // MARK: - Profile Expiry Tests
    
    func testProfileCacheExpiry() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let profile = NDKUserProfile(
            name: "Expiring User",
            displayName: nil,
            about: nil,
            picture: nil,
            banner: nil,
            nip05: nil,
            lud16: nil,
            lud06: nil,
            website: nil
        )
        
        // When
        await sut.saveProfile(profile, for: pubkey, expiresIn: 0.1) // 100ms expiry
        
        // Then - Profile should exist immediately
        let immediateProfile = await sut.loadProfile(for: pubkey)
        XCTAssertNotNil(immediateProfile)
        
        // Wait for expiry
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Profile should be expired
        let expiredProfile = await sut.loadProfile(for: pubkey)
        XCTAssertNil(expiredProfile)
    }
    
    // MARK: - Performance Tests
    
    func testLoadProfilePerformance() async throws {
        // Given - Pre-cache many profiles
        let profileCount = 1000
        var pubkeys: [String] = []
        
        for i in 0..<profileCount {
            let pubkey = try generateRandomHex(32)
            pubkeys.append(pubkey)
            let profile = NDKUserProfile(
                name: "User \(i)",
                displayName: nil,
                about: nil,
                picture: nil,
                banner: nil,
                nip05: nil,
                lud16: nil,
                lud06: nil,
                website: nil
            )
            await cache.saveProfile(profile, for: pubkey)
        }
        
        // When/Then - Measure loading performance
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for pubkey in pubkeys {
            _ = await sut.loadProfile(for: pubkey)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let avgLoadTime = duration / Double(profileCount) * 1000 // ms per profile
        
        XCTAssertLessThan(avgLoadTime, 1.0, "Average profile load time should be less than 1ms")
    }
}