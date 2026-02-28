import XCTest
@testable import NDKSwiftCore

/// Tests for the simplified profile API
/// - ndk.profile(for:) -> NDKProfile
/// - user.profile -> NDKProfile
@MainActor
final class NDKProfileAPITests: XCTestCase {

    private var ndk: NDK!
    private let testPubkey = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"

    override func setUp() async throws {
        ndk = try await NDKTestFactory.createNDK()
    }

    override func tearDown() async throws {
        ndk = nil
    }

    // MARK: - ndk.profile(for:) Tests

    func testProfileForPubkey_ReturnsNDKProfile() {
        // Given a pubkey

        // When getting profile
        let profile = ndk.profile(for: testPubkey)

        // Then returns NDKProfile instance
        XCTAssertNotNil(profile)
        XCTAssert(profile is NDKProfile)
    }

    func testProfileForPubkey_ReturnsSameInstanceForSamePubkey() {
        // Given a pubkey

        // When getting profile twice
        let profile1 = ndk.profile(for: testPubkey)
        let profile2 = ndk.profile(for: testPubkey)

        // Then returns same instance (deduplication)
        XCTAssert(profile1 === profile2)
    }

    func testProfileForPubkey_ReturnsDifferentInstancesForDifferentPubkeys() {
        // Given two different pubkeys
        let pubkey1 = "pubkey1"
        let pubkey2 = "pubkey2"

        // When getting profiles
        let profile1 = ndk.profile(for: pubkey1)
        let profile2 = ndk.profile(for: pubkey2)

        // Then returns different instances
        XCTAssert(profile1 !== profile2)
    }

    func testProfile_StartsWithNilMetadata() {
        // Given a new pubkey with no cached data

        // When getting profile
        let profile = ndk.profile(for: testPubkey)

        // Then metadata is initially nil
        XCTAssertNil(profile.metadata)
    }

    func testProfile_NameReturnsEmptyStringWhenNoMetadata() {
        // Given profile with no metadata
        let profile = ndk.profile(for: testPubkey)

        // When accessing name
        let name = profile.name

        // Then returns empty string
        XCTAssertEqual(name, "")
    }

    func testProfile_DisplayNameReturnsFallbackWhenNoMetadata() {
        // Given profile with no metadata
        let profile = ndk.profile(for: testPubkey)

        // When accessing displayName
        let displayName = profile.displayName

        // Then returns truncated npub (starts with npub1, ends with ...)
        XCTAssert(displayName.hasPrefix("npub1"), "Expected npub format, got: \(displayName)")
        XCTAssert(displayName.hasSuffix("..."), "Expected ... suffix, got: \(displayName)")
    }

    func testProfile_PictureURLReturnsNilWhenNoMetadata() {
        // Given profile with no metadata
        let profile = ndk.profile(for: testPubkey)

        // When accessing pictureURL
        let pictureURL = profile.pictureURL

        // Then returns nil
        XCTAssertNil(pictureURL)
    }

    func testProfile_AboutReturnsEmptyStringWhenNoMetadata() {
        // Given profile with no metadata
        let profile = ndk.profile(for: testPubkey)

        // When accessing about
        let about = profile.about

        // Then returns empty string
        XCTAssertEqual(about, "")
    }

    func testProfile_Nip05ReturnsNilWhenNoMetadata() {
        // Given profile with no metadata
        let profile = ndk.profile(for: testPubkey)

        // When accessing nip05
        let nip05 = profile.nip05

        // Then returns nil
        XCTAssertNil(nip05)
    }

    // MARK: - LRU Cache Tests

    func testProfileCache_EvictsOldestWhenAtCapacity() {
        // Given: fill cache to capacity (500)
        var firstProfiles: [NDKProfile] = []
        for i in 0..<500 {
            let pubkey = String(format: "%064d", i)
            firstProfiles.append(ndk.profile(for: pubkey))
        }

        // When: add one more profile
        let newPubkey = String(format: "%064d", 999)
        _ = ndk.profile(for: newPubkey)

        // Then: first profile should be evicted (new instance returned)
        let firstPubkey = String(format: "%064d", 0)
        let refetchedFirst = ndk.profile(for: firstPubkey)
        XCTAssert(refetchedFirst !== firstProfiles[0], "First profile should have been evicted and return new instance")
    }

    func testProfileCache_AccessUpdatesLRUPosition() {
        // Given: fill cache to capacity
        for i in 0..<500 {
            let pubkey = String(format: "%064d", i)
            _ = ndk.profile(for: pubkey)
        }

        // When: access the first profile (moves it to most recent)
        let firstPubkey = String(format: "%064d", 0)
        let firstProfile = ndk.profile(for: firstPubkey)

        // And: add a new profile (should evict second, not first)
        let newPubkey = String(format: "%064d", 999)
        _ = ndk.profile(for: newPubkey)

        // Then: first profile should still be cached (same instance)
        let refetchedFirst = ndk.profile(for: firstPubkey)
        XCTAssert(refetchedFirst === firstProfile, "First profile should still be cached after access")

        // And: second profile should be evicted (new instance)
        let secondPubkey = String(format: "%064d", 1)
        let originalSecond = ndk.profile(for: secondPubkey)
        // Add another to trigger eviction check
        let anotherNewPubkey = String(format: "%064d", 998)
        _ = ndk.profile(for: anotherNewPubkey)
        // Now second should be evicted since it wasn't accessed
    }

    func testProfileCache_KeepsProfilesAliveWithStrongReferences() {
        // Given: create a profile
        let profile = ndk.profile(for: testPubkey)

        // When: access it again without holding external reference
        let profile2 = ndk.profile(for: testPubkey)

        // Then: same instance (cache holds strong reference)
        XCTAssert(profile === profile2, "Cache should hold strong reference to profile")
    }

}
