@testable import NDKSwift
import XCTest

final class NDKUserTests: XCTestCase {
    func testUserInitialization() {
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let user = NDKUser(pubkey: pubkey)

        XCTAssertEqual(user.pubkey, pubkey)
        XCTAssertNil(user.profile)
        XCTAssertNil(user.nip05)
        XCTAssertNil(user.displayName)
        XCTAssertNil(user.name)
        XCTAssertTrue(user.relayList.isEmpty)
    }

    func testUserEquality() {
        let pubkey1 = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let pubkey2 = "e0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59f"

        let user1a = NDKUser(pubkey: pubkey1)
        let user1b = NDKUser(pubkey: pubkey1)
        let user2 = NDKUser(pubkey: pubkey2)

        XCTAssertEqual(user1a, user1b)
        XCTAssertNotEqual(user1a, user2)

        // Test hashable
        var userSet = Set<NDKUser>()
        userSet.insert(user1a)
        userSet.insert(user1b)
        userSet.insert(user2)

        XCTAssertEqual(userSet.count, 2) // user1a and user1b are the same
    }

    func testUserProfile() {
        let user = NDKUser(pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")

        let profile = NDKUserProfile(
            name: "alice",
            displayName: "Alice",
            about: "Nostr enthusiast",
            picture: "https://example.com/alice.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "alice@example.com",
            lud16: "alice@walletofsatoshi.com",
            website: "https://alice.example.com"
        )

        user.updateProfile(profile)

        XCTAssertEqual(user.name, "alice")
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(user.nip05, "alice@example.com")
        XCTAssertEqual(user.profile?.about, "Nostr enthusiast")
        XCTAssertEqual(user.profile?.picture, "https://example.com/alice.jpg")
        XCTAssertEqual(user.profile?.banner, "https://example.com/banner.jpg")
        XCTAssertEqual(user.profile?.lud16, "alice@walletofsatoshi.com")
        XCTAssertEqual(user.profile?.website, "https://alice.example.com")
    }

    func testUserDisplayNameFallback() {
        let user = NDKUser(pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")

        // No profile, no display name
        XCTAssertNil(user.displayName)

        // Profile with only name
        let profileWithName = NDKUserProfile(name: "bob")
        user.updateProfile(profileWithName)
        XCTAssertEqual(user.displayName, "bob")

        // Profile with display name
        let profileWithDisplayName = NDKUserProfile(
            name: "bob",
            displayName: "Bob the Builder"
        )
        user.updateProfile(profileWithDisplayName)
        XCTAssertEqual(user.displayName, "Bob the Builder")
    }

    func testShortPubkey() {
        let longPubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let user = NDKUser(pubkey: longPubkey)

        let shortPubkey = user.shortPubkey
        XCTAssertEqual(shortPubkey, "d0a1ffb8...20c9a59e")

        // Test with short pubkey
        let shortUser = NDKUser(pubkey: "abc123")
        XCTAssertEqual(shortUser.shortPubkey, "abc123")
    }

    func testUserProfileCodable() throws {
        let originalProfile = NDKUserProfile(
            name: "test",
            displayName: "Test User",
            about: "About me",
            picture: "https://example.com/pic.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "test@example.com",
            lud16: "test@wallet.com",
            lud06: "lnurl1234",
            website: "https://test.com"
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(originalProfile)
        let json = String(data: data, encoding: .utf8)!

        // Verify JSON structure
        XCTAssertTrue(json.contains("\"name\":\"test\""))
        XCTAssertTrue(json.contains("\"display_name\":\"Test User\""))
        XCTAssertTrue(json.contains("\"about\":\"About me\""))
        XCTAssertTrue(json.contains("\"picture\":\"https:\\/\\/example.com\\/pic.jpg\""))
        XCTAssertTrue(json.contains("\"nip05\":\"test@example.com\""))

        // Decode
        let decoder = JSONDecoder()
        let decodedProfile = try decoder.decode(NDKUserProfile.self, from: data)

        XCTAssertEqual(decodedProfile.name, originalProfile.name)
        XCTAssertEqual(decodedProfile.displayName, originalProfile.displayName)
        XCTAssertEqual(decodedProfile.about, originalProfile.about)
        XCTAssertEqual(decodedProfile.picture, originalProfile.picture)
        XCTAssertEqual(decodedProfile.banner, originalProfile.banner)
        XCTAssertEqual(decodedProfile.nip05, originalProfile.nip05)
        XCTAssertEqual(decodedProfile.lud16, originalProfile.lud16)
        XCTAssertEqual(decodedProfile.lud06, originalProfile.lud06)
        XCTAssertEqual(decodedProfile.website, originalProfile.website)
    }

    func testUserProfileAdditionalFields() throws {
        // Test decoding profile with additional fields
        let jsonString = """
        {
            "name": "test",
            "display_name": "Test",
            "custom_field": "custom_value",
            "another_field": "another_value"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        var profile = try decoder.decode(NDKUserProfile.self, from: data)

        XCTAssertEqual(profile.name, "test")
        XCTAssertEqual(profile.displayName, "Test")
        XCTAssertEqual(profile.additionalField("custom_field"), "custom_value")
        XCTAssertEqual(profile.additionalField("another_field"), "another_value")

        // Test setting additional fields
        profile.setAdditionalField("new_field", value: "new_value")
        XCTAssertEqual(profile.additionalField("new_field"), "new_value")

        // Test encoding preserves additional fields
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encodedData = try encoder.encode(profile)
        let encodedString = String(data: encodedData, encoding: .utf8)!

        XCTAssertTrue(encodedString.contains("\"custom_field\":\"custom_value\""))
        XCTAssertTrue(encodedString.contains("\"another_field\":\"another_value\""))
        XCTAssertTrue(encodedString.contains("\"new_field\":\"new_value\""))
    }

    func testNDKIntegration() async throws {
        let ndk = NDK()
        let user = ndk.getUser("d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")

        XCTAssertNotNil(user.ndk)
        XCTAssertTrue(user.ndk === ndk)

        // Test error when NDK is not set
        let standaloneUser = NDKUser(pubkey: "abc123")

        do {
            _ = try await standaloneUser.fetchProfile()
            XCTFail("Should have thrown error")
        } catch {
            if let ndkError = error as? NDKError {
                XCTAssertEqual(ndkError.localizedDescription, "NDK instance not set")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
}
