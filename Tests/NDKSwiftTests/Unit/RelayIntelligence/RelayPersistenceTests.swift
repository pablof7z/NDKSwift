import XCTest
@testable import NDKSwiftCore

final class RelayPersistenceTests: XCTestCase {
    // MARK: - Relay Persistence Tests

    func test_relay_isPersistent_defaultsFalse() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let isPersistent = await relay.isPersistent
        XCTAssertFalse(isPersistent)
    }

    func test_relay_isPersistent_canBeSet() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        await relay.setPersistent(true)
        let isPersistent = await relay.isPersistent
        XCTAssertTrue(isPersistent)
    }

    func test_pool_explicitRelays_arePersistent() async {
        let ndk = NDK()
        let relay = await ndk.pool.addRelay("wss://relay.example.com", origin: .appRelays)
        let isPersistent = await relay.isPersistent
        XCTAssertTrue(isPersistent)
    }

    func test_pool_discoveryRelays_areNotPersistent() async {
        let ndk = NDK()
        let relay = await ndk.pool.addRelay("wss://relay.example.com", origin: .outbox(authorPubkey: "test"))
        let isPersistent = await relay.isPersistent
        XCTAssertFalse(isPersistent)
    }

    func test_pool_outboxConfigRelays_arePersistent() async {
        let ndk = NDK()
        let relay = await ndk.pool.addRelay("wss://relay.example.com", origin: .discovery)
        let isPersistent = await relay.isPersistent
        XCTAssertTrue(isPersistent)
    }
}
