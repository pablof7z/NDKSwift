@testable import NDKSwiftCore
import XCTest

final class EOSETrackerTests: XCTestCase {

    /// Test for GitHub issue #54: EOSETracker receives EOSE from unexpected relays
    ///
    /// This test verifies that fallback relays (used for unknown authors in outbox model)
    /// are properly tracked as expected relays. The bug was that expectedRelays was set
    /// BEFORE applyOutboxStrategy() added fallback relays, causing spurious warnings.
    func testFallbackRelaysAreTrackedAsExpected() async throws {
        let tracker = EOSETracker(subscriptionId: "test-sub")

        // Simulate the outbox scenario:
        // - outbox relays: relay1.example.com (from filtersByRelay)
        // - fallback relays: fallback.example.com (added later for unknown authors)
        let outboxRelay = "wss://relay1.example.com/"
        let fallbackRelay = "wss://fallback.example.com/"

        // This is what the FIXED code should do: include ALL relays
        // (both outbox-specific and fallback relays)
        let allRelays: Set<RelayURL> = [outboxRelay, fallbackRelay]
        await tracker.setExpectedRelays(allRelays)

        // Simulate EOSE from both relays
        await tracker.trackEOSE(from: outboxRelay)
        await tracker.trackEOSE(from: fallbackRelay)

        // Verify: All relays should be tracked, so allRelaysEOSEd should be true
        let allEOSEd = await tracker.allRelaysEOSEd()
        XCTAssertTrue(allEOSEd, "Both outbox and fallback relays should be tracked as expected")
    }

    /// This test demonstrates the BUGGY behavior: when fallback relays are NOT in expectedRelays,
    /// their EOSE is ignored and allRelaysEOSEd never becomes true if we're only counting fallback.
    ///
    /// After the fix, this scenario shouldn't occur because all relays should be in expectedRelays.
    func testUnexpectedRelayEOSEIsIgnored() async throws {
        let tracker = EOSETracker(subscriptionId: "test-sub")

        // Set only outbox relay as expected (simulating the bug)
        let outboxRelay = "wss://relay1.example.com/"
        let fallbackRelay = "wss://fallback.example.com/"

        await tracker.setExpectedRelays([outboxRelay])

        // Send EOSE from outbox relay - should be tracked
        await tracker.trackEOSE(from: outboxRelay)

        // Send EOSE from fallback relay - should be IGNORED (current buggy behavior)
        await tracker.trackEOSE(from: fallbackRelay)

        // With only outboxRelay expected and EOSEd, this should be true
        let allEOSEd = await tracker.allRelaysEOSEd()
        XCTAssertTrue(allEOSEd, "Only the expected relay should be tracked")

        // But this is the BUG: fallback relay sent EOSE but it was ignored!
        // The warning "Received EOSE from unexpected relay" was logged.
    }

    /// Test that verifies the core bug scenario: expectedRelays must include ALL relays
    /// where subscriptions are created, not just the outbox-specific relays.
    ///
    /// The bug was that expectedRelays was set to strategy.filtersByRelay.keys BEFORE
    /// applyOutboxStrategy() added fallback relays. This meant fallback relays weren't
    /// expected, causing "unexpected relay" warnings when they sent EOSE.
    ///
    /// This test verifies that if you have N relays active, you need N relays expected
    /// for allRelaysEOSEd() to work correctly.
    func testExpectedRelaysMustMatchActiveRelaysForCorrectEOSETracking() async throws {
        let tracker = EOSETracker(subscriptionId: "test-sub")

        // Scenario: 3 relays are active (1 outbox + 2 fallback)
        let outboxRelay = "wss://outbox.relay.com/"
        let fallbackRelay1 = "wss://fallback1.relay.com/"
        let fallbackRelay2 = "wss://fallback2.relay.com/"

        let allActiveRelays: Set<RelayURL> = [outboxRelay, fallbackRelay1, fallbackRelay2]

        // CORRECT behavior after fix: expectedRelays includes ALL active relays
        await tracker.setExpectedRelays(allActiveRelays)

        // Simulate EOSE from all relays
        await tracker.trackEOSE(from: outboxRelay)
        await tracker.trackEOSE(from: fallbackRelay1)
        await tracker.trackEOSE(from: fallbackRelay2)

        // Verify: allRelaysEOSEd should be true only after ALL relays have sent EOSE
        let allEOSEd = await tracker.allRelaysEOSEd()
        XCTAssertTrue(allEOSEd, "All relays (outbox + fallback) should be tracked and allRelaysEOSEd should be true")
    }

    /// Test that demonstrates the bug: if expectedRelays only includes outbox relays
    /// (not fallback), then EOSE from fallback relays causes issues.
    func testBugScenario_OnlyOutboxRelaysExpected_FallbackEOSEIgnored() async throws {
        let tracker = EOSETracker(subscriptionId: "test-sub")

        // Scenario: 3 relays are ACTIVE but only 1 is EXPECTED (the bug)
        let outboxRelay = "wss://outbox.relay.com/"
        let fallbackRelay1 = "wss://fallback1.relay.com/"
        let fallbackRelay2 = "wss://fallback2.relay.com/"

        // BUGGY behavior: only outbox relay is expected (before the fix)
        await tracker.setExpectedRelays([outboxRelay])

        // EOSE from outbox relay - tracked
        await tracker.trackEOSE(from: outboxRelay)

        // Check: allRelaysEOSEd is TRUE even though fallback relays haven't sent EOSE yet!
        // This is the bug - we're declaring "all done" prematurely
        let allEOSEdAfterOutbox = await tracker.allRelaysEOSEd()
        XCTAssertTrue(allEOSEdAfterOutbox, "Bug: allRelaysEOSEd is true with only outbox relay (fallback not expected)")

        // EOSE from fallback relays - these would log warnings and be ignored
        await tracker.trackEOSE(from: fallbackRelay1)
        await tracker.trackEOSE(from: fallbackRelay2)

        // Still true because fallback relays were never expected
        let allEOSEdAfterFallback = await tracker.allRelaysEOSEd()
        XCTAssertTrue(allEOSEdAfterFallback, "Bug: fallback relay EOSE was ignored")
    }
}
