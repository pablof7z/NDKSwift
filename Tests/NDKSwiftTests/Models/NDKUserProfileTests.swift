import XCTest
@testable import NDKSwift

final class NDKUserProfileTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        // Create NDK without cache for basic profile tests
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        ndk = nil
    }
    
    func testUserFetchProfile() async throws {
        // Setup
        let pubkey = "test_pubkey"
        let user = ndk.getUser(pubkey)
        
        // Test that user is created properly
        XCTAssertEqual(user.pubkey, pubkey)
        XCTAssertNotNil(user.ndk)
        
        // Without a relay connection, fetchProfile should return nil or timeout
        do {
            let fetchedProfile = try await user.fetchProfile()
            XCTAssertNil(fetchedProfile, "Should return nil without relay connection")
        } catch {
            // Timeout is also acceptable
            XCTAssertTrue(true, "Timeout is expected without relay connection")
        }
    }
    
    func testUserInitialization() {
        // Test user creation from pubkey
        let pubkey = "d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62"
        let user = ndk.getUser(pubkey)
        
        XCTAssertEqual(user.pubkey, pubkey)
        XCTAssertNotNil(user.ndk)
        XCTAssertEqual(user.npub, "npub1m8arggz248g4r38ymkzraz9z7neydat5ypfkwvheyhu735tddfpqt3f8xh")
    }
    
    func testUserFromNpub() {
        // Test user creation from npub
        let npub = "npub1m8arggz248g4r38ymkzraz9z7neydat5ypfkwvheyhu735tddfpqt3f8xh"
        let user = ndk.getUser(npub: npub)
        
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.pubkey, "d9fa34214aa9d151c4f4db843e9c2af4f246bab4205137731f91bcfa44d66a62")
        XCTAssertEqual(user?.npub, npub)
        
        // Test invalid npub
        let invalidUser = ndk.getUser(npub: "invalid_npub")
        XCTAssertNil(invalidUser)
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