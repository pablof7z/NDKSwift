@testable import NDKSwiftCore
import XCTest

/// Tests that verify the subscription-based contact list update mechanism.
/// When an event is published, it should flow through the cache to the session's
/// subscription and update sessionData.contactList automatically.
final class NDKSessionContactListTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!

    override func setUp() async throws {
        try await super.setUp()

        // Create NDK with in-memory cache (no relays needed for this test)
        ndk = NDK(relayURLs: [], cache: MemoryCache())

        // Create test signer
        signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
    }

    override func tearDown() async throws {
        await ndk.disconnect()
        ndk = nil
        signer = nil
        try await super.tearDown()
    }

    /// Tests that when a contact list event is published, the sessionData.contactList
    /// is updated via the subscription mechanism (not manual update).
    func testFollowUpdatesSessionDataViaSubscription() async throws {
        // Start session with follow list requirement
        let sessionData = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .blocking
            )
        )

        // Verify empty initial state
        XCTAssertTrue(sessionData.followList.isEmpty, "New user should have empty follow list")
        XCTAssertNil(sessionData.contactList, "Contact list should be nil initially")

        // Generate a target pubkey to follow
        let targetSigner = try NDKPrivateKeySigner.generate()
        let targetPubkey = try await targetSigner.pubkey

        // Follow using direct pattern: modify contactList and publish
        // The event should flow: publish → cache save → subscription notification → sessionData update
        let contactList = ndk.sessionData?.contactList ?? NDKContactList(ndk: ndk)
        contactList.addContact(pubkey: targetPubkey)
        try await contactList.sign()
        _ = try await ndk.publish(contactList.toNDKEvent())

        // Give the async subscription processing a moment to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify the subscription-based flow updated sessionData
        XCTAssertNotNil(ndk.sessionData?.contactList, "Contact list should exist after follow")
        XCTAssertTrue(
            ndk.sessionData?.contactList?.isFollowing(targetPubkey) ?? false,
            "Session data should reflect the follow via subscription"
        )
        XCTAssertTrue(
            ndk.sessionData?.followList.contains(targetPubkey) ?? false,
            "Follow list should contain the target pubkey"
        )
    }

    /// Tests that unfollow also updates sessionData via the subscription mechanism.
    func testUnfollowUpdatesSessionDataViaSubscription() async throws {
        // Start session
        _ = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .blocking
            )
        )

        // Generate a target pubkey
        let targetSigner = try NDKPrivateKeySigner.generate()
        let targetPubkey = try await targetSigner.pubkey

        // Follow first using direct pattern
        let contactList = ndk.sessionData?.contactList ?? NDKContactList(ndk: ndk)
        contactList.addContact(pubkey: targetPubkey)
        try await contactList.sign()
        _ = try await ndk.publish(contactList.toNDKEvent())
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify follow worked
        XCTAssertTrue(
            ndk.sessionData?.contactList?.isFollowing(targetPubkey) ?? false,
            "Should be following after follow"
        )

        // Now unfollow using direct pattern
        guard let currentContactList = ndk.sessionData?.contactList else {
            XCTFail("Contact list should exist")
            return
        }
        currentContactList.removeContact(pubkey: targetPubkey)
        try await currentContactList.sign()
        _ = try await ndk.publish(currentContactList.toNDKEvent())
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify the subscription-based flow updated sessionData
        XCTAssertFalse(
            ndk.sessionData?.contactList?.isFollowing(targetPubkey) ?? true,
            "Session data should reflect the unfollow via subscription"
        )
        XCTAssertFalse(
            ndk.sessionData?.followList.contains(targetPubkey) ?? true,
            "Follow list should not contain the target pubkey after unfollow"
        )
    }
}
