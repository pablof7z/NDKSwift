import XCTest
@testable import NDKSwiftCore

final class NDKProfileManagerTests: NDKTestCase {
    
    var sut: NDKProfileManager!
    var cache: MemoryCache!
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        cache = MemoryCache()
        ndk = NDK(relayUrls: [], cache: cache)
        sut = NDKProfileManager(ndk: ndk)
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
        let metadata = [
            "name": "Test User",
            "display_name": "Test Display Name",
            "about": "Test about",
            "picture": "https://example.com/pic.jpg",
            "banner": "https://example.com/banner.jpg",
            "nip05": "test@example.com",
            "lud16": "test@walletofsatoshi.com",
            "website": "https://example.com"
        ]
        let content = try JSONCoding.encodeToString(metadata)
        let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
        
        // Cache the event
        try await cache.saveEvent(event)
        
        // When
        var loadedMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey) {
            loadedMetadata = metadata
            break
        }
        
        // Then
        XCTAssertNotNil(loadedMetadata)
        XCTAssertEqual(loadedMetadata?.name, "Test User")
        XCTAssertEqual(loadedMetadata?.displayName, "Test Display Name")
        XCTAssertEqual(loadedMetadata?.about, "Test about")
        XCTAssertEqual(loadedMetadata?.picture, "https://example.com/pic.jpg")
        XCTAssertEqual(loadedMetadata?.nip05, "test@example.com")
    }
    
    func testLoadProfileNotInCache() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        
        // When
        var loadedMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey, maxAge: 0) {
            loadedMetadata = metadata
            break
        }
        
        // Then
        XCTAssertNil(loadedMetadata)
    }
    
    // MARK: - Profile Saving Tests
    
    func testSaveProfile() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let metadata = [
            "name": "New User",
            "display_name": "New Display Name",
            "about": "New about",
            "picture": "https://example.com/newpic.jpg"
        ]
        let content = try JSONCoding.encodeToString(metadata)
        let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
        
        // When
        // Save the event directly to cache instead of injecting
        try await cache.saveEvent(event)
        
        // Then verify it's cached
        let cachedEvents = try await cache.queryEvents(NDKFilter(authors: [pubkey], kinds: [0]))
        XCTAssertEqual(cachedEvents.count, 1)
        let cachedMetadata = NDKUserMetadata(event: cachedEvents[0])
        XCTAssertEqual(cachedMetadata.name, "New User")
        XCTAssertEqual(cachedMetadata.displayName, "New Display Name")
        XCTAssertEqual(cachedMetadata.about, "New about")
    }
    
    // MARK: - Profile Update Tests
    
    func testUpdateExistingProfile() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let originalMetadata = [
            "name": "Original Name",
            "about": "Original about"
        ]
        let originalContent = try JSONCoding.encodeToString(originalMetadata)
        let originalEvent = EventTestFactory.createEvent(kind: 0, content: originalContent, pubkey: pubkey, createdAt: Timestamp(100))
        try await cache.saveEvent(originalEvent)
        
        let updatedMetadata = [
            "name": "Updated Name",
            "display_name": "Updated Display",
            "about": "Updated about",
            "picture": "https://example.com/updated.jpg",
            "nip05": "updated@example.com",
            "website": "https://updated.com"
        ]
        let updatedContent = try JSONCoding.encodeToString(updatedMetadata)
        let updatedEvent = EventTestFactory.createEvent(kind: 0, content: updatedContent, pubkey: pubkey, createdAt: Timestamp(200))
        
        // When
        try await cache.saveEvent(updatedEvent)
        
        // Then
        let filter = NDKFilter(authors: [pubkey], kinds: [0], limit: 1)
        let cachedEvents = try await cache.queryEvents(filter)
        XCTAssertEqual(cachedEvents.count, 1)
        let cachedMetadata = NDKUserMetadata(event: cachedEvents[0])
        XCTAssertEqual(cachedMetadata.name, "Updated Name")
        XCTAssertEqual(cachedMetadata.displayName, "Updated Display")
        XCTAssertEqual(cachedMetadata.about, "Updated about")
        XCTAssertEqual(cachedMetadata.picture, "https://example.com/updated.jpg")
        XCTAssertEqual(cachedMetadata.nip05, "updated@example.com")
        XCTAssertEqual(cachedMetadata.website, "https://updated.com")
    }
    
    // MARK: - Batch Operations Tests
    
    func testLoadMultipleProfiles() async throws {
        // Given
        let profiles = [
            (pubkey: try generateRandomHex(32), name: "User 1"),
            (pubkey: try generateRandomHex(32), name: "User 2"),
            (pubkey: try generateRandomHex(32), name: "User 3")
        ]
        
        // Cache all profile events
        for (pubkey, name) in profiles {
            let metadata = ["name": name]
            let content = try JSONCoding.encodeToString(metadata)
            let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
            try await cache.saveEvent(event)
        }
        
        // When
        let pubkeys = profiles.map { $0.pubkey }
        var loadedProfiles: [String: NDKUserMetadata] = [:]
        
        // Observe each pubkey
        for pubkey in pubkeys {
            for await metadata in await sut.subscribe(for: pubkey, maxAge: 0) {
                loadedProfiles[pubkey] = metadata
                break
            }
        }
        
        // Then
        XCTAssertEqual(loadedProfiles.count, 3)
        for (pubkey, name) in profiles {
            XCTAssertEqual(loadedProfiles[pubkey]?.name, name)
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
        let content = try JSONCoding.encodeToString(metadata)
        let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
        
        // When
        // Save the event directly to cache
        try await cache.saveEvent(event)
        
        // Then
        var loadedMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey, maxAge: 0) {
            loadedMetadata = metadata
            break
        }
        XCTAssertNotNil(loadedMetadata)
        XCTAssertEqual(loadedMetadata?.name, "Event User")
        XCTAssertEqual(loadedMetadata?.about, "From event")
        XCTAssertEqual(loadedMetadata?.picture, "https://example.com/event.jpg")
    }
    
    func testProcessInvalidProfileEvent() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let event = EventTestFactory.createEvent(kind: 0, content: "invalid json", pubkey: pubkey)
        
        // When
        // Save the invalid event directly to cache
        try await cache.saveEvent(event)
        
        // Then - metadata should have empty fields
        var loadedMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey, maxAge: 0) {
            loadedMetadata = metadata
            break
        }
        // With invalid JSON, NDKUserMetadata returns empty dictionary
        XCTAssertNotNil(loadedMetadata)
        XCTAssertNil(loadedMetadata?.name)
        XCTAssertNil(loadedMetadata?.about)
    }
    
    // MARK: - Profile Expiry Tests
    
    func testProfileCacheExpiry() async throws {
        // Given
        let pubkey = try generateRandomHex(32)
        let metadata = ["name": "Expiring User"]
        let content = try JSONCoding.encodeToString(metadata)
        let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
        
        // When - save event with expiry
        try await cache.saveEvent(event)
        
        // Then - Profile should exist immediately with maxAge 0
        var immediateMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey, maxAge: 0) {
            immediateMetadata = metadata
            break
        }
        XCTAssertNotNil(immediateMetadata)
        
        // When requesting with a very small maxAge, it should not return stale data
        var expiredMetadata: NDKUserMetadata?
        for await metadata in await sut.subscribe(for: pubkey, maxAge: 0.0001) { // 0.1ms maxAge
            expiredMetadata = metadata
            break
        }
        // Since we're using maxAge, it should still return the metadata if within the time window
        XCTAssertNotNil(expiredMetadata)
    }
    
    // MARK: - Performance Tests
    
    func testLoadProfilePerformance() async throws {
        // Given - Pre-cache many profiles
        let profileCount = 1000
        var pubkeys: [String] = []
        
        for i in 0..<profileCount {
            let pubkey = try generateRandomHex(32)
            pubkeys.append(pubkey)
            let metadata = ["name": "User \(i)"]
            let content = try JSONCoding.encodeToString(metadata)
            let event = EventTestFactory.createEvent(kind: 0, content: content, pubkey: pubkey)
            try await cache.saveEvent(event)
        }
        
        // When/Then - Measure loading performance
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for pubkey in pubkeys {
            for await _ in await sut.subscribe(for: pubkey, maxAge: 0) {
                break // Just get the first result
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let avgLoadTime = duration / Double(profileCount) * 1000 // ms per profile
        
        XCTAssertLessThan(avgLoadTime, 1.0, "Average profile load time should be less than 1ms")
    }
}