@testable import NDKSwiftCore
import XCTest

final class ProfileSemanticCachingTests: XCTestCase {
    var cache: NDKNostrDBCache!

    override func setUp() async throws {
        try await super.setUp()

        // Create test cache
        cache = try await NDKTestFactory.createTestCache()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    func testProfileSavingWithoutJSONParsing() async throws {
        // Create a profile with standard and additional fields
        var profile = NDKUserProfile(
            name: "Alice",
            displayName: "Alice in Nostrland",
            about: "Testing semantic caching",
            picture: "https://example.com/alice.jpg",
            banner: "https://example.com/banner.jpg",
            nip05: "alice@nostr.example",
            lud16: "alice@getalby.com",
            website: "https://alice.example"
        )

        // Add some additional fields
        profile.setAdditionalField("pronouns", value: "she/her")
        profile.setAdditionalField("location", value: "Wonderland")

        let pubkey = "test_pubkey_123"

        // Save the profile
        try await cache.saveProfile(profile, pubkey: pubkey)

        // Retrieve the profile
        let retrievedProfile = await cache.getProfile(pubkey: pubkey)

        // Verify all standard fields
        XCTAssertEqual(retrievedProfile?.name, "Alice")
        XCTAssertEqual(retrievedProfile?.displayName, "Alice in Nostrland")
        XCTAssertEqual(retrievedProfile?.about, "Testing semantic caching")
        XCTAssertEqual(retrievedProfile?.picture, "https://example.com/alice.jpg")
        XCTAssertEqual(retrievedProfile?.banner, "https://example.com/banner.jpg")
        XCTAssertEqual(retrievedProfile?.nip05, "alice@nostr.example")
        XCTAssertEqual(retrievedProfile?.lud16, "alice@getalby.com")
        XCTAssertEqual(retrievedProfile?.website, "https://alice.example")

        // Verify additional fields
        XCTAssertEqual(retrievedProfile?.additionalField("pronouns"), "she/her")
        XCTAssertEqual(retrievedProfile?.additionalField("location"), "Wonderland")
    }

    func testProfileRetrievalPerformance() async throws {
        // Create a profile with many additional fields
        var profile = NDKUserProfile(
            name: "Performance Test User",
            displayName: "Perf User",
            about: "A user for performance testing with many fields"
        )

        // Add 50 additional fields
        for i in 0 ..< 50 {
            profile.setAdditionalField("field_\(i)", value: "value_\(i)")
        }

        let pubkey = "perf_test_pubkey"
        try await cache.saveProfile(profile, pubkey: pubkey)

        // Measure retrieval time
        let startTime = CFAbsoluteTimeGetCurrent()

        // Retrieve profile 100 times
        for _ in 0 ..< 100 {
            _ = await cache.getProfile(pubkey: pubkey)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = elapsed / 100.0 * 1000 // Convert to milliseconds

        print("Average profile retrieval time: \(averageTime)ms")

        // Should be very fast since no JSON parsing is needed
        XCTAssertLessThan(averageTime, 1.0, "Profile retrieval should be under 1ms on average")
    }

    func testBackwardCompatibilityWithJSONOnly() async throws {
        // Simulate an old profile stored only as JSON (before migration)
        let pubkey = "legacy_pubkey"
        let jsonProfile = """
        {
            "name": "Legacy User",
            "display_name": "Legacy Display",
            "about": "A user from before semantic caching",
            "custom_field": "custom_value"
        }
        """

        // Insert directly into database to simulate pre-migration data
        try await cache.insertRawProfileForTesting(pubkey: pubkey, json: jsonProfile)

        // Should still be able to retrieve the profile
        let retrievedProfile = await cache.getProfile(pubkey: pubkey)

        XCTAssertEqual(retrievedProfile?.name, "Legacy User")
        XCTAssertEqual(retrievedProfile?.displayName, "Legacy Display")
        XCTAssertEqual(retrievedProfile?.about, "A user from before semantic caching")
        XCTAssertEqual(retrievedProfile?.additionalField("custom_field"), "custom_value")
    }

    func testMigrationFromJSONToSemanticFields() async throws {
        // First, insert a profile with only JSON (simulating pre-migration state)
        let pubkey = "migration_test_pubkey"
        let jsonProfile = """
        {
            "name": "Pre-Migration User",
            "display_name": "Pre-Migration Display",
            "about": "Testing migration",
            "nip05": "user@example.com",
            "custom_data": "should be preserved"
        }
        """

        // Insert as JSON only
        try await cache.insertRawProfileForTesting(pubkey: pubkey, json: jsonProfile)

        // Retrieve the profile (should use JSON fallback)
        let profile = await cache.getProfile(pubkey: pubkey)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "Pre-Migration User")

        // Now save it again, which should populate the semantic fields
        if var updatedProfile = profile {
            updatedProfile.about = "Updated after migration"
            try await cache.saveProfile(updatedProfile, pubkey: pubkey)
        } else {
            XCTFail("Profile should not be nil")
        }

        // Verify the profile now has semantic fields populated
        let rawProfile: [String: Any]? = try await cache.getRawProfileForTesting(pubkey: pubkey)
        XCTAssertNotNil(rawProfile)

        // Check that individual fields are populated
        let nameVal = rawProfile?["name"] as? String
        let displayNameVal = rawProfile?["display_name"] as? String
        let aboutVal = rawProfile?["about"] as? String
        let nip05Val = rawProfile?["nip05"] as? String
        XCTAssertEqual(nameVal, "Pre-Migration User")
        XCTAssertEqual(displayNameVal, "Pre-Migration Display")
        XCTAssertEqual(aboutVal, "Updated after migration")
        XCTAssertEqual(nip05Val, "user@example.com")

        // Retrieve again and verify it uses semantic fields (not JSON)
        let finalProfile = await cache.getProfile(pubkey: pubkey)
        XCTAssertEqual(finalProfile?.about, "Updated after migration")
        XCTAssertEqual(finalProfile?.additionalField("custom_data"), "should be preserved")
    }
}
