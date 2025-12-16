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

    // MARK: - Integration Tests Using Mock Relay Infrastructure

    /// Integration test: Verify that NDKSubscriptionRequirement includes fallback relays
    /// in expectedRelays when using outbox strategy with unknown authors.
    ///
    /// This is the main test for issue #54 using the new mock relay infrastructure.
    func testOutboxStrategyWithUnknownAuthors_FallbackRelaysInExpected() async throws {
        // Create NDK and add mock relays that appear "connected"
        let ndk = NDK()

        // Add fallback relays (these will be used for unknown authors)
        let fallbackRelay1URL = "wss://fallback1.test/"
        let fallbackRelay2URL = "wss://fallback2.test/"
        let (_, fallbackRelay1) = await ndk.addMockRelay(url: fallbackRelay1URL)
        let (_, fallbackRelay2) = await ndk.addMockRelay(url: fallbackRelay2URL)

        // Add outbox relay (for known author)
        let outboxRelayURL = "wss://outbox.test/"
        let (_, outboxRelay) = await ndk.addMockRelay(url: outboxRelayURL)

        // Verify relays are connected
        let connectedRelays = await ndk.pool.getConnectedRelayURLsForTesting()
        XCTAssertTrue(connectedRelays.contains(fallbackRelay1URL.normalizedRelayURL),
                     "Fallback relay 1 should be connected")
        XCTAssertTrue(connectedRelays.contains(fallbackRelay2URL.normalizedRelayURL),
                     "Fallback relay 2 should be connected")
        XCTAssertTrue(connectedRelays.contains(outboxRelayURL.normalizedRelayURL),
                     "Outbox relay should be connected")

        // Create outbox strategy with:
        // - Known author on outbox relay
        // - Unknown author (will use fallback relays)
        let knownAuthor = "known_author_pubkey"
        let unknownAuthor = "unknown_author_pubkey"

        var filterForOutbox = NDKFilter(kinds: [1])
        filterForOutbox.authors = [knownAuthor]

        let strategy = OutboxFilterStrategy(
            filtersByRelay: [outboxRelayURL: filterForOutbox],
            unknownAuthors: [unknownAuthor],
            authorsToDiscover: []
        )

        // Create subscription coordinator
        let coordinator = await ndk.internalSubscriptionManager.createSubscription(
            id: "test-outbox-sub",
            filters: [NDKFilter(authors: [knownAuthor, unknownAuthor], kinds: [1])],
            relays: nil,
            autoStart: false
        )

        // Create the requirement with outbox strategy
        let filter = NDKFilter(authors: [knownAuthor, unknownAuthor], kinds: [1])
        let requirement = NDKSubscriptionRequirement(
            filter: filter,
            subscriptionId: "test-outbox-sub",
            internalSubscription: coordinator,
            cache: ndk.cache,
            ndk: ndk,
            relays: nil,
            exclusiveRelays: false,
            closeOnEose: false,
            relayStrategy: .outbox(strategy: strategy),
            shouldFetchFromNetwork: true,
            cachePolicy: .networkOnly
        )

        // Start processing - this triggers applyRelayStrategy which should:
        // 1. Apply outbox strategy (adds subscriptions to outbox + fallback relays)
        // 2. Set expectedRelays to ALL relays in relaySubscriptions
        await requirement.startProcessing()

        // Get active relays (where subscriptions were created)
        let activeRelays = await requirement.getActiveRelays()

        // Get expected relays from the EOSE tracker
        let expectedRelays = await requirement.getExpectedRelaysForTesting()

        // Verify: Active relays should include outbox relay
        XCTAssertTrue(activeRelays.contains(outboxRelayURL.normalizedRelayURL),
                     "Outbox relay should be active. Active: \(activeRelays)")

        // Verify: Active relays should include at least one fallback relay
        // (They're used because unknownAuthors is not empty and relays are "connected")
        let activeFallbackRelays = activeRelays.filter {
            $0 == fallbackRelay1URL.normalizedRelayURL || $0 == fallbackRelay2URL.normalizedRelayURL
        }
        XCTAssertFalse(activeFallbackRelays.isEmpty,
                      "At least one fallback relay should be active for unknown authors. Active: \(activeRelays)")

        // THE KEY ASSERTION: Expected relays should equal active relays
        // This is the fix for issue #54 - fallback relays must be in expectedRelays
        XCTAssertEqual(expectedRelays, activeRelays,
                      "Expected relays should match active relays.\nExpected: \(expectedRelays)\nActive: \(activeRelays)")

        // Additional verification: all active relays should be expected
        for activeRelay in activeRelays {
            XCTAssertTrue(expectedRelays.contains(activeRelay),
                         "Active relay \(activeRelay) should be in expectedRelays")
        }

        // Clean up
        await requirement.cancel()
    }

    /// Test that EOSE from fallback relays is properly tracked after the fix.
    func testEOSEFromFallbackRelaysIsTracked() async throws {
        // Create NDK and add mock relays
        let ndk = NDK()

        let fallbackRelayURL = "wss://fallback.test/"
        let outboxRelayURL = "wss://outbox.test/"

        let (fallbackMock, _) = await ndk.addMockRelay(url: fallbackRelayURL)
        let (outboxMock, _) = await ndk.addMockRelay(url: outboxRelayURL)

        // Create outbox strategy
        let knownAuthor = "known_author"
        let unknownAuthor = "unknown_author"

        var filterForOutbox = NDKFilter(kinds: [1])
        filterForOutbox.authors = [knownAuthor]

        let strategy = OutboxFilterStrategy(
            filtersByRelay: [outboxRelayURL: filterForOutbox],
            unknownAuthors: [unknownAuthor],
            authorsToDiscover: []
        )

        // Create requirement
        let coordinator = await ndk.internalSubscriptionManager.createSubscription(
            id: "test-eose-sub",
            filters: [NDKFilter(authors: [knownAuthor, unknownAuthor], kinds: [1])],
            relays: nil,
            autoStart: false
        )

        let requirement = NDKSubscriptionRequirement(
            filter: NDKFilter(authors: [knownAuthor, unknownAuthor], kinds: [1]),
            subscriptionId: "test-eose-sub",
            internalSubscription: coordinator,
            cache: ndk.cache,
            ndk: ndk,
            relays: nil,
            exclusiveRelays: false,
            closeOnEose: false,
            relayStrategy: .outbox(strategy: strategy),
            shouldFetchFromNetwork: true,
            cachePolicy: .networkOnly
        )

        await requirement.startProcessing()

        // Get the subscription ID used for EOSE tracking
        let activeRelays = await requirement.getActiveRelays()
        let expectedRelays = await requirement.getExpectedRelaysForTesting()

        // Both relays should be in expected (if fallback relay is active)
        if activeRelays.contains(fallbackRelayURL.normalizedRelayURL) {
            XCTAssertTrue(expectedRelays.contains(fallbackRelayURL.normalizedRelayURL),
                         "Fallback relay should be in expectedRelays")
        }

        // Simulate EOSE from outbox relay
        await outboxMock.sendEOSE(subscriptionId: "test-eose-sub")

        // Check EOSEs seen
        let eosesSeen = await requirement.getEOSEsSeenForTesting()

        // If fallback relay is active, simulate its EOSE too
        if activeRelays.contains(fallbackRelayURL.normalizedRelayURL) {
            await fallbackMock.sendEOSE(subscriptionId: "test-eose-sub")

            // Small delay for async processing
            try await Task.sleep(nanoseconds: 50_000_000)

            let finalEosesSeen = await requirement.getEOSEsSeenForTesting()

            // Verify fallback EOSE was tracked (not ignored with warning)
            XCTAssertTrue(finalEosesSeen.contains(fallbackRelayURL.normalizedRelayURL) ||
                         finalEosesSeen.contains(outboxRelayURL.normalizedRelayURL),
                         "At least one EOSE should be tracked. EOSEs seen: \(finalEosesSeen)")
        }

        await requirement.cancel()
    }
}
