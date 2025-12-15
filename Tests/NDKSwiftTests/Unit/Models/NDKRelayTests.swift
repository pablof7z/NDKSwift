@testable import NDKSwiftCore
import XCTest

// Helper actor for thread-safe state collection
private actor StateCollector {
    private var states: [NDKRelayConnectionState] = []

    func append(_ state: NDKRelayConnectionState) {
        states.append(state)
    }

    func getStates() -> [NDKRelayConnectionState] {
        return states
    }
}

final class NDKRelayTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitialization() {
        let relay = NDKRelay(url: "wss://relay.example.com")

        XCTAssertEqual(relay.url, "wss://relay.example.com")
        XCTAssertNotNil(relay.subscriptionManager)
    }

    func testNormalizedURL() {
        let testCases = [
            ("wss://relay.example.com", "wss://relay.example.com/"),
            ("wss://relay.example.com/", "wss://relay.example.com/"),
            ("wss://RELAY.EXAMPLE.COM", "wss://relay.example.com/"),
            ("wss://relay.example.com:8080", "wss://relay.example.com:8080/"),
            ("wss://relay.example.com/path", "wss://relay.example.com/path/"),
        ]

        for (input, expected) in testCases {
            let relay = NDKRelay(url: input)
            XCTAssertEqual(relay.normalizedURL, expected, "Failed for input: \(input)")
        }
    }

    // MARK: - State Management Tests

    func testInitialState() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        let state = await relay.connectionState
        XCTAssertEqual(state, .disconnected)

        let isConnected = await relay.isConnected
        XCTAssertFalse(isConnected)

        let isAuthenticated = await relay.isAuthenticated
        XCTAssertFalse(isAuthenticated)

        let origin = await relay.origin
        XCTAssertEqual(origin, .explicit)
    }

    func testSetOrigin() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        await relay.setOrigin(.outbox(authorPubkey: "test-pubkey"))
        let origin = await relay.origin
        XCTAssertEqual(origin, .outbox(authorPubkey: "test-pubkey"))

        await relay.setOrigin(.outboxConfig)
        let origin2 = await relay.origin
        XCTAssertEqual(origin2, .outboxConfig)
    }

    func testConnectionStateObserver() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let expectation = XCTestExpectation(description: "State observer called")
        expectation.expectedFulfillmentCount = 2 // Initial call + state change

        let statesActor = StateCollector()

        await relay.observeConnectionState { state in
            Task {
                await statesActor.append(state)
                expectation.fulfill()
            }
        }

        // Should immediately receive current state
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Update state
        await relay.updateConnectionState(.connecting)

        await fulfillment(of: [expectation], timeout: 1.0)

        let receivedStates = await statesActor.getStates()
        XCTAssertEqual(receivedStates.count, 2)
        XCTAssertEqual(receivedStates[0], .disconnected)
        XCTAssertEqual(receivedStates[1], .connecting)
    }

    func testStateStream() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        let expectation = XCTestExpectation(description: "State stream emits values")
        expectation.expectedFulfillmentCount = 2

        let task = Task {
            var states: [NDKRelay.State] = []
            for await state in relay.stateStream {
                states.append(state)
                expectation.fulfill()
                if states.count >= 2 {
                    break
                }
            }
            return states
        }

        // Give stream time to setup
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Update state to trigger new emission
        await relay.updateConnectionState(.connected)

        await fulfillment(of: [expectation], timeout: 1.0)

        let states = await task.value
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].connectionState, .disconnected)
        XCTAssertEqual(states[1].connectionState, .connected)

        task.cancel()
    }

    // MARK: - Connection State Tests

    func testIsConnected() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        // Test disconnected state
        let isConnected1 = await relay.isConnected
        XCTAssertFalse(isConnected1)

        // Test connected state
        await relay.updateConnectionState(.connected)
        let isConnected2 = await relay.isConnected
        XCTAssertTrue(isConnected2)

        // Test authenticated state (also considered connected)
        await relay.updateConnectionState(.authenticated)
        let isConnected3 = await relay.isConnected
        XCTAssertTrue(isConnected3)

        // Test other states
        await relay.updateConnectionState(.connecting)
        let isConnected4 = await relay.isConnected
        XCTAssertFalse(isConnected4)

        await relay.updateConnectionState(.failed("test error"))
        let isConnected5 = await relay.isConnected
        XCTAssertFalse(isConnected5)
    }

    func testIsAuthenticated() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        // Test non-authenticated states
        let isAuth1 = await relay.isAuthenticated
        XCTAssertFalse(isAuth1)

        await relay.updateConnectionState(.connected)
        let isAuth2 = await relay.isAuthenticated
        XCTAssertFalse(isAuth2)

        // Test authenticated state
        await relay.updateConnectionState(.authenticated)
        let isAuth3 = await relay.isAuthenticated
        XCTAssertTrue(isAuth3)

        // Test auth required state
        await relay.updateConnectionState(.authRequired(challenge: "test-challenge"))
        let isAuth4 = await relay.isAuthenticated
        XCTAssertFalse(isAuth4)
    }

    // MARK: - NDK Reference Tests

    func testNDKReference() async {
        // Create relay through pool to have proper ndk reference
        let ndk = NDK(relayURLs: [])
        let relay = await ndk.pool.addRelay("wss://relay.example.com")

        // Relay should have ndk reference when added through pool
        let relayNDK = await relay.ndk
        XCTAssertNotNil(relayNDK)
    }

    // MARK: - Statistics Tests

    func testInitialStats() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let stats = await relay.stats

        XCTAssertNil(stats.connectedAt)
        XCTAssertNil(stats.lastMessageAt)
        XCTAssertEqual(stats.messagesSent, 0)
        XCTAssertEqual(stats.messagesReceived, 0)
        XCTAssertEqual(stats.bytesReceived, 0)
        XCTAssertEqual(stats.bytesSent, 0)
        XCTAssertNil(stats.latency)
        XCTAssertEqual(stats.connectionAttempts, 0)
        XCTAssertEqual(stats.successfulConnections, 0)
    }

    func testUpdateSignatureStats() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        await relay.updateSignatureStats { stats in
            stats.addValidatedEvent()
            stats.addValidatedEvent()
            stats.addValidatedEvent()
            stats.addNonValidatedEvent()
            stats.updateValidationRatio(0.75)
        }

        let stats = await relay.getSignatureStats()
        XCTAssertEqual(stats.validatedCount, 3)
        XCTAssertEqual(stats.nonValidatedCount, 1)
        XCTAssertEqual(stats.totalEvents, 4)
        XCTAssertEqual(stats.currentValidationRatio, 0.75)
    }

    // MARK: - Subscription Management Tests

    func testSubscriptionTracking() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        // Initially no subscriptions
        var subs = await relay.activeSubscriptions
        XCTAssertTrue(subs.isEmpty)

        // Track a subscription
        let filters = [NDKFilter(kinds: [EventKind.metadata])]
        await relay.trackSubscription(id: "sub1", filters: filters)

        subs = await relay.activeSubscriptions
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].id, "sub1")
        XCTAssertEqual(subs[0].filters, filters)
        XCTAssertEqual(subs[0].eventCount, 0)

        // Increment event count
        await relay.incrementSubscriptionEventCount(id: "sub1")

        subs = await relay.activeSubscriptions
        XCTAssertEqual(subs[0].eventCount, 1)
        XCTAssertNotNil(subs[0].lastEventAt)

        // Untrack subscription
        await relay.untrackSubscription(id: "sub1")

        subs = await relay.activeSubscriptions
        XCTAssertTrue(subs.isEmpty)
    }

    // MARK: - Relay Information Tests

    func testRelayInfo() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        // Initially nil
        let info = await relay.info
        XCTAssertNil(info)

        // Can't easily test setting info without exposing internal methods
        // This would be set by fetchRelayInformation() after connection
    }

    // MARK: - Equatable and Hashable Tests

    func testEquatable() {
        let relay1 = NDKRelay(url: "wss://relay.example.com")
        let relay2 = NDKRelay(url: "wss://relay.example.com/")
        let relay3 = NDKRelay(url: "wss://other.example.com")

        XCTAssertEqual(relay1, relay2) // Same normalized URL
        XCTAssertNotEqual(relay1, relay3) // Different URL
    }

    func testHashable() {
        let relay1 = NDKRelay(url: "wss://relay.example.com")
        let relay2 = NDKRelay(url: "wss://relay.example.com/")
        let relay3 = NDKRelay(url: "wss://other.example.com")

        var relaySet = Set<NDKRelay>()
        relaySet.insert(relay1)
        relaySet.insert(relay2) // Should not increase count (same normalized URL)
        relaySet.insert(relay3)

        XCTAssertEqual(relaySet.count, 2)
        XCTAssertTrue(relaySet.contains(relay1))
        XCTAssertTrue(relaySet.contains(relay2))
        XCTAssertTrue(relaySet.contains(relay3))
    }

    // MARK: - Supporting Type Tests

    func testNDKRelayOrigin() {
        let explicit = NDKRelayOrigin.explicit
        let outbox = NDKRelayOrigin.outbox(authorPubkey: "test-pubkey")
        let outboxConfig = NDKRelayOrigin.outboxConfig

        // Test equality
        XCTAssertEqual(explicit, .explicit)
        XCTAssertEqual(outbox, .outbox(authorPubkey: "test-pubkey"))
        XCTAssertNotEqual(outbox, .outbox(authorPubkey: "different-pubkey"))
        XCTAssertEqual(outboxConfig, .outboxConfig)

        // Test different origins are not equal
        XCTAssertNotEqual(explicit, outbox)
        XCTAssertNotEqual(explicit, outboxConfig)
        XCTAssertNotEqual(outbox, outboxConfig)
    }

    func testNDKRelayInfo() {
        let info1 = NDKRelayInfo(url: "wss://relay.example.com", read: true, write: true)
        let info2 = NDKRelayInfo(url: "wss://relay.example.com", read: true, write: false)
        let info3 = NDKRelayInfo(url: "wss://relay.example.com")

        XCTAssertEqual(info1.url, "wss://relay.example.com")
        XCTAssertTrue(info1.read)
        XCTAssertTrue(info1.write)

        XCTAssertTrue(info2.read)
        XCTAssertFalse(info2.write)

        // Test defaults
        XCTAssertTrue(info3.read)
        XCTAssertTrue(info3.write)

        // Test equality
        XCTAssertNotEqual(info1, info2)
        XCTAssertEqual(info1, info3) // Same values despite different init
    }

    func testNDKRelayConnectionState() {
        // Test equality
        XCTAssertEqual(NDKRelayConnectionState.disconnected, .disconnected)
        XCTAssertEqual(NDKRelayConnectionState.connecting, .connecting)
        XCTAssertEqual(NDKRelayConnectionState.connected, .connected)
        XCTAssertEqual(NDKRelayConnectionState.authenticating, .authenticating)
        XCTAssertEqual(NDKRelayConnectionState.authenticated, .authenticated)
        XCTAssertEqual(NDKRelayConnectionState.disconnecting, .disconnecting)

        // Test auth required with same challenge
        XCTAssertEqual(
            NDKRelayConnectionState.authRequired(challenge: "test"),
            .authRequired(challenge: "test")
        )

        // Test auth required with different challenge
        XCTAssertNotEqual(
            NDKRelayConnectionState.authRequired(challenge: "test1"),
            .authRequired(challenge: "test2")
        )

        // Test failed with same message
        XCTAssertEqual(
            NDKRelayConnectionState.failed("error"),
            .failed("error")
        )

        // Test failed with different message
        XCTAssertNotEqual(
            NDKRelayConnectionState.failed("error1"),
            .failed("error2")
        )

        // Test different states are not equal
        XCTAssertNotEqual(NDKRelayConnectionState.disconnected, .connected)
        XCTAssertNotEqual(NDKRelayConnectionState.connected, .authenticated)
    }

    func testNDKRelayStats() {
        let date = Date()
        let stats = NDKRelayStats(
            connectedAt: date,
            lastMessageAt: date,
            messagesSent: 10,
            messagesReceived: 20,
            bytesReceived: 1000,
            bytesSent: 500,
            latency: 0.05,
            connectionAttempts: 2,
            successfulConnections: 1
        )

        XCTAssertEqual(stats.connectedAt, date)
        XCTAssertEqual(stats.lastMessageAt, date)
        XCTAssertEqual(stats.messagesSent, 10)
        XCTAssertEqual(stats.messagesReceived, 20)
        XCTAssertEqual(stats.bytesReceived, 1000)
        XCTAssertEqual(stats.bytesSent, 500)
        XCTAssertEqual(stats.latency, 0.05)
        XCTAssertEqual(stats.connectionAttempts, 2)
        XCTAssertEqual(stats.successfulConnections, 1)

        // Test default init
        let defaultStats = NDKRelayStats()
        XCTAssertNil(defaultStats.connectedAt)
        XCTAssertNil(defaultStats.lastMessageAt)
        XCTAssertEqual(defaultStats.messagesSent, 0)
    }

    func testNDKRelaySubscriptionInfo() {
        let filters = [NDKFilter(kinds: [EventKind.metadata])]
        let createdAt = Date()
        var info = NDKRelaySubscriptionInfo(id: "sub1", filters: filters, createdAt: createdAt)

        XCTAssertEqual(info.id, "sub1")
        XCTAssertEqual(info.filters, filters)
        XCTAssertEqual(info.createdAt, createdAt)
        XCTAssertEqual(info.eventCount, 0)
        XCTAssertNil(info.lastEventAt)

        // Test mutating
        info.eventCount = 5
        info.lastEventAt = Date()

        XCTAssertEqual(info.eventCount, 5)
        XCTAssertNotNil(info.lastEventAt)
    }

    func testRelayState() {
        let stats = NDKRelayStats()
        let info = NDKRelayInformation(
            name: "Test Relay",
            description: nil,
            banner: nil,
            icon: nil,
            pubkey: nil,
            contact: nil,
            supportedNips: [1, 2, 9],
            software: "test",
            version: "1.0",
            limitation: nil,
            retention: nil,
            relayCountries: nil,
            languageTags: nil,
            tags: nil,
            postingPolicy: nil,
            paymentsUrl: nil,
            fees: nil
        )
        let subscriptions = [NDKRelaySubscriptionInfo(id: "sub1", filters: [])]

        let state = NDKRelay.State(
            connectionState: .connected,
            stats: stats,
            info: info,
            activeSubscriptions: subscriptions
        )

        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertEqual(state.stats, stats)
        XCTAssertEqual(state.info, info)
        XCTAssertEqual(state.activeSubscriptions, subscriptions)
    }

    // MARK: - Relay Information Types Tests

    func testRelayLimitation() {
        let limitation = RelayLimitation(
            maxMessageLength: 65536,
            maxSubscriptions: 20,
            maxFilters: 10,
            maxLimit: 5000,
            maxSubidLength: 64,
            maxEventTags: 100,
            maxContentLength: 8192,
            minPowDifficulty: 0,
            authRequired: false,
            paymentRequired: false,
            restrictedWrites: false
        )

        XCTAssertEqual(limitation.maxMessageLength, 65536)
        XCTAssertEqual(limitation.maxSubscriptions, 20)
        XCTAssertEqual(limitation.maxFilters, 10)
        XCTAssertEqual(limitation.maxLimit, 5000)
        XCTAssertEqual(limitation.maxSubidLength, 64)
        XCTAssertEqual(limitation.maxEventTags, 100)
        XCTAssertEqual(limitation.maxContentLength, 8192)
        XCTAssertEqual(limitation.minPowDifficulty, 0)
        XCTAssertFalse(limitation.authRequired ?? true)
        XCTAssertFalse(limitation.paymentRequired ?? true)
        XCTAssertFalse(limitation.restrictedWrites ?? true)
    }

    func testRelayRetention() {
        let retention = RelayRetention(
            kinds: [0, 1, 3],
            time: 3600,
            count: 1000
        )

        XCTAssertEqual(retention.kinds, [0, 1, 3])
        XCTAssertEqual(retention.time, 3600)
        XCTAssertEqual(retention.count, 1000)
    }

    func testRelayFees() {
        let admission = RelayFee(amount: 1000, unit: "msats", period: 86400, kinds: nil)
        let publication = RelayFee(amount: 21, unit: "msats", period: nil, kinds: [1, 4])

        let fees = RelayFees(
            admission: [admission],
            publication: [publication]
        )

        XCTAssertEqual(fees.admission?.count, 1)
        XCTAssertEqual(fees.admission?[0].amount, 1000)
        XCTAssertEqual(fees.admission?[0].unit, "msats")
        XCTAssertEqual(fees.admission?[0].period, 86400)

        XCTAssertEqual(fees.publication?.count, 1)
        XCTAssertEqual(fees.publication?[0].amount, 21)
        XCTAssertEqual(fees.publication?[0].kinds, [1, 4])
    }

    func testNDKRelayInformation() {
        let limitation = RelayLimitation(
            maxMessageLength: 65536,
            maxSubscriptions: nil,
            maxFilters: nil,
            maxLimit: nil,
            maxSubidLength: nil,
            maxEventTags: nil,
            maxContentLength: nil,
            minPowDifficulty: nil,
            authRequired: true,
            paymentRequired: nil,
            restrictedWrites: nil
        )

        let info = NDKRelayInformation(
            name: "Test Relay",
            description: "A test relay",
            banner: "https://example.com/banner.jpg",
            icon: "https://example.com/icon.png",
            pubkey: "test-pubkey",
            contact: "admin@example.com",
            supportedNips: [1, 2, 9, 11, 12],
            software: "test-relay",
            version: "1.0.0",
            limitation: limitation,
            retention: nil,
            relayCountries: ["US", "EU"],
            languageTags: ["en", "es"],
            tags: ["public", "paid"],
            postingPolicy: "https://example.com/policy",
            paymentsUrl: "https://example.com/pay",
            fees: nil
        )

        XCTAssertEqual(info.name, "Test Relay")
        XCTAssertEqual(info.description, "A test relay")
        XCTAssertEqual(info.supportedNips, [1, 2, 9, 11, 12])
        XCTAssertEqual(info.software, "test-relay")
        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertEqual(info.limitation?.authRequired, true)
        XCTAssertEqual(info.relayCountries, ["US", "EU"])
        XCTAssertEqual(info.languageTags, ["en", "es"])
        XCTAssertEqual(info.tags, ["public", "paid"])
    }

    // MARK: - Codable Tests

    func testNDKRelayOriginCodable() throws {
        let testCases: [NDKRelayOrigin] = [
            .explicit,
            .outbox(authorPubkey: "test-pubkey"),
            .outboxConfig,
        ]

        for origin in testCases {
            let encoded = try JSONEncoder().encode(origin)
            let decoded = try JSONDecoder().decode(NDKRelayOrigin.self, from: encoded)
            XCTAssertEqual(origin, decoded)
        }
    }

    func testNDKRelayInfoCodable() throws {
        let info = NDKRelayInfo(url: "wss://relay.example.com", read: true, write: false)

        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(NDKRelayInfo.self, from: encoded)

        XCTAssertEqual(info, decoded)
    }

    func testNDKRelayConnectionStateCodable() throws {
        let testCases: [NDKRelayConnectionState] = [
            .disconnected,
            .connecting,
            .connected,
            .authRequired(challenge: "test-challenge"),
            .authenticating,
            .authenticated,
            .disconnecting,
            .failed("test error"),
        ]

        for state in testCases {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(NDKRelayConnectionState.self, from: encoded)
            XCTAssertEqual(state, decoded)
        }
    }
}
