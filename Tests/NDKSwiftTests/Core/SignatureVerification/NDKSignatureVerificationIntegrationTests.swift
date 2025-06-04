import XCTest
@testable import NDKSwift

final class NDKSignatureVerificationIntegrationTests: XCTestCase {
    
    private var ndk: NDK!
    private var mockDelegate: MockSignatureVerificationDelegate!
    
    override func setUp() async throws {
        try await super.setUp()
        mockDelegate = MockSignatureVerificationDelegate()
    }
    
    override func tearDown() async throws {
        if ndk != nil {
            await ndk.disconnect()
        }
        ndk = nil
        mockDelegate = nil
        try await super.tearDown()
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() async {
        ndk = NDK(signatureVerificationConfig: .default)
        
        XCTAssertEqual(ndk.signatureVerificationConfig.initialValidationRatio, 1.0)
        XCTAssertEqual(ndk.signatureVerificationConfig.lowestValidationRatio, 0.1)
        XCTAssertFalse(ndk.signatureVerificationConfig.autoBlacklistInvalidRelays)
    }
    
    func testDisabledConfiguration() async {
        ndk = NDK(signatureVerificationConfig: .disabled)
        
        XCTAssertEqual(ndk.signatureVerificationConfig.initialValidationRatio, 0.0)
        XCTAssertEqual(ndk.signatureVerificationConfig.lowestValidationRatio, 0.0)
        
        // With disabled config, all events should be skipped
        let relay = ndk.addRelay("wss://relay.example.com")
        let event = createTestEvent()
        
        // Process event
        ndk.processEvent(event, from: relay)
        
        // Give it time to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Check relay stats
        let stats = relay.getSignatureStats()
        XCTAssertEqual(stats.validatedCount, 0, "No events should be validated with disabled config")
    }
    
    func testCustomConfiguration() async {
        let customConfig = NDKSignatureVerificationConfig(
            initialValidationRatio: 0.5,
            lowestValidationRatio: 0.2,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: { _, validatedCount, _ in
                // Simple linear decay
                return max(0.2, 1.0 - (Double(validatedCount) * 0.01))
            }
        )
        
        ndk = NDK(signatureVerificationConfig: customConfig)
        await ndk.setSignatureVerificationDelegate(mockDelegate)
        
        let relay = ndk.addRelay("wss://test.relay.com")
        
        // Process many valid events
        for i in 0..<100 {
            let event = createTestEvent(id: "event_\(i)")
            ndk.processEvent(event, from: relay)
        }
        
        // Give time to process
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let stats = relay.getSignatureStats()
        let totalEvents = stats.validatedCount + stats.nonValidatedCount
        
        XCTAssertEqual(totalEvents, 100, "Should have processed 100 events")
        XCTAssertGreaterThan(stats.nonValidatedCount, 0, "Some events should have been skipped")
    }
    
    // MARK: - Relay Blacklisting Tests
    
    func testRelayBlacklistingOnInvalidSignature() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 1.0,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )
        
        ndk = NDK(signatureVerificationConfig: config)
        await ndk.setSignatureVerificationDelegate(mockDelegate)
        
        let evilRelay = ndk.addRelay("wss://evil.relay.com")
        
        // Send event with invalid signature
        let invalidEvent = createInvalidEvent()
        ndk.processEvent(invalidEvent, from: evilRelay)
        
        // Give time to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Check if relay was blacklisted
        let isBlacklisted = await ndk.isRelayBlacklisted(evilRelay)
        XCTAssertTrue(isBlacklisted, "Relay should be blacklisted after invalid signature")
        
        // Check delegate was called
        XCTAssertEqual(mockDelegate.invalidSignatureEvents.count, 1)
        XCTAssertEqual(mockDelegate.blacklistedRelays.count, 1)
        
        // Check blacklisted relays list
        let blacklistedRelays = await ndk.getBlacklistedRelays()
        XCTAssertTrue(blacklistedRelays.contains(evilRelay.url))
    }
    
    func testBlacklistedRelayEventsIgnored() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 1.0,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )
        
        ndk = NDK(signatureVerificationConfig: config)
        
        let relay = ndk.addRelay("wss://bad.relay.com")
        
        // Create subscription to track received events
        var receivedEvents: [NDKEvent] = []
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        subscription.onEvent = { event in
            receivedEvents.append(event)
        }
        subscription.start()
        
        // Send invalid event to get relay blacklisted
        let invalidEvent = createInvalidEvent()
        ndk.processEvent(invalidEvent, from: relay)
        
        // Wait for blacklisting
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Now send valid events from the blacklisted relay
        for i in 0..<5 {
            let validEvent = createTestEvent(id: "valid_\(i)")
            ndk.processEvent(validEvent, from: relay)
        }
        
        // Wait for processing
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // No events should have been received from the blacklisted relay
        XCTAssertEqual(receivedEvents.count, 0, "No events should be received from blacklisted relay")
        
        subscription.stop()
    }
    
    // MARK: - Performance Tests
    
    func testSignatureVerificationPerformance() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 0.05, // 5% minimum
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: nil
        )
        
        ndk = NDK(signatureVerificationConfig: config)
        let relay = ndk.addRelay("wss://perf.relay.com")
        
        let startTime = Date()
        
        // Process 1000 events
        for i in 0..<1000 {
            let event = createTestEvent(id: "perf_\(i)")
            ndk.processEvent(event, from: relay)
        }
        
        // Wait for all to process
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let endTime = Date()
        let elapsed = endTime.timeIntervalSince(startTime)
        
        print("Processed 1000 events in \(elapsed) seconds")
        
        let stats = relay.getSignatureStats()
        let verificationRate = Double(stats.validatedCount) / 1000.0
        
        print("Verified \(stats.validatedCount) events (\(verificationRate * 100)%)")
        print("Skipped \(stats.nonValidatedCount) events")
        
        XCTAssertLessThan(elapsed, 3.0, "Should process 1000 events in under 3 seconds")
        XCTAssertGreaterThan(stats.nonValidatedCount, 0, "Should have skipped some events for performance")
    }
    
    // MARK: - Statistics Tests
    
    func testSignatureVerificationStatistics() async {
        let config = NDKSignatureVerificationConfig(
            initialValidationRatio: 0.5,
            lowestValidationRatio: 0.5,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: nil
        )
        
        ndk = NDK(signatureVerificationConfig: config)
        
        let relay1 = ndk.addRelay("wss://relay1.com")
        let relay2 = ndk.addRelay("wss://relay2.com")
        
        // Process some valid events
        for i in 0..<20 {
            ndk.processEvent(createTestEvent(id: "r1_\(i)"), from: relay1)
            ndk.processEvent(createTestEvent(id: "r2_\(i)"), from: relay2)
        }
        
        // Process an invalid event
        ndk.processEvent(createInvalidEvent(), from: relay2)
        
        // Wait for processing
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Get global stats
        let globalStats = await ndk.getSignatureVerificationStats()
        
        print("Global stats:")
        print("  Total verifications: \(globalStats.totalVerifications)")
        print("  Failed verifications: \(globalStats.failedVerifications)")
        print("  Blacklisted relays: \(globalStats.blacklistedRelays)")
        
        XCTAssertGreaterThan(globalStats.totalVerifications, 0)
        XCTAssertEqual(globalStats.failedVerifications, 1)
        XCTAssertEqual(globalStats.blacklistedRelays, 1)
        
        // Check individual relay stats
        let relay1Stats = relay1.getSignatureStats()
        let relay2Stats = relay2.getSignatureStats()
        
        print("\nRelay 1 stats:")
        print("  Validated: \(relay1Stats.validatedCount)")
        print("  Non-validated: \(relay1Stats.nonValidatedCount)")
        
        print("\nRelay 2 stats:")
        print("  Validated: \(relay2Stats.validatedCount)")
        print("  Non-validated: \(relay2Stats.nonValidatedCount)")
    }
    
    // MARK: - Cache Effectiveness Tests
    
    func testCacheEffectiveness() async {
        let config = NDKSignatureVerificationConfig.default
        ndk = NDK(signatureVerificationConfig: config)
        
        let relay1 = ndk.addRelay("wss://relay1.com")
        let relay2 = ndk.addRelay("wss://relay2.com")
        let relay3 = ndk.addRelay("wss://relay3.com")
        
        // Create a single event
        let event = createTestEvent(id: "shared_event")
        
        // Send the same event from multiple relays
        ndk.processEvent(event, from: relay1)
        ndk.processEvent(event, from: relay2)
        ndk.processEvent(event, from: relay3)
        
        // Wait for processing
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Only relay1 should have actually verified the signature
        let stats1 = relay1.getSignatureStats()
        let stats2 = relay2.getSignatureStats()
        let stats3 = relay3.getSignatureStats()
        
        // First relay verifies
        XCTAssertEqual(stats1.validatedCount, 1, "First relay should verify")
        
        // Other relays should use cache (counted as validated but not actually verified)
        XCTAssertEqual(stats2.validatedCount, 1, "Second relay should count as validated (from cache)")
        XCTAssertEqual(stats3.validatedCount, 1, "Third relay should count as validated (from cache)")
        
        // Global stats should show only 1 actual verification
        let globalStats = await ndk.getSignatureVerificationStats()
        XCTAssertEqual(globalStats.totalVerifications, 1, "Only one actual verification should occur")
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvent(id: String = UUID().uuidString) -> NDKEvent {
        let privateKey = Crypto.generatePrivateKey()
        let publicKey = try! Crypto.getPublicKey(from: privateKey)
        
        let event = NDKEvent(
            pubkey: publicKey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test event \(id)"
        )
        
        event.id = try! event.generateID()
        let messageData = Data(hexString: event.id!)!
        event.sig = try! Crypto.sign(message: messageData, privateKey: privateKey)
        
        return event
    }
    
    private func createInvalidEvent() -> NDKEvent {
        let event = NDKEvent(
            pubkey: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Invalid event"
        )
        
        event.id = "badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"
        event.sig = "invalidsignatureinvalidsignatureinvalidsignatureinvalidsignatureinvalidsignatureinvalidsignatureinvalidsignatureinvalidsignature00"
        
        return event
    }
}