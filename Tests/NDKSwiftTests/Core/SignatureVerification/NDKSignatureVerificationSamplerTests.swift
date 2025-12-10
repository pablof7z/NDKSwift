import XCTest
@testable import NDKSwiftCore

final class NDKSignatureVerificationSamplerTests: XCTestCase {
    var sampler: NDKSignatureVerificationSampler!
    var config: NDKSignatureVerificationConfig!
    
    override func setUp() {
        super.setUp()
        config = NDKSignatureVerificationConfig(
            initialValidationRatio: 1.0,
            lowestValidationRatio: 0.1,
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: nil
        )
        sampler = NDKSignatureVerificationSampler(config: config)
    }
    
    override func tearDown() {
        sampler = nil
        config = nil
        super.tearDown()
    }
    
    func testSamplerInitialization() async {
        let stats = await sampler.getStats()
        XCTAssertEqual(stats.totalVerifications, 0)
        XCTAssertEqual(stats.failedVerifications, 0)
        XCTAssertEqual(stats.blacklistedRelays, 0)
    }
    
    func testRelayBlacklistingFunctionality() async {
        // Create a mock relay URL
        let relayUrl = "wss://evil.relay.com"
        
        // Initially not blacklisted
        let isBlacklisted = await sampler.isRelayBlacklisted(relayUrl)
        XCTAssertFalse(isBlacklisted)
        
        // Get blacklisted relays (should be empty)
        let blacklistedRelays = await sampler.getBlacklistedRelays()
        XCTAssertTrue(blacklistedRelays.isEmpty)
    }
    
    func testDelegateSetup() async {
        // Create a test delegate
        let delegate = TestSignatureVerificationDelegate()
        
        // Set the delegate
        await sampler.setDelegate(delegate)
        
        // This test just verifies the delegate can be set without crashing
        XCTAssertTrue(true)
    }
    
    func testCacheClear() async {
        // Test that cache can be cleared without error
        await sampler.clearCache()
        
        // Verify stats are still accessible after cache clear
        let stats = await sampler.getStats()
        XCTAssertEqual(stats.totalVerifications, 0)
    }
    
    func testConfigurationTypes() {
        // Test default configuration
        let defaultConfig = NDKSignatureVerificationConfig.default
        XCTAssertEqual(defaultConfig.initialValidationRatio, 1.0)
        XCTAssertEqual(defaultConfig.lowestValidationRatio, 0.1)
        XCTAssertFalse(defaultConfig.autoBlacklistInvalidRelays)
        
        // Test disabled configuration
        let disabledConfig = NDKSignatureVerificationConfig.disabled
        XCTAssertEqual(disabledConfig.initialValidationRatio, 0.0)
        XCTAssertEqual(disabledConfig.lowestValidationRatio, 0.0)
        XCTAssertFalse(disabledConfig.autoBlacklistInvalidRelays)
    }
    
    func testRelaySignatureStats() {
        let stats = NDKRelaySignatureStats()
        
        // Initial state
        XCTAssertEqual(stats.validatedCount, 0)
        XCTAssertEqual(stats.nonValidatedCount, 0)
        XCTAssertEqual(stats.totalEvents, 0)
        XCTAssertEqual(stats.currentValidationRatio, 1.0)
        
        // Test stats equality
        let stats2 = NDKRelaySignatureStats()
        XCTAssertEqual(stats, stats2)
    }
    
    func testSignatureVerificationResult() {
        // Test that the enum values exist and can be used
        let results: [NDKSignatureVerificationResult] = [.valid, .invalid, .skipped, .cached]
        XCTAssertEqual(results.count, 4)
    }
    
    func testCustomValidationRatioFunction() async {
        // Test configuration with custom validation ratio function
        let customConfig = NDKSignatureVerificationConfig(
            initialValidationRatio: 0.5,
            lowestValidationRatio: 0.05,
            autoBlacklistInvalidRelays: true,
            validationRatioFunction: { _, validatedCount, _ in
                // Custom function that decreases ratio based on validated count
                return max(0.1, 1.0 - (Double(validatedCount) * 0.01))
            }
        )
        
        let customSampler = NDKSignatureVerificationSampler(config: customConfig)
        let stats = await customSampler.getStats()
        XCTAssertEqual(stats.totalVerifications, 0)
    }
}

// MARK: - Test Helper Classes

private class TestSignatureVerificationDelegate: NDKSignatureVerificationDelegate {
    var signatureFailureEvents: [(NDKEvent, RelayProtocol)] = []
    var blacklistedRelays: [RelayProtocol] = []
    
    func signatureVerificationFailed(for event: NDKEvent, from relay: RelayProtocol) {
        signatureFailureEvents.append((event, relay))
    }
    
    func relayBlacklisted(_ relay: RelayProtocol) {
        blacklistedRelays.append(relay)
    }
}