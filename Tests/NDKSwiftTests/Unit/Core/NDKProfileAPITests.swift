import XCTest
@testable import NDKSwiftCore

/// Tests for the simplified profile API
/// - ndk.profile(for:) -> NDKProfile
/// - user.profile -> NDKProfile
@MainActor
final class NDKProfileAPITests: XCTestCase {

    private var ndk: NDK!
    private let testPubkey = "test_pubkey_12345"

    override func setUp() async throws {
        ndk = NDK()
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

        // Then returns truncated pubkey
        XCTAssert(displayName.hasPrefix("test_pubkey"))
        XCTAssert(displayName.hasSuffix("..."))
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

    // MARK: - user.profile Tests

    func testUserProfile_ReturnsSameProfileAsNDKProfile() {
        // Given a user
        let user = ndk.getUser(testPubkey)!

        // When getting profile via user vs ndk
        let userProfile = user.profile
        let ndkProfile = ndk.profile(for: testPubkey)

        // Then returns same instance
        XCTAssert(userProfile === ndkProfile)
    }

}
