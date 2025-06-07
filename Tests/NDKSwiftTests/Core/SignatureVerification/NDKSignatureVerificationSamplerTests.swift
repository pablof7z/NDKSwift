@testable import NDKSwift
import XCTest

/// Mock delegate for testing
class MockSignatureVerificationDelegate: NDKSignatureVerificationDelegate {
    var invalidSignatureEvents: [(event: NDKEvent, relay: NDKRelay)] = []
    var blacklistedRelays: [NDKRelay] = []

    func signatureVerificationFailed(for event: NDKEvent, from relay: NDKRelay) {
        invalidSignatureEvents.append((event, relay))
    }

    func relayBlacklisted(_ relay: NDKRelay) {
        blacklistedRelays.append(relay)
    }
}

final class NDKSignatureVerificationSamplerTests: XCTestCase {
    private var mockDelegate: MockSignatureVerificationDelegate!

    override func setUp() {
        super.setUp()
        mockDelegate = MockSignatureVerificationDelegate()
    }

    // MARK: - Sampling Rate Tests

    func testInitialValidationRatio() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 0.1,
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: nil
        )

        let sampler = NDKSignatureVerificationSampler(config: config)
        let relay = NDKRelay(url: "wss://relay.example.com")

        var stats = NDKRelaySignatureStats()

        // First 10 events should all be verified (initial ratio = 1.0)
        var verifiedCount = 0
        for i in 0 ..< 10 {
            let event = createValidEvent(id: "event_\(i)")
            let result = await sampler.verifyEvent(event, from: relay, stats: &stats)

            if case .valid = result {
                verifiedCount += 1
            }
        }

        XCTAssertEqual(verifiedCount, 10, "All first 10 events should be verified with initial ratio 1.0")
        XCTAssertEqual(stats.validatedCount, 10)
        XCTAssertEqual(stats.nonValidatedCount, 0)
    }

    func testValidationRatioDecay() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 0.1,
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: nil
        )

        let sampler = NDKSignatureVerificationSampler(config: config)
        let relay = NDKRelay(url: "wss://relay.example.com")

        var stats = NDKRelaySignatureStats()

        // Verify 100 events to build trust
        for i in 0 ..< 100 {
            let event = createValidEvent(id: "trust_event_\(i)")
            _ = await sampler.verifyEvent(event, from: relay, stats: &stats)
        }

        // Now test the sampling rate on next 1000 events
        var verifiedCount = 0
        var skippedCount = 0

        for i in 0 ..< 1000 {
            let event = createValidEvent(id: "test_event_\(i)")
            let result = await sampler.verifyEvent(event, from: relay, stats: &stats)

            switch result {
            case .valid, .cached:
                verifiedCount += 1
            case .skipped:
                skippedCount += 1
            case .invalid:
                XCTFail("Should not have invalid events in this test")
            }
        }

        // The ratio should have decreased, so we should have skipped some events
        XCTAssertGreaterThan(skippedCount, 0, "Some events should have been skipped due to sampling")
        XCTAssertLessThan(skippedCount, 1000, "Not all events should be skipped")

        // The verification rate should be above the minimum (0.1 = 10%)
        let actualRate = Double(verifiedCount) / 1000.0
        XCTAssertGreaterThanOrEqual(actualRate, 0.1, "Verification rate should not go below minimum")
    }

    func testCustomValidationRatioFunction() async {
        // Custom function that always returns 0.5 (50% sampling)
        let customFunction: (NDKRelay, Int, Int) -> Double = { _, _, _ in 0.5 }

        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 0.1,
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: customFunction
        )

        let sampler = NDKSignatureVerificationSampler(config: config)
        let relay = NDKRelay(url: "wss://relay.example.com")

        var stats = NDKRelaySignatureStats()

        // Skip the first 10 events (which use initial ratio)
        for i in 0 ..< 10 {
            _ = await sampler.verifyEvent(createValidEvent(id: "init_\(i)"), from: relay, stats: &stats)
        }

        // Test next 1000 events
        var verifiedCount = 0
        for i in 0 ..< 1000 {
            let event = createValidEvent(id: "test_\(i)")
            let result = await sampler.verifyEvent(event, from: relay, stats: &stats)

            if case .valid = result {
                verifiedCount += 1
            }
        }

        // Should be roughly 50% verified
        let rate = Double(verifiedCount) / 1000.0
        XCTAssertGreaterThan(rate, 0.4, "Rate should be above 40%")
        XCTAssertLessThan(rate, 0.6, "Rate should be below 60%")
    }

    // MARK: - Invalid Signature Detection Tests

    func testInvalidSignatureDetection() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 1.0, // Always verify for this test
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )

        let sampler = NDKSignatureVerificationSampler(config: config)
        await sampler.setDelegate(mockDelegate)

        let relay = NDKRelay(url: "wss://evil.relay.com")
        var stats = NDKRelaySignatureStats()

        // Create event with invalid signature
        let event = createInvalidEvent(id: "evil_event")

        let result = await sampler.verifyEvent(event, from: relay, stats: &stats)

        XCTAssertEqual(result, .invalid, "Should detect invalid signature")

        // Wait a bit for delegate calls
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        XCTAssertEqual(mockDelegate.invalidSignatureEvents.count, 1, "Delegate should be notified")
        XCTAssertEqual(mockDelegate.blacklistedRelays.count, 1, "Relay should be blacklisted")

        // Verify relay is blacklisted
        let isBlacklisted = await sampler.isBlacklisted(relay: relay)
        XCTAssertTrue(isBlacklisted, "Relay should be blacklisted")
    }

    func testBlacklistedRelayRejection() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 1.0,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )

        let sampler = NDKSignatureVerificationSampler(config: config)
        let relay = NDKRelay(url: "wss://bad.relay.com")
        var stats = NDKRelaySignatureStats()

        // First, get the relay blacklisted with an invalid event
        let invalidEvent = createInvalidEvent(id: "invalid")
        _ = await sampler.verifyEvent(invalidEvent, from: relay, stats: &stats)

        // Now try a valid event from the same relay
        let validEvent = createValidEvent(id: "valid")
        let result = await sampler.verifyEvent(validEvent, from: relay, stats: &stats)

        XCTAssertEqual(result, .invalid, "Blacklisted relay's events should always be invalid")
    }

    // MARK: - Cache Tests

    func testSignatureCaching() async {
        let config = NDKSignatureVerificationConfig.default
        let sampler = NDKSignatureVerificationSampler(config: config)

        let relay1 = NDKRelay(url: "wss://relay1.com")
        let relay2 = NDKRelay(url: "wss://relay2.com")

        var stats1 = NDKRelaySignatureStats()
        var stats2 = NDKRelaySignatureStats()

        let event = createValidEvent(id: "cached_event")

        // First verification
        let result1 = await sampler.verifyEvent(event, from: relay1, stats: &stats1)
        XCTAssertEqual(result1, .valid, "First verification should be valid")

        // Second verification from different relay should use cache
        let result2 = await sampler.verifyEvent(event, from: relay2, stats: &stats2)
        XCTAssertEqual(result2, .cached, "Second verification should use cache")
    }

    func testClearCache() async {
        let config = NDKSignatureVerificationConfig.default
        let sampler = NDKSignatureVerificationSampler(config: config)

        let relay = NDKRelay(url: "wss://relay.com")
        var stats = NDKRelaySignatureStats()

        let event = createValidEvent(id: "cache_test")

        // Verify and cache
        _ = await sampler.verifyEvent(event, from: relay, stats: &stats)

        // Clear cache
        await sampler.clearCache()

        // Verify again - should not be cached
        let result = await sampler.verifyEvent(event, from: relay, stats: &stats)
        XCTAssertNotEqual(result, .cached, "Should not use cache after clearing")
    }

    // MARK: - Statistics Tests

    func testStatisticsTracking() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 1.0,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )

        let sampler = NDKSignatureVerificationSampler(config: config)

        let relay1 = NDKRelay(url: "wss://good.relay.com")
        let relay2 = NDKRelay(url: "wss://evil.relay.com")

        var stats1 = NDKRelaySignatureStats()
        var stats2 = NDKRelaySignatureStats()

        // Verify some valid events
        for i in 0 ..< 5 {
            _ = await sampler.verifyEvent(createValidEvent(id: "valid_\(i)"), from: relay1, stats: &stats1)
        }

        // Try an invalid event
        _ = await sampler.verifyEvent(createInvalidEvent(id: "invalid"), from: relay2, stats: &stats2)

        let stats = await sampler.getStats()
        XCTAssertEqual(stats.totalVerifications, 5, "Should have 5 successful verifications")
        XCTAssertEqual(stats.failedVerifications, 1, "Should have 1 failed verification")
        XCTAssertEqual(stats.blacklistedRelays, 1, "Should have 1 blacklisted relay")
    }

    // MARK: - Helper Methods

    private func createValidEvent(id: String) -> NDKEvent {
        let privateKey = Crypto.generatePrivateKey()
        let publicKey = try! Crypto.getPublicKey(from: privateKey)

        let event = NDKEvent(
            pubkey: publicKey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test event \(id)"
        )

        // Generate proper ID and signature
        event.id = try! event.generateID()
        let messageData = Data(hexString: event.id!)!
        event.sig = try! Crypto.sign(message: messageData, privateKey: privateKey)

        return event
    }

    private func createInvalidEvent(id: String) -> NDKEvent {
        let event = NDKEvent(
            pubkey: "invalid_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Invalid event \(id)"
        )

        event.id = "invalid_id_\(id)"
        event.sig = "invalid_signature"

        return event
    }
}
