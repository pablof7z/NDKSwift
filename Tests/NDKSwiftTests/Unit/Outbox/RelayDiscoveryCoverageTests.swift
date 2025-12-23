@testable import NDKSwiftCore
import XCTest

/// Tests for relay discovery coverage tracking
/// Verifies that fallback/explicit relays do NOT count toward author coverage
final class RelayDiscoveryCoverageTests: XCTestCase {

    // MARK: - Core Coverage Counting Tests

    /// Fallback relays should NOT count toward author coverage
    /// When an unknown author is initially subscribed via fallback relays,
    /// those relays should not be counted when checking if the author has coverage
    func testFallbackRelaysDoNotCountAsCoverage() async throws {
        // Given: An author whose relays have just been discovered
        let author = "abc123def456author"
        let fallbackRelay1 = "wss://relay.damus.io"
        let fallbackRelay2 = "wss://relay.primal.net"

        // The author's actual relays from their kind:10002
        let authorRelay1 = "wss://author-relay1.com"
        let authorRelay2 = "wss://author-relay2.com"
        let authorRelay3 = "wss://author-relay3.com"

        // Create tracker with the discovered relay info
        let mockTracker = MockRelayPreferenceProvider()
        await mockTracker.track(
            pubkey: author,
            readRelays: Set([authorRelay1, authorRelay2, authorRelay3]),
            writeRelays: Set([authorRelay1, authorRelay2, authorRelay3]),
            source: .nip65,
            emitDiscoveryEvent: false
        )

        let selector = OverlapOptimizedRelaySelector(tracker: mockTracker)

        // Simulate: author was previously added to fallback relays
        // These are connected but should NOT count as coverage
        let existingFallbackRelays: Set<RelayURL> = [fallbackRelay1, fallbackRelay2]

        // The discovered relays from the author's 10002
        let discoveredAuthorRelays: Set<RelayURL> = [authorRelay1, authorRelay2, authorRelay3]

        // When: We select relays to connect to
        // Even though fallback relays are "existing", they should NOT count
        // The fix: `existingRelays` should be empty because fallbacks don't count
        let selectedRelays = await selector.selectRelaysToConnect(
            discoveredRelays: discoveredAuthorRelays,
            for: Set([author]),
            existingRelays: Set(), // Fallback relays should NOT be passed as existing
            connectedRelays: existingFallbackRelays, // But they are connected
            maxRelays: 2
        )

        // Should select 2 of the discovered author-specific relays
        XCTAssertEqual(selectedRelays.count, 2,
            "Should select 2 author-specific relays even when fallback relays exist")
        XCTAssertTrue(selectedRelays.isSubset(of: discoveredAuthorRelays),
            "Selected relays should be from discovered author relays, not fallbacks")
    }

    /// When an author has author-specific relays, those should count
    func testAuthorSpecificRelaysCountAsCoverage() async throws {
        // Given: An author with known relays already being used
        let author = "author123"
        let authorRelay1 = "wss://author-relay1.com"
        let authorRelay2 = "wss://author-relay2.com"

        let mockTracker = MockRelayPreferenceProvider()
        // Pre-populate the tracker with the author's relay preferences
        await mockTracker.track(
            pubkey: author,
            readRelays: Set([authorRelay1, authorRelay2]),
            writeRelays: Set([authorRelay1, authorRelay2]),
            source: .nip65,
            emitDiscoveryEvent: false
        )

        let selector = OverlapOptimizedRelaySelector(tracker: mockTracker)

        // Existing relays are author-specific (these DO count)
        let existingAuthorRelays: Set<RelayURL> = [authorRelay1, authorRelay2]

        // When: We discover more relays for this author
        let newDiscoveredRelays: Set<RelayURL> = [
            "wss://new-relay1.com",
            "wss://new-relay2.com"
        ]

        // Then: The selector should NOT select more relays
        // because the author already has 2 author-specific relays
        let selectedRelays = await selector.selectRelaysToConnect(
            discoveredRelays: newDiscoveredRelays,
            for: Set([author]),
            existingRelays: existingAuthorRelays, // These are author-specific, so count
            connectedRelays: existingAuthorRelays,
            maxRelays: 2
        )

        // Should NOT select any new relays
        XCTAssertEqual(selectedRelays.count, 0,
            "Should not select more relays when author already has sufficient author-specific coverage")
    }

    /// Mixed scenario: author has 1 author-specific relay already being used
    /// and we discover additional relays - should select 1 more to reach the limit
    func testPartialCoverageWithMixedRelays() async throws {
        // Given: An author with 2 relays discovered (we already use 1, discover 1 more)
        let author = "author456"
        let authorSpecificRelay = "wss://author-relay.com"
        let discoveredRelay1 = "wss://discovered1.com"
        let discoveredRelay2 = "wss://discovered2.com"
        let fallbackRelay = "wss://fallback.relay.com"

        let mockTracker = MockRelayPreferenceProvider()
        // The author's full relay list includes 3 relays
        await mockTracker.track(
            pubkey: author,
            readRelays: Set([authorSpecificRelay, discoveredRelay1, discoveredRelay2]),
            writeRelays: Set([authorSpecificRelay, discoveredRelay1, discoveredRelay2]),
            source: .nip65,
            emitDiscoveryEvent: false
        )

        let selector = OverlapOptimizedRelaySelector(tracker: mockTracker)

        // We already have 1 author-specific relay connected
        let existingAuthorRelays: Set<RelayURL> = [authorSpecificRelay]

        // When: We discover additional relays for this author
        let discoveredRelays: Set<RelayURL> = [discoveredRelay1, discoveredRelay2]

        // Then: Should select 1 more relay to reach limit of 2
        let selectedRelays = await selector.selectRelaysToConnect(
            discoveredRelays: discoveredRelays,
            for: Set([author]),
            existingRelays: existingAuthorRelays, // Only 1 author-specific relay
            connectedRelays: Set([authorSpecificRelay, fallbackRelay]), // Both connected
            maxRelays: 2
        )

        XCTAssertEqual(selectedRelays.count, 1,
            "Should select 1 more relay when author has 1 author-specific relay")
    }
}
