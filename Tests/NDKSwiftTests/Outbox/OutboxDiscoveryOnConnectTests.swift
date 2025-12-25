@testable import NDKSwiftCore
import XCTest

/// Tests that outbox discovery automatically triggers when relays connect
/// after a subscription is created with unknown authors
final class OutboxDiscoveryOnConnectTests: NDKUnitTestCase {

    // MARK: - Test: Authors marked as pending when no relays connected

    /// When discovery is triggered with no connected relays,
    /// authors should be marked as pending for later retry
    func testAuthorsMarkedAsPendingWhenNoRelaysConnected() async throws {
        try await performAsyncTest(timeout: 5) {
            // GIVEN: NDK with outbox relay but NOT connected
            let outboxRelayURL = "wss://outbox.test"
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )
            // Note: NOT calling ndk.connect() - relays are not connected

            let unknownAuthors = Set(["author1", "author2", "author3"])

            // Verify no pending authors initially
            let pendingBefore = await self.ndk.outbox.getPendingAuthorsForTesting()
            XCTAssertTrue(pendingBefore.isEmpty, "Should have no pending authors initially")

            // WHEN: Trigger discovery while offline (no relays connected)
            await self.ndk.outbox.discoverRelaysInBackground(for: unknownAuthors)

            // Give time for the background task to process
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // THEN: Authors should be marked as pending
            let pendingAfter = await self.ndk.outbox.getPendingAuthorsForTesting()
            XCTAssertTrue(
                unknownAuthors.isSubset(of: pendingAfter),
                "Authors should be marked as pending when no relays are connected. Expected \(unknownAuthors) to be subset of \(pendingAfter)"
            )
        }
    }

    // MARK: - Test: Pending authors cleared after retry

    /// When retryPendingDiscoveries is called with connected relays,
    /// pending authors should be cleared (moved to lookup)
    func testPendingAuthorsClearedAfterRetryWithConnectedRelays() async throws {
        try await performAsyncTest(timeout: 10) {
            // GIVEN: NDK with outbox relay
            let outboxRelayURL = "wss://relay.damus.io"  // Real relay
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            let unknownAuthors = Set(["author1", "author2"])

            // First, mark authors as pending by triggering discovery while offline
            await self.ndk.outbox.discoverRelaysInBackground(for: unknownAuthors)
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Verify authors are pending
            let pendingBefore = await self.ndk.outbox.getPendingAuthorsForTesting()
            XCTAssertTrue(
                unknownAuthors.isSubset(of: pendingBefore),
                "Authors should be pending before connect. Expected \(unknownAuthors) to be subset of \(pendingBefore)"
            )

            // WHEN: Connect to relays and call retryPendingDiscoveries
            await self.ndk.connect()

            // Wait for relay to connect
            var connected = false
            for _ in 0..<50 {  // 5 seconds max
                let connectedRelays = await self.ndk.pool.connectedRelayURLs
                if !connectedRelays.isEmpty {
                    connected = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            guard connected else {
                XCTFail("Failed to connect to relay within timeout")
                return
            }

            // Manually trigger retry (normally called by handleRelayConnected)
            await self.ndk.outbox.retryPendingDiscoveries()

            // Give time for discovery to start
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // THEN: Pending authors should be cleared
            let pendingAfter = await self.ndk.outbox.getPendingAuthorsForTesting()
            XCTAssertTrue(
                pendingAfter.isEmpty,
                "Pending authors should be cleared after retry - still pending: \(pendingAfter)"
            )
        }
    }

    // MARK: - Test: Subscription triggers discovery for unknown authors

    /// When a subscription is created with unknown authors,
    /// they should be marked for discovery
    func testSubscriptionMarksAuthorsForDiscovery() async throws {
        try await performAsyncTest(timeout: 5) {
            // GIVEN: NDK with outbox enabled
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: ["wss://outbox.test"])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            let unknownAuthors = ["author1", "author2", "author3"]

            // WHEN: Get outbox strategy for a filter with unknown authors
            let filter = NDKFilter(authors: unknownAuthors, kinds: [1])
            let strategy = await self.ndk.outbox.getOutboxStrategy(for: filter)

            // THEN: All authors should be marked as unknown and for discovery
            XCTAssertEqual(strategy.unknownAuthors.count, 3, "All 3 authors should be unknown")
            XCTAssertEqual(strategy.authorsToDiscover.count, 3, "All 3 authors should be marked for discovery")
            XCTAssertTrue(strategy.filtersByRelay.isEmpty, "No relay-specific filters since all authors unknown")
        }
    }

    // MARK: - Test: Known authors not marked for discovery

    /// Test that kind:10002 subscription receives events from relay
    /// This is the key test - if this fails, discovery can't work
    func testKind10002SubscriptionReceivesEvents() async throws {
        try await performAsyncTest(timeout: 15) {
            // GIVEN: NDK with a real relay
            let outboxRelayURL = "wss://relay.damus.io"
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            // Known pubkey that definitely has a kind:10002 event
            let knownPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52" // pablof7z

            // Connect to relay
            await self.ndk.connect()

            // Wait for relay to connect
            var connected = false
            for _ in 0..<50 {
                let connectedRelays = await self.ndk.pool.connectedRelayURLs
                if !connectedRelays.isEmpty {
                    connected = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard connected else {
                XCTFail("Failed to connect to relay within timeout")
                return
            }

            // WHEN: Create a kind:10002 subscription directly
            let filter = NDKFilter(
                authors: [knownPubkey],
                kinds: [EventKind.relayList]
            )

            let connectedRelays = await self.ndk.pool.connectedRelayURLs
            let subscription = NDKSubscription(
                ndk: self.ndk,
                filter: filter,
                relays: connectedRelays,
                subscriptionId: "test_relay_list"
            )

            // Collect events
            var receivedEvents: [NDKEvent] = []
            let startTime = Date()

            // Listen for events with a timeout
            for await batch in subscription.events {
                receivedEvents.append(contentsOf: batch)
                // Break after receiving any events or after 5 seconds
                if !receivedEvents.isEmpty || Date().timeIntervalSince(startTime) > 5 {
                    break
                }
            }

            // THEN: Should have received at least one kind:10002 event
            XCTAssertFalse(
                receivedEvents.isEmpty,
                "Should have received at least one kind:10002 event for known pubkey"
            )

            // Verify it's a relay list event
            if let event = receivedEvents.first {
                XCTAssertEqual(event.kind, EventKind.relayList, "Event should be kind:10002")
                XCTAssertEqual(event.pubkey, knownPubkey, "Event should be from the requested pubkey")
            }
        }
    }

    /// Test the FULL demo flow: subscription created before relay connects
    /// This is the key integration test simulating the actual demo scenario
    func testFullDemoFlow_SubscriptionBeforeConnect() async throws {
        try await performAsyncTest(timeout: 20) {
            // GIVEN: NDK with outbox relay, NOT connected yet
            let outboxRelayURL = "wss://relay.damus.io"
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            // Known pubkey that definitely has a kind:10002 event
            let knownPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52" // pablof7z

            // WHEN: Create subscription BEFORE connecting (like the demo does)
            let filter = NDKFilter(authors: [knownPubkey], kinds: [1])
            let subscription = self.ndk.subscribe(filter: filter)

            // Keep subscription alive
            _ = subscription

            // Give time for subscription to be registered and trigger discovery
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Check that author is pending (since no relays connected)
            let pendingBefore = await self.ndk.outbox.getPendingAuthorsForTesting()
            // Note: might include signer's pubkey too
            XCTAssertTrue(
                pendingBefore.contains(knownPubkey) || pendingBefore.isEmpty,
                "Author should be pending or discovery skipped (no relays). Pending: \(pendingBefore)"
            )

            // Verify no cached relay info before connect
            let cachedBefore = await self.ndk.outbox.getRelaysSyncFor(pubkey: knownPubkey)
            XCTAssertNil(cachedBefore, "Should not have cached relay info before connect")

            // THEN: Connect to relays
            await self.ndk.connect()

            // Wait for relay to connect AND for handleRelayConnected to trigger retryPendingDiscoveries
            var connected = false
            for _ in 0..<100 {  // 10 seconds max
                let connectedRelays = await self.ndk.pool.connectedRelayURLs
                if !connectedRelays.isEmpty {
                    connected = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard connected else {
                XCTFail("Failed to connect to relay within timeout")
                return
            }

            // Wait for discovery to complete (triggered by handleRelayConnected)
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // THEN: Author should have cached relay info (discovered automatically)
            let cachedAfter = await self.ndk.outbox.getRelaysSyncFor(pubkey: knownPubkey)
            XCTAssertNotNil(
                cachedAfter,
                "Author relay info should be discovered automatically when relay connects"
            )

            if let cached = cachedAfter {
                let totalRelays = cached.readRelays.count + cached.writeRelays.count
                XCTAssertGreaterThan(totalRelays, 0, "Should have discovered at least one relay")
            }
        }
    }

    /// Test discovery with multiple authors (simulating the demo scenario)
    func testDiscoverRelaysInBackgroundWithManyAuthors() async throws {
        try await performAsyncTest(timeout: 20) {
            // GIVEN: NDK with a real relay
            let outboxRelayURL = "wss://relay.damus.io"
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            // Use multiple known pubkeys that have kind:10002 events
            // These are real pubkeys from the nostr network
            let knownPubkeys = Set([
                "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52", // pablof7z
                "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", // jb55
                "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
            ])

            // Connect to relay
            await self.ndk.connect()

            // Wait for relay to connect
            var connected = false
            for _ in 0..<50 {
                let connectedRelays = await self.ndk.pool.connectedRelayURLs
                if !connectedRelays.isEmpty {
                    connected = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard connected else {
                XCTFail("Failed to connect to relay within timeout")
                return
            }

            // Verify no cached relay info before discovery
            for pubkey in knownPubkeys {
                let cached = await self.ndk.outbox.getRelaysSyncFor(pubkey: pubkey)
                XCTAssertNil(cached, "Should not have cached relay info before discovery for \(pubkey.prefix(8))")
            }

            // WHEN: Call discoverRelaysInBackground with multiple authors
            await self.ndk.outbox.discoverRelaysInBackground(for: knownPubkeys)

            // Wait for discovery to complete
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // THEN: At least some authors should have cached relay info
            var foundCount = 0
            for pubkey in knownPubkeys {
                let cached = await self.ndk.outbox.getRelaysSyncFor(pubkey: pubkey)
                if cached != nil {
                    foundCount += 1
                }
            }

            XCTAssertGreaterThan(foundCount, 0, "Should have discovered relay info for at least one author")
        }
    }

    /// Test that discoverRelaysInBackground actually updates the outbox cache
    func testDiscoverRelaysInBackgroundUpdatesCache() async throws {
        try await performAsyncTest(timeout: 15) {
            // GIVEN: NDK with a real relay
            let outboxRelayURL = "wss://relay.damus.io"
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: [outboxRelayURL])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            // Known pubkey that definitely has a kind:10002 event
            let knownPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52" // pablof7z

            // Connect to relay
            await self.ndk.connect()

            // Wait for relay to connect
            var connected = false
            for _ in 0..<50 {
                let connectedRelays = await self.ndk.pool.connectedRelayURLs
                if !connectedRelays.isEmpty {
                    connected = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            guard connected else {
                XCTFail("Failed to connect to relay within timeout")
                return
            }

            // Verify no cached relay info before discovery
            let cachedBefore = await self.ndk.outbox.getRelaysSyncFor(pubkey: knownPubkey)
            XCTAssertNil(cachedBefore, "Should not have cached relay info before discovery")

            // WHEN: Call discoverRelaysInBackground
            await self.ndk.outbox.discoverRelaysInBackground(for: Set([knownPubkey]))

            // Wait for discovery to complete (the background task)
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            // THEN: Cache should be updated
            let cachedAfter = await self.ndk.outbox.getRelaysSyncFor(pubkey: knownPubkey)
            XCTAssertNotNil(cachedAfter, "Should have cached relay info after discovery")

            if let cached = cachedAfter {
                let totalRelays = cached.readRelays.count + cached.writeRelays.count
                XCTAssertGreaterThan(totalRelays, 0, "Should have discovered at least one relay")
            }
        }
    }

    /// When authors have cached relay info, they should NOT be marked for discovery
    func testKnownAuthorsNotMarkedForDiscovery() async throws {
        try await performAsyncTest(timeout: 5) {
            // GIVEN: NDK with some known authors
            let outboxConfig = NDKDiscoveryConfig(discoveryRelays: ["wss://outbox.test"])

            self.ndk = NDK(
                relayURLs: [],
                signer: self.signer,
                cache: self.cache,
                outboxEnabled: true,
                discoveryConfig: outboxConfig
            )

            // Cache relay info for author1
            await self.ndk.outbox.track(
                pubkey: "author1",
                readRelays: ["wss://relay1.test"],
                writeRelays: ["wss://relay1.test"],
                source: .nip65,
                emitDiscoveryEvent: false
            )

            // WHEN: Get outbox strategy with mix of known and unknown authors
            let filter = NDKFilter(authors: ["author1", "author2", "author3"], kinds: [1])
            let strategy = await self.ndk.outbox.getOutboxStrategy(for: filter)

            // THEN: Only unknown authors should be marked for discovery
            XCTAssertEqual(strategy.unknownAuthors.count, 2, "Only 2 authors should be unknown")
            XCTAssertFalse(strategy.unknownAuthors.contains("author1"), "author1 is known")
            XCTAssertTrue(strategy.unknownAuthors.contains("author2"), "author2 is unknown")
            XCTAssertTrue(strategy.unknownAuthors.contains("author3"), "author3 is unknown")
            XCTAssertEqual(strategy.authorsToDiscover.count, 2, "Only 2 authors should need discovery")
        }
    }
}
