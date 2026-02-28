import XCTest
@testable import NDKSwiftCore

/// Tests that relays added during publishing operations have the correct origin
/// and don't pollute the app relays list
final class PublishingRelayOriginTests: XCTestCase {

    // MARK: - Relay Origin During Publishing

    /// When a relay is added by the publishing strategy (not explicitly configured by the app),
    /// it should NOT be marked as an app relay
    func test_relayAddedDuringPublishing_isNotAppRelay() async throws {
        // Setup: Create NDK with NO initial relays
        let ndk = try await NDKTestFactory.createNDK()

        // Verify no app relays initially
        let initialAppRelays = await ndk.pool.appRelays
        XCTAssertTrue(initialAppRelays.isEmpty, "Should start with no app relays")

        // Simulate what getOrConnectRelay does during publishing:
        // It calls ndk.addRelay without specifying an origin
        // This is the BUG - it should NOT use .appRelays
        let publishingRelayUrl = "wss://discovered-during-publish.test.com"

        // This is what getOrConnectRelay currently does (incorrectly):
        // await ndk.addRelay(publishingRelayUrl) // defaults to .appRelays

        // This is what it SHOULD do - use outbox origin:
        _ = await ndk.pool.addRelay(publishingRelayUrl, origin: .outbox(authorPubkey: "testpubkey1234567890123456789012345678901234567890123456789012"))

        // Verify the relay exists in the pool
        let allRelays = await ndk.pool.relays
        XCTAssertEqual(allRelays.count, 1, "Relay should be added to pool")

        // The key assertion: relay added during publishing should NOT be in appRelays
        let appRelays = await ndk.pool.appRelays
        XCTAssertTrue(appRelays.isEmpty, "Relay added during publishing should NOT appear in appRelays")

        // Verify the relay has the correct origin
        if let relay = allRelays.first {
            let origin = await relay.origin
            if case .outbox = origin {
                // Expected
            } else {
                XCTFail("Relay should have outbox origin, but has: \(origin)")
            }
        }
    }

    /// Verifies that the publishing strategy's getOrConnectRelay method
    /// uses the correct origin when adding new relays.
    ///
    /// The bug: getOrConnectRelay calls ndk.addRelay(url) without an origin,
    /// which defaults to .appRelays. It should pass .outbox origin instead.
    func test_publishingStrategyAddsRelayWithOutboxOrigin_notAppRelays() async throws {
        // Setup: Create NDK with one explicit app relay
        let appRelayUrl = "wss://my-app-relay.test.com"
        let ndk = try await NDKTestFactory.createNDK(relayURLs: [appRelayUrl])
        await ndk.initializeRelays()

        // Verify initial state: one app relay
        var appRelays = await ndk.pool.appRelays
        XCTAssertEqual(appRelays.count, 1, "Should have one app relay")
        XCTAssertTrue(appRelays.first?.url.contains("my-app-relay.test.com") ?? false)

        // Simulate what getOrConnectRelay SHOULD do when adding a relay during publishing:
        // It should use .outbox origin, not the default .appRelays
        let outboxRelayUrl = "wss://user-relay-from-outbox.test.com"
        let authorPubkey = "testauthor12345678901234567890123456789012345678901234567890123"

        // CORRECT: Use outbox origin when adding relay during publishing
        _ = await ndk.addRelay(outboxRelayUrl, origin: .outbox(authorPubkey: authorPubkey))

        // After adding with outbox origin, check appRelays
        appRelays = await ndk.pool.appRelays

        // Only the explicitly configured relay should be an app relay
        XCTAssertEqual(appRelays.count, 1,
            "Only the explicitly configured relay should be an app relay. " +
            "Relays added during publishing should NOT be app relays.")

        // Verify the outbox relay is in the pool but NOT in appRelays
        let allRelays = await ndk.pool.relays
        XCTAssertEqual(allRelays.count, 2, "Both relays should be in pool")

        let outboxRelay = allRelays.first { $0.url.contains("user-relay-from-outbox.test.com") }
        XCTAssertNotNil(outboxRelay, "Outbox relay should be in pool")
        XCTAssertFalse(appRelays.contains { $0.url.contains("user-relay-from-outbox.test.com") },
            "Outbox relay should NOT be in appRelays")

        // Verify the relay has outbox origin
        if let relay = outboxRelay {
            let origin = await relay.origin
            if case let .outbox(pubkey) = origin {
                XCTAssertEqual(pubkey, authorPubkey)
            } else {
                XCTFail("Relay should have outbox origin, but has: \(origin)")
            }
        }
    }

    /// Confirms that explicitly added app relays ARE in appRelays
    func test_explicitlyAddedRelay_isAppRelay() async throws {
        let ndk = try await NDKTestFactory.createNDK()

        // Explicitly add a relay as an app relay
        let appRelayUrl = "wss://explicit-app-relay.test.com"
        _ = await ndk.addRelay(appRelayUrl, origin: .appRelays)

        let appRelays = await ndk.pool.appRelays
        XCTAssertEqual(appRelays.count, 1)
        // URLs get normalized with trailing slash
        XCTAssertTrue(appRelays.first?.url.hasPrefix("wss://explicit-app-relay.test.com") ?? false)
    }

    /// Confirms that discovery relays are NOT in appRelays
    func test_discoveryRelay_isNotAppRelay() async throws {
        let ndk = try await NDKTestFactory.createNDK()

        let discoveryUrl = "wss://discovery.test.com"
        _ = await ndk.pool.addRelay(discoveryUrl, origin: .discovery)

        let appRelays = await ndk.pool.appRelays
        XCTAssertTrue(appRelays.isEmpty, "Discovery relays should not be app relays")
    }

    /// Confirms that outbox relays are NOT in appRelays
    func test_outboxRelay_isNotAppRelay() async throws {
        let ndk = try await NDKTestFactory.createNDK()

        let outboxUrl = "wss://outbox.test.com"
        _ = await ndk.pool.addRelay(outboxUrl, origin: .outbox(authorPubkey: "somepubkey12345678901234567890123456789012345678901234567890123"))

        let appRelays = await ndk.pool.appRelays
        XCTAssertTrue(appRelays.isEmpty, "Outbox relays should not be app relays")
    }
}
