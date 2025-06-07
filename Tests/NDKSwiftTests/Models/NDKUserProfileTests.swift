import XCTest
@testable import NDKSwift

final class NDKUserProfileTests: XCTestCase {
    var ndk: NDK!
    var mockCache: MockCache!
    
    override func setUp() async throws {
        mockCache = MockCache()
        ndk = NDK(cacheAdapter: mockCache)
    }
    
    override func tearDown() async throws {
        ndk = nil
        mockCache = nil
    }
    
    func testUserFetchProfile() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let user = ndk.getUser(pubkey)
        
        let profile = NDKUserProfile(
            name: "Test User",
            displayName: "Test Display Name",
            about: "Test about section",
            picture: "https://example.com/pic.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "test@example.com"
        )
        
        // Mock event
        let event = NDKEvent(pubkey: pubkey, kind: EventKind.metadata)
        event.content = try JSONEncoder().encode(profile).string
        event.id = "test_event_id"
        event.sig = "test_sig"
        event.createdAt = Timestamp(Date().timeIntervalSince1970)
        mockCache.mockEvents = [event]
        
        // Test
        let fetchedProfile = try await user.fetchProfile()
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, "Test User")
        XCTAssertEqual(fetchedProfile?.displayName, "Test Display Name")
        XCTAssertEqual(fetchedProfile?.about, "Test about section")
        XCTAssertEqual(fetchedProfile?.picture, "https://example.com/pic.jpg")
        XCTAssertEqual(fetchedProfile?.banner, "https://example.com/banner.jpg")
        XCTAssertEqual(fetchedProfile?.nip05, "test@example.com")
        
        // Verify profile was cached
        let cachedProfile = await mockCache.fetchProfile(pubkey: pubkey)
        XCTAssertNotNil(cachedProfile)
        XCTAssertEqual(cachedProfile?.name, "Test User")
    }
    
    func testUserFetchProfileFromCache() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let user = ndk.getUser(pubkey)
        
        let cachedProfile = NDKUserProfile(
            name: "Cached User",
            displayName: "Cached Display"
        )
        
        // Pre-populate cache
        await mockCache.saveProfile(pubkey: pubkey, profile: cachedProfile)
        
        // Test - should return from cache without network call
        let fetchedProfile = try await user.fetchProfile()
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, "Cached User")
        XCTAssertEqual(fetchedProfile?.displayName, "Cached Display")
        
        // Verify no network call was made
        XCTAssertTrue(mockCache.mockEvents.isEmpty)
    }
    
    func testUserFetchProfileForceRefresh() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let user = ndk.getUser(pubkey)
        
        let cachedProfile = NDKUserProfile(name: "Cached User")
        await mockCache.saveProfile(pubkey: pubkey, profile: cachedProfile)
        
        let freshProfile = NDKUserProfile(name: "Fresh User")
        let event = NDKEvent(pubkey: pubkey, kind: EventKind.metadata)
        event.content = try JSONEncoder().encode(freshProfile).string
        event.id = "test_event_id"
        event.sig = "test_sig"
        event.createdAt = Timestamp(Date().timeIntervalSince1970)
        mockCache.mockEvents = [event]
        
        // Test - force refresh should bypass cache
        let fetchedProfile = try await user.fetchProfile(forceRefresh: true)
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, "Fresh User")
    }
    
    func testUserProfileDecoding() throws {
        // Test complete profile
        let json = """
        {
            "name": "alice",
            "display_name": "Alice",
            "about": "Bitcoin enthusiast",
            "picture": "https://example.com/alice.jpg",
            "banner": "https://example.com/banner.jpg",
            "nip05": "alice@example.com",
            "lud16": "alice@getalby.com",
            "website": "https://alice.example.com",
            "custom_field": "custom_value"
        }
        """
        
        let profile = try JSONDecoder().decode(NDKUserProfile.self, from: json.data(using: .utf8)!)
        
        XCTAssertEqual(profile.name, "alice")
        XCTAssertEqual(profile.displayName, "Alice")
        XCTAssertEqual(profile.about, "Bitcoin enthusiast")
        XCTAssertEqual(profile.picture, "https://example.com/alice.jpg")
        XCTAssertEqual(profile.banner, "https://example.com/banner.jpg")
        XCTAssertEqual(profile.nip05, "alice@example.com")
        XCTAssertEqual(profile.lud16, "alice@getalby.com")
        XCTAssertEqual(profile.website, "https://alice.example.com")
        XCTAssertEqual(profile.additionalField("custom_field"), "custom_value")
    }
    
    func testUserProfileEncoding() throws {
        var profile = NDKUserProfile(
            name: "bob",
            displayName: "Bob",
            about: "Nostr developer"
        )
        profile.setAdditionalField("pronouns", value: "he/him")
        
        let data = try JSONEncoder().encode(profile)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        XCTAssertEqual(json["name"] as? String, "bob")
        XCTAssertEqual(json["display_name"] as? String, "Bob")
        XCTAssertEqual(json["about"] as? String, "Nostr developer")
        XCTAssertEqual(json["pronouns"] as? String, "he/him")
    }
    
    func testUserProfilePartialData() throws {
        // Test minimal profile
        let json = """
        {
            "name": "charlie"
        }
        """
        
        let profile = try JSONDecoder().decode(NDKUserProfile.self, from: json.data(using: .utf8)!)
        
        XCTAssertEqual(profile.name, "charlie")
        XCTAssertNil(profile.displayName)
        XCTAssertNil(profile.about)
        XCTAssertNil(profile.picture)
    }
    
    func testUserUpdateProfile() {
        let pubkey = "test_pubkey"
        let user = ndk.getUser(pubkey)
        
        XCTAssertNil(user.profile)
        XCTAssertNil(user.displayName)
        XCTAssertNil(user.name)
        
        let profile = NDKUserProfile(
            name: "alice",
            displayName: "Alice"
        )
        
        user.updateProfile(profile)
        
        XCTAssertNotNil(user.profile)
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(user.name, "alice")
    }
    
    func testFilterUnionMerging() {
        // Test profile filter union merging
        let filter1 = NDKFilter(
            authors: ["pubkey1", "pubkey2"],
            kinds: [EventKind.metadata]
        )
        
        let filter2 = NDKFilter(
            authors: ["pubkey3", "pubkey4"],
            kinds: [EventKind.metadata]
        )
        
        let merged = filter1.mergedUnion(with: filter2)
        
        XCTAssertNotNil(merged)
        XCTAssertEqual(Set(merged!.authors ?? []), Set(["pubkey1", "pubkey2", "pubkey3", "pubkey4"]))
        XCTAssertEqual(merged!.kinds, [EventKind.metadata])
    }
    
    func testFilterUnionMergingIncompatible() {
        // Test that incompatible filters don't merge
        let filter1 = NDKFilter(
            authors: ["pubkey1"],
            kinds: [EventKind.metadata]
        )
        
        let filter2 = NDKFilter(
            authors: ["pubkey2"],
            kinds: [EventKind.textNote] // Different kind
        )
        
        let merged = filter1.mergedUnion(with: filter2)
        XCTAssertNil(merged)
    }
}


// MARK: - Extensions

private extension NDK {
    func fetchEvent(_ filter: NDKFilter) async throws -> NDKEvent? {
        let events = try await fetchEvents(filters: [filter])
        return events.first
    }
}

private extension Data {
    var string: String {
        String(data: self, encoding: .utf8) ?? ""
    }
}