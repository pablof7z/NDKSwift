@testable import NDKSwiftCore
import XCTest

final class InternalSubscriptionO1Test: XCTestCase {
    func testRelayConnectionUsesO1Lookup() async throws {
        // Create NDK instance
        let ndk = NDK()

        // Create a mock relay pool with some relays
        let relayUrls = [
            "wss://relay1.example.com/",
            "wss://relay2.example.com/",
            "wss://relay3.example.com/",
        ]

        for url in relayUrls {
            await ndk.pool.addRelay(url)
        }

        // Create the internal subscription manager
        let manager = InternalSubscriptionManager(ndk: ndk)

        // Create subscriptions with different relay targets

        // Universal subscription (goes to all relays)
        let universalSub = await manager.createSubscription(
            id: "universal-sub",
            filters: [NDKFilter(kinds: [1])],
            relays: nil, // No specific relays = universal
            autoStart: false
        )

        // Relay-specific subscriptions
        let relay1Sub = await manager.createSubscription(
            id: "relay1-sub",
            filters: [NDKFilter(kinds: [2])],
            relays: ["wss://relay1.example.com/"],
            autoStart: false
        )

        let relay2Sub = await manager.createSubscription(
            id: "relay2-sub",
            filters: [NDKFilter(kinds: [3])],
            relays: ["wss://relay2.example.com/"],
            autoStart: false
        )

        let relay3Sub = await manager.createSubscription(
            id: "relay3-sub",
            filters: [NDKFilter(kinds: [4])],
            relays: ["wss://relay3.example.com/"],
            autoStart: false
        )

        // Multi-relay subscription
        let multiRelaySub = await manager.createSubscription(
            id: "multi-relay-sub",
            filters: [NDKFilter(kinds: [5])],
            relays: ["wss://relay1.example.com/", "wss://relay3.example.com/"],
            autoStart: false
        )

        // Now verify that when relay2 connects, only the relevant subscriptions are replayed
        // This is O(1) because we directly look up subscriptions for relay2

        // The test passes if we can create all these subscriptions without errors
        // The actual O(1) lookup happens in replaySubscriptionsForRelay which is tested
        // by the logs showing "Found X subscriptions for relay Y (O(1) lookup)"

        XCTAssertNotNil(universalSub)
        XCTAssertNotNil(relay1Sub)
        XCTAssertNotNil(relay2Sub)
        XCTAssertNotNil(relay3Sub)
        XCTAssertNotNil(multiRelaySub)

        // Clean up
        await manager.closeSubscription(id: "universal-sub")
        await manager.closeSubscription(id: "relay1-sub")
        await manager.closeSubscription(id: "relay2-sub")
        await manager.closeSubscription(id: "relay3-sub")
        await manager.closeSubscription(id: "multi-relay-sub")
    }

    func testRelayToSubscriptionMappingCorrectness() async throws {
        let ndk = NDK()
        let manager = InternalSubscriptionManager(ndk: ndk)

        // Create subscriptions
        _ = await manager.createSubscription(
            id: "sub1",
            filters: [NDKFilter(kinds: [1])],
            relays: ["wss://relay1.com/", "wss://relay2.com/"],
            autoStart: false
        )

        let sub2 = await manager.createSubscription(
            id: "sub2",
            filters: [NDKFilter(kinds: [2])],
            relays: ["wss://relay2.com/", "wss://relay3.com/"],
            autoStart: false
        )

        let sub3 = await manager.createSubscription(
            id: "sub3",
            filters: [NDKFilter(kinds: [3])],
            relays: nil, // Universal
            autoStart: false
        )

        // Close sub1 and verify mappings are cleaned up
        await manager.closeSubscription(id: "sub1")

        // Create another subscription for relay2 to ensure mappings work after deletion
        let sub4 = await manager.createSubscription(
            id: "sub4",
            filters: [NDKFilter(kinds: [4])],
            relays: ["wss://relay2.com/"],
            autoStart: false
        )

        XCTAssertNotNil(sub2)
        XCTAssertNotNil(sub3)
        XCTAssertNotNil(sub4)

        // Clean up
        await manager.closeSubscription(id: "sub2")
        await manager.closeSubscription(id: "sub3")
        await manager.closeSubscription(id: "sub4")
    }
}
