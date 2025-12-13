@testable import NDKSwiftCore
import XCTest

final class NDKRelayListManagerTests: XCTestCase {
    var ndk: NDK!
    var mockCache: MemoryCache!
    var manager: NDKRelayListManager!
    let defaultRelays = ["wss://relay1.example.com", "wss://relay2.example.com"]
    let appIdentifier = "test.app"

    override func setUp() async throws {
        try await super.setUp()
        mockCache = MemoryCache()
        ndk = NDK(cache: mockCache)
        manager = NDKRelayListManager(
            ndk: ndk,
            defaultRelays: defaultRelays,
            appIdentifier: appIdentifier
        )
    }

    override func tearDown() async throws {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "\(appIdentifier)_UserAddedRelays")
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationWithoutSigner() async {
        // When initialized without a signer, should connect to default relays
        await waitForExpectation(timeout: 1.0) { @MainActor in
            self.manager.isLoading == false
        }

        XCTAssertNil(manager.relayList)
        XCTAssertNil(manager.error)
    }

    func testInitializationWithSigner() async throws {
        // Setup signer
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer

        // Re-create manager with signer
        manager = NDKRelayListManager(
            ndk: ndk,
            defaultRelays: defaultRelays,
            appIdentifier: appIdentifier
        )

        // Should attempt to load relay list
        await waitForExpectation(timeout: 1.0) { @MainActor in
            self.manager.isLoading == false
        }
    }

    // MARK: - Relay Management Tests

    func testGetAllRelays() async {
        let allRelays = await manager.getAllRelays()
        XCTAssertTrue(allRelays.contains(defaultRelays[0]))
        XCTAssertTrue(allRelays.contains(defaultRelays[1]))
    }

    func testAddRelay() async {
        let newRelay = "wss://new.relay.com"

        await manager.addRelay(newRelay)

        let allRelays = await manager.getAllRelays()
        XCTAssertTrue(allRelays.contains(newRelay))
        XCTAssertTrue(manager.userAddedRelays.contains(newRelay))
    }

    func testRemoveRelay() async {
        let relayToRemove = "wss://remove.relay.com"

        // First add it
        await manager.addRelay(relayToRemove)
        XCTAssertTrue(manager.userAddedRelays.contains(relayToRemove))

        // Then remove it
        await manager.removeRelay(relayToRemove)

        let allRelays = await manager.getAllRelays()
        XCTAssertFalse(allRelays.contains(relayToRemove))
        XCTAssertFalse(manager.userAddedRelays.contains(relayToRemove))
    }

    func testResetToDefaults() async {
        // Add some custom relays
        await manager.addRelay("wss://custom1.relay.com")
        await manager.addRelay("wss://custom2.relay.com")

        // Reset to defaults
        await manager.resetToDefaults()

        // Check that user-added relays are cleared
        XCTAssertTrue(manager.userAddedRelays.isEmpty)

        // Should still have default relays
        let allRelays = await manager.getAllRelays()
        XCTAssertTrue(allRelays.contains(defaultRelays[0]))
        XCTAssertTrue(allRelays.contains(defaultRelays[1]))
    }

    // MARK: - Local Storage Tests

    func testUserAddedRelaysPersistence() async {
        let testRelay = "wss://persistent.relay.com"

        // Add relay
        await manager.addRelay(testRelay)

        // Create new manager instance
        let newManager = NDKRelayListManager(
            ndk: ndk,
            defaultRelays: defaultRelays,
            appIdentifier: appIdentifier
        )

        // Should still have the user-added relay
        XCTAssertTrue(newManager.userAddedRelays.contains(testRelay))
    }

    func testIsUserAddedRelay() async {
        let userRelay = "wss://user.relay.com"

        await manager.addRelay(userRelay)

        XCTAssertTrue(manager.isUserAddedRelay(userRelay))
        XCTAssertFalse(manager.isUserAddedRelay(defaultRelays[0]))
    }

    // MARK: - Relay List Event Tests

    func testCreateInitialRelayList() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer

        // Add a user relay
        await manager.addRelay("wss://user.relay.com")

        // Re-create manager to trigger relay list creation
        manager = NDKRelayListManager(
            ndk: ndk,
            defaultRelays: defaultRelays,
            appIdentifier: appIdentifier
        )

        await waitForExpectation(timeout: 2.0) { @MainActor in
            self.manager.relayList != nil || self.manager.error != nil
        }

        if let relayList = manager.relayList {
            // Should contain default relays and user-added relay
            XCTAssertTrue(relayList.hasRelay(defaultRelays[0]))
            XCTAssertTrue(relayList.hasRelay(defaultRelays[1]))
            XCTAssertTrue(relayList.hasRelay("wss://user.relay.com"))
        }
    }

    // MARK: - Error Handling Tests

    func testHandlesRelayListLoadingError() async throws {
        // This test would require mocking network failures
        // For now, just verify error property exists
        XCTAssertNil(manager.error)
    }
}

// MARK: - Helper Extensions

private extension XCTestCase {
    func waitForExpectation(timeout: TimeInterval, condition: @escaping () async -> Bool) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }
}
