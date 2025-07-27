import XCTest
import Combine
@testable import NDKSwift
@testable import NDKSwiftUI

/// Tests for NDKProfileDataSource
@MainActor
final class NDKProfileDataSourceTests: NDKTestCase {
    
    var ndk: NDK!
    var mockCache: MemoryCache!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockCache = createMemoryCache()
        ndk = createTestNDK(cache: mockCache)
        cancellables = []
    }
    
    override func tearDown() async throws {
        cancellables = nil
        mockCache = nil
        ndk = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        XCTAssertNil(dataSource.profile)
        XCTAssertFalse(dataSource.isLoading)
        XCTAssertNil(dataSource.error)
    }
    
    // MARK: - Profile Loading Tests
    
    func testProfileLoading() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        // Create and save a profile event
        let profileContent = """
        {
            "name": "Alice",
            "display_name": "Alice Wonderland",
            "about": "Test user",
            "picture": "https://example.com/alice.jpg",
            "nip05": "alice@example.com"
        }
        """
        
        let profileEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: profileContent,
            pubkey: pubkey,
            createdAt: Int64(Date().timeIntervalSince1970)
        )
        
        // Save to cache
        try await mockCache.saveEvent(profileEvent)
        
        // Wait for profile to load
        let expectation = XCTestExpectation(description: "Profile loads")
        
        dataSource.$profile
            .dropFirst()
            .sink { profile in
                if profile != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Verify profile data
        XCTAssertNotNil(dataSource.profile)
        XCTAssertEqual(dataSource.profile?.name, "Alice")
        XCTAssertEqual(dataSource.profile?.displayName, "Alice Wonderland")
        XCTAssertEqual(dataSource.profile?.about, "Test user")
        XCTAssertEqual(dataSource.profile?.picture, "https://example.com/alice.jpg")
        XCTAssertEqual(dataSource.profile?.nip05, "alice@example.com")
    }
    
    // MARK: - Display Name Tests
    
    func testDisplayNameFallbacks() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        // Test with no profile - should use npub fallback
        let npub = NDKUser(pubkey: pubkey).npub
        let expectedFallback = String(npub.prefix(16)) + "..."
        XCTAssertEqual(dataSource.displayName, expectedFallback)
        
        // Test with name only
        let nameOnlyContent = """
        {
            "name": "Alice"
        }
        """
        
        let nameOnlyEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: nameOnlyContent,
            pubkey: pubkey
        )
        
        try await mockCache.saveEvent(nameOnlyEvent)
        
        // Wait for update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(dataSource.displayName, "Alice")
        
        // Test with display_name
        let displayNameContent = """
        {
            "name": "Alice",
            "display_name": "Alice Wonderland"
        }
        """
        
        let displayNameEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: displayNameContent,
            pubkey: pubkey,
            createdAt: Int64(Date().timeIntervalSince1970) + 1
        )
        
        try await mockCache.saveEvent(displayNameEvent)
        
        // Wait for update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(dataSource.displayName, "Alice Wonderland")
    }
    
    // MARK: - Picture URL Tests
    
    func testPictureURL() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        // Test with no profile
        XCTAssertNil(dataSource.pictureURL)
        
        // Test with valid picture URL
        let profileContent = """
        {
            "picture": "https://example.com/alice.jpg"
        }
        """
        
        let profileEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: profileContent,
            pubkey: pubkey
        )
        
        try await mockCache.saveEvent(profileEvent)
        
        // Wait for update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(dataSource.pictureURL?.absoluteString, "https://example.com/alice.jpg")
    }
    
    // MARK: - Multiple Profile Events Tests
    
    func testLatestProfileEventIsUsed() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        // Create older profile event
        let olderContent = """
        {
            "name": "Old Alice"
        }
        """
        
        let olderEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: olderContent,
            pubkey: pubkey,
            createdAt: 1000
        )
        
        // Create newer profile event
        let newerContent = """
        {
            "name": "New Alice"
        }
        """
        
        let newerEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: newerContent,
            pubkey: pubkey,
            createdAt: 2000
        )
        
        // Save both events
        try await mockCache.saveEvent(olderEvent)
        try await mockCache.saveEvent(newerEvent)
        
        // Wait for profile to load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should use the newer event
        XCTAssertEqual(dataSource.profile?.name, "New Alice")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidJSONHandling() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        // Create event with invalid JSON
        let invalidEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: "{ invalid json }",
            pubkey: pubkey
        )
        
        try await mockCache.saveEvent(invalidEvent)
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Profile should remain nil with invalid JSON
        XCTAssertNil(dataSource.profile)
    }
    
    // MARK: - Real-time Update Tests
    
    func testRealTimeProfileUpdates() async throws {
        let pubkey = TestFixtures.Keys.alice.publicKey
        let dataSource = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)
        
        var profileUpdates: [NDKUserProfile?] = []
        let expectation = XCTestExpectation(description: "Receive profile updates")
        expectation.expectedFulfillmentCount = 3
        
        dataSource.$profile
            .sink { profile in
                profileUpdates.append(profile)
                if profileUpdates.count <= 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Initial state
        XCTAssertNil(dataSource.profile)
        
        // First update
        let firstProfileContent = """
        {
            "name": "Alice v1"
        }
        """
        
        let firstEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: firstProfileContent,
            pubkey: pubkey,
            createdAt: 1000
        )
        
        try await mockCache.saveEvent(firstEvent)
        
        // Second update
        let secondProfileContent = """
        {
            "name": "Alice v2",
            "about": "Updated profile"
        }
        """
        
        let secondEvent = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            content: secondProfileContent,
            pubkey: pubkey,
            createdAt: 2000
        )
        
        try await mockCache.saveEvent(secondEvent)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Verify we received updates
        XCTAssertTrue(profileUpdates.count >= 3)
        XCTAssertNil(profileUpdates[0]) // Initial nil state
        XCTAssertEqual(profileUpdates[1]?.name, "Alice v1")
        XCTAssertEqual(profileUpdates[2]?.name, "Alice v2")
        XCTAssertEqual(profileUpdates[2]?.about, "Updated profile")
    }
}