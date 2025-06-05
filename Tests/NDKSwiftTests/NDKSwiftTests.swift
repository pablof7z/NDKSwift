@testable import NDKSwift
import XCTest

final class NDKSwiftTests: XCTestCase {
    func testNDKInitialization() {
        let ndk = NDK()

        XCTAssertNil(ndk.signer)
        XCTAssertNil(ndk.cacheAdapter)
        XCTAssertNil(ndk.activeUser)
        XCTAssertTrue(ndk.relays.isEmpty)
        XCTAssertFalse(ndk.debugMode)
    }

    func testNDKWithRelays() {
        let relayUrls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com",
        ]

        let ndk = NDK(relayUrls: relayUrls)

        XCTAssertEqual(ndk.relays.count, 3)
        XCTAssertTrue(ndk.relays.contains { $0.url == "wss://relay1.example.com" })
        XCTAssertTrue(ndk.relays.contains { $0.url == "wss://relay2.example.com" })
        XCTAssertTrue(ndk.relays.contains { $0.url == "wss://relay3.example.com" })
    }

    func testNDKRelayManagement() {
        let ndk = NDK()

        // Add relays
        let relay1 = ndk.addRelay("wss://relay1.example.com")
        let relay2 = ndk.addRelay("wss://relay2.example.com")

        XCTAssertEqual(ndk.relays.count, 2)
        XCTAssertTrue(ndk.relays.contains { $0 === relay1 })
        XCTAssertTrue(ndk.relays.contains { $0 === relay2 })

        // Remove relay
        ndk.removeRelay("wss://relay1.example.com")

        XCTAssertEqual(ndk.relays.count, 1)
        XCTAssertFalse(ndk.relays.contains { $0 === relay1 })
        XCTAssertTrue(ndk.relays.contains { $0 === relay2 })
    }

    func testNDKUserManagement() {
        let ndk = NDK()

        // Get user by pubkey
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let user = ndk.getUser(pubkey)

        XCTAssertEqual(user.pubkey, pubkey)
        XCTAssertNotNil(user.ndk)
        XCTAssertTrue(user.ndk === ndk)

        // Get user by npub (not implemented yet)
        let npubUser = ndk.getUser(npub: "npub1...")
        XCTAssertNil(npubUser)
    }

    func testNDKSubscription() {
        let ndk = NDK()

        let filters = [
            NDKFilter(kinds: [1], limit: 10),
            NDKFilter(authors: ["pubkey1", "pubkey2"]),
        ]

        let subscription = ndk.subscribe(filters: filters)

        XCTAssertNotNil(subscription.id)
        XCTAssertEqual(subscription.filters.count, 2)
        XCTAssertFalse(subscription.options.closeOnEose)
        XCTAssertTrue(subscription.ndk === ndk)

        // Test with custom sub ID using NDKSubscription directly
        let customSub = NDKSubscription(id: "custom-id", filters: filters, ndk: ndk)
        XCTAssertEqual(customSub.id, "custom-id")
    }

    func testEventKindConstants() {
        XCTAssertEqual(EventKind.metadata, 0)
        XCTAssertEqual(EventKind.textNote, 1)
        XCTAssertEqual(EventKind.recommendRelay, 2)
        XCTAssertEqual(EventKind.contacts, 3)
        XCTAssertEqual(EventKind.encryptedDirectMessage, 4)
        XCTAssertEqual(EventKind.deletion, 5)
        XCTAssertEqual(EventKind.repost, 6)
        XCTAssertEqual(EventKind.reaction, 7)
        XCTAssertEqual(EventKind.relayList, 10002)
        XCTAssertEqual(EventKind.longFormContent, 30023)
    }

    func testNDKErrorTypes() {
        let errors: [NDKError] = [
            .invalidPublicKey,
            .invalidPrivateKey,
            .invalidEventID,
            .invalidSignature,
            .signingFailed,
            .verificationFailed,
            .invalidFilter,
            .relayConnectionFailed("test"),
            .subscriptionFailed("test"),
            .cacheFailed("test"),
            .timeout,
            .cancelled,
            .notImplemented,
            .custom("test"),
        ]

        // Ensure all errors have descriptions
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
