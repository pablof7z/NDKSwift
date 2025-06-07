import XCTest
@testable import NDKSwift

final class NDKProfileManagerTests: XCTestCase {
    var ndk: NDK!
    var profileManager: NDKProfileManager!
    var mockCache: MockCache!
    
    override func setUp() async throws {
        // Create NDK with mock cache
        mockCache = MockCache()
        ndk = NDK(cacheAdapter: mockCache)
        profileManager = ndk.profileManager
    }
    
    override func tearDown() async throws {
        ndk = nil
        profileManager = nil
        mockCache = nil
    }
    
    func testFetchProfileWithCache() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let profile = NDKUserProfile(
            name: "Test User",
            displayName: "Test Display",
            about: "Test bio",
            picture: "https://example.com/pic.jpg"
        )
        
        // Pre-populate cache
        await mockCache.saveProfile(profile, for: pubkey)
        
        // Test - should return from cache
        let fetchedProfile = try await profileManager.fetchProfile(for: pubkey)
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, "Test User")
        XCTAssertEqual(fetchedProfile?.displayName, "Test Display")
    }
    
    func testFetchProfileForceRefresh() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let cachedProfile = NDKUserProfile(name: "Cached User")
        let freshProfile = NDKUserProfile(name: "Fresh User")
        
        // Pre-populate cache
        await mockCache.saveProfile(cachedProfile, for: pubkey)
        
        // Mock relay response
        let event = NDKEvent(kind: EventKind.metadata)
        event.pubkey = pubkey
        event.content = try JSONEncoder().encode(freshProfile).string
        mockCache.mockEvents = [event]
        
        // Test - force refresh should bypass cache
        let fetchedProfile = try await profileManager.fetchProfile(for: pubkey, forceRefresh: true)
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, "Fresh User")
    }
    
    func testFetchMultipleProfiles() async throws {
        // Setup
        let profiles = [
            ("pubkey1", NDKUserProfile(name: "User 1")),
            ("pubkey2", NDKUserProfile(name: "User 2")),
            ("pubkey3", NDKUserProfile(name: "User 3"))
        ]
        
        // Pre-populate some in cache
        await mockCache.saveProfile(profiles[0].1, for: profiles[0].0)
        
        // Mock relay responses for others
        var events: [NDKEvent] = []
        for (pubkey, profile) in profiles.dropFirst() {
            let event = NDKEvent(kind: EventKind.metadata)
            event.pubkey = pubkey
            event.content = try JSONEncoder().encode(profile).string
            events.append(event)
        }
        mockCache.mockEvents = events
        
        // Test
        let pubkeys = profiles.map { $0.0 }
        let fetchedProfiles = try await profileManager.fetchProfiles(for: pubkeys)
        
        XCTAssertEqual(fetchedProfiles.count, 3)
        XCTAssertEqual(fetchedProfiles["pubkey1"]?.name, "User 1")
        XCTAssertEqual(fetchedProfiles["pubkey2"]?.name, "User 2")
        XCTAssertEqual(fetchedProfiles["pubkey3"]?.name, "User 3")
    }
    
    func testCacheEviction() async throws {
        // Create manager with small cache
        let config = NDKProfileConfig(cacheSize: 2)
        let smallProfileManager = NDKProfileManager(ndk: ndk, config: config)
        
        // Add 3 profiles (should evict the first)
        let profiles = [
            ("pubkey1", NDKUserProfile(name: "User 1")),
            ("pubkey2", NDKUserProfile(name: "User 2")),
            ("pubkey3", NDKUserProfile(name: "User 3"))
        ]
        
        for (pubkey, profile) in profiles {
            let event = NDKEvent(kind: EventKind.metadata)
            event.pubkey = pubkey
            event.content = try JSONEncoder().encode(profile).string
            mockCache.mockEvents = [event]
            
            _ = try await smallProfileManager.fetchProfile(for: pubkey)
        }
        
        // Check cache stats
        let stats = await smallProfileManager.getCacheStats()
        XCTAssertEqual(stats.size, 2)
    }
    
    func testProfileBatching() async throws {
        // Create manager with batching enabled
        let config = NDKProfileConfig(
            batchRequests: true,
            batchDelay: 0.2, // 200ms delay
            maxBatchSize: 10
        )
        let batchingManager = NDKProfileManager(ndk: ndk, config: config)
        
        // Setup mock events
        let pubkeys = (1...5).map { "pubkey\($0)" }
        var events: [NDKEvent] = []
        for pubkey in pubkeys {
            let profile = NDKUserProfile(name: "User \(pubkey)")
            let event = NDKEvent(kind: EventKind.metadata)
            event.pubkey = pubkey
            event.content = try JSONEncoder().encode(profile).string
            events.append(event)
        }
        mockCache.mockEvents = events
        
        // Start multiple concurrent fetch requests
        let tasks = pubkeys.map { pubkey in
            Task {
                try await batchingManager.fetchProfile(for: pubkey)
            }
        }
        
        // Wait for all to complete
        let results = try await withThrowingTaskGroup(of: NDKUserProfile?.self) { group in
            for task in tasks {
                group.addTask {
                    try await task.value
                }
            }
            
            var profiles: [NDKUserProfile?] = []
            for try await profile in group {
                profiles.append(profile)
            }
            return profiles
        }
        
        // Verify all profiles were fetched
        XCTAssertEqual(results.compactMap { $0 }.count, 5)
    }
    
    func testCacheStaleness() async throws {
        // Create manager with short stale time
        let config = NDKProfileConfig(staleAfter: 0.1) // 100ms
        let manager = NDKProfileManager(ndk: ndk, config: config)
        
        let pubkey = "test_pubkey"
        let profile = NDKUserProfile(name: "Test User")
        
        // First fetch - will cache
        let event = NDKEvent(kind: EventKind.metadata)
        event.pubkey = pubkey
        event.content = try JSONEncoder().encode(profile).string
        mockCache.mockEvents = [event]
        
        _ = try await manager.fetchProfile(for: pubkey)
        
        // Wait for cache to become stale
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Second fetch - should refetch due to staleness
        let updatedProfile = NDKUserProfile(name: "Updated User")
        event.content = try JSONEncoder().encode(updatedProfile).string
        mockCache.mockEvents = [event]
        
        let fetched = try await manager.fetchProfile(for: pubkey)
        XCTAssertEqual(fetched?.name, "Updated User")
    }
}

// MARK: - Mock Cache for Testing

private class MockCache: NDKCacheAdapter {
    var events: [EventID: NDKEvent] = [:]
    var profiles: [PublicKey: NDKUserProfile] = [:]
    var mockEvents: [NDKEvent] = []
    
    func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay: NDKRelay?) async {
        if let id = event.id {
            events[id] = event
        }
    }
    
    func queryEvents(filters: [NDKFilter]) async -> AsyncThrowingStream<NDKEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in mockEvents {
                if filters.contains(where: { $0.matches(event: event) }) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }
    }
    
    func fetchProfile(pubkey: PublicKey) async -> NDKUserProfile? {
        return profiles[pubkey]
    }
    
    func saveProfile(_ profile: NDKUserProfile, for pubkey: PublicKey) async {
        profiles[pubkey] = profile
    }
    
    func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {}
    func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] { [] }
    func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {}
}

private extension Data {
    var string: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}