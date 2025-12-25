import XCTest
@testable import NDKSwiftCore

final class IdleRelayEvictionTests: XCTestCase {
    // MARK: - Idle Relay Eviction Tests

    func test_pool_evictIdleRelays_removesNonPersistentIdleRelays() async {
        let ndk = NDK()

        // Add a non-persistent relay (outbox origin)
        let relay = await ndk.pool.addRelay("wss://idle-relay.example.com", origin: .outbox(authorPubkey: "test"))

        // Verify relay is in pool
        let initialCount = await ndk.pool.relays.count
        XCTAssertEqual(initialCount, 1)

        // Evict with 0 second threshold (all idle relays should be evicted)
        let evicted = await ndk.pool.evictIdleRelays(idleThreshold: 0)

        // Should have evicted the relay
        XCTAssertEqual(evicted.count, 1)
        XCTAssertEqual(evicted.first, relay.url)

        // Pool should be empty
        let finalCount = await ndk.pool.relays.count
        XCTAssertEqual(finalCount, 0)
    }

    func test_pool_evictIdleRelays_preservesPersistentRelays() async {
        let ndk = NDK()

        // Add a persistent relay (explicit origin)
        _ = await ndk.pool.addRelay("wss://explicit-relay.example.com", origin: .appRelays)

        // Evict with 0 second threshold
        let evicted = await ndk.pool.evictIdleRelays(idleThreshold: 0)

        // Should NOT have evicted the persistent relay
        XCTAssertEqual(evicted.count, 0)

        // Relay should still be in pool
        let finalCount = await ndk.pool.relays.count
        XCTAssertEqual(finalCount, 1)
    }

    func test_pool_evictIdleRelays_respectsIdleThreshold() async {
        let ndk = NDK()

        // Add a non-persistent relay
        let relay = await ndk.pool.addRelay("wss://active-relay.example.com", origin: .outbox(authorPubkey: "test"))

        // Record activity
        await relay.recordActivity()

        // Evict with 1 hour threshold (relay is recently active)
        let evicted = await ndk.pool.evictIdleRelays(idleThreshold: 3600)

        // Should NOT have evicted (relay was just active)
        XCTAssertEqual(evicted.count, 0)

        // Relay should still be in pool
        let finalCount = await ndk.pool.relays.count
        XCTAssertEqual(finalCount, 1)
    }

    func test_pool_evictIdleRelays_evictsMixedPool() async {
        let ndk = NDK()

        // Add persistent relay
        _ = await ndk.pool.addRelay("wss://persistent.example.com", origin: .appRelays)

        // Add non-persistent idle relay
        _ = await ndk.pool.addRelay("wss://idle.example.com", origin: .outbox(authorPubkey: "test1"))

        // Add non-persistent active relay
        let activeRelay = await ndk.pool.addRelay("wss://active.example.com", origin: .outbox(authorPubkey: "test2"))
        await activeRelay.recordActivity()

        // Evict with 1 hour threshold
        let evicted = await ndk.pool.evictIdleRelays(idleThreshold: 3600)

        // Should only evict the idle non-persistent relay
        XCTAssertEqual(evicted.count, 1)
        XCTAssertTrue(evicted.contains("wss://idle.example.com/"))

        // Should have 2 relays remaining (persistent + active)
        let finalCount = await ndk.pool.relays.count
        XCTAssertEqual(finalCount, 2)
    }
}
