@testable import NDKSwift
import XCTest

/// Integration tests for the complete outbox model implementation
final class NDKOutboxIntegrationTests: XCTestCase {
    func testCompleteOutboxPublishingFlow() async throws {
        // Create NDK with outbox configuration
        let ndk = NDK()
        ndk.outboxConfig = NDKOutboxConfig(
            blacklistedRelays: ["wss://spam.relay"],
            defaultPublishConfig: OutboxPublishConfig(
                minSuccessfulRelays: 2,
                maxRetries: 3,
                enablePow: true
            )
        )

        // Set up signer
        let privateKey = try NDKPrivateKeySigner.generateKey()
        ndk.signer = NDKPrivateKeySigner(privateKey: privateKey)
        let userPubkey = await ndk.signer!.publicKey()

        // Track user's relays
        await ndk.setRelaysForUser(
            pubkey: userPubkey,
            readRelays: ["wss://read1.relay", "wss://read2.relay"],
            writeRelays: ["wss://write1.relay", "wss://write2.relay", "wss://spam.relay"]
        )

        // Track mentioned user's relays
        let mentionedUser = "mentioned_user_pubkey"
        await ndk.setRelaysForUser(
            pubkey: mentionedUser,
            readRelays: ["wss://mentioned-read.relay"],
            writeRelays: ["wss://mentioned-write.relay"]
        )

        // Create event with mention
        var event = NDKEvent(
            pubkey: userPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [
                ["p", mentionedUser],
                ["e", "parent_event_id", "wss://parent.relay"],
            ],
            content: "Hello @\(mentionedUser), this is a test!"
        )

        // Sign event
        _ = try event.generateID()
        event.sig = try await ndk.signer!.sign(event)

        // Verify relay selection
        let selection = await ndk.relaySelector.selectRelaysForPublishing(event: event)

        // Should include user's write relays (excluding blacklisted)
        XCTAssertTrue(selection.relays.contains("wss://write1.relay"))
        XCTAssertTrue(selection.relays.contains("wss://write2.relay"))
        XCTAssertFalse(selection.relays.contains("wss://spam.relay"))

        // Should include mentioned user's relays
        XCTAssertTrue(selection.relays.contains("wss://mentioned-write.relay"))

        // Should include parent event relay
        XCTAssertTrue(selection.relays.contains("wss://parent.relay"))

        print("✅ Outbox would publish to \(selection.relays.count) relays: \(selection.relays)")
    }

    func testCompleteOutboxFetchingFlow() async throws {
        let ndk = NDK()

        // Set up current user
        let userPubkey = "current_user"
        ndk.signer = MockSigner(publicKey: userPubkey)

        // Track user's read relays
        await ndk.setRelaysForUser(
            pubkey: userPubkey,
            readRelays: ["wss://user-read1.relay", "wss://user-read2.relay"],
            writeRelays: []
        )

        // Track multiple authors
        let authors = ["author1", "author2", "author3"]

        await ndk.setRelaysForUser(
            pubkey: "author1",
            readRelays: ["wss://author1-read.relay", "wss://common.relay"],
            writeRelays: ["wss://author1-write.relay"]
        )

        await ndk.setRelaysForUser(
            pubkey: "author2",
            readRelays: ["wss://author2-read.relay", "wss://common.relay"],
            writeRelays: []
        )

        await ndk.setRelaysForUser(
            pubkey: "author3",
            readRelays: [],
            writeRelays: ["wss://author3-write.relay"] // Will fallback to write
        )

        // Create filter for multiple authors
        let filter = NDKFilter(
            authors: authors,
            kinds: [1, 6],
            since: Timestamp(Date().timeIntervalSince1970 - 3600) // Last hour
        )

        // Test relay selection
        let selection = await ndk.relaySelector.selectRelaysForFetching(filter: filter)

        // Should include user's read relays
        XCTAssertTrue(selection.relays.contains("wss://user-read1.relay"))

        // Should include authors' read relays
        XCTAssertTrue(selection.relays.contains("wss://author1-read.relay"))
        XCTAssertTrue(selection.relays.contains("wss://common.relay")) // Shared by multiple

        // Should fallback to write relay for author3
        XCTAssertTrue(selection.relays.contains("wss://author3-write.relay"))

        print("✅ Outbox would fetch from \(selection.relays.count) relays: \(selection.relays)")

        // Test relay combination optimization
        let relayMap = await ndk.relaySelector.chooseRelayCombinationForPubkeys(
            authors,
            type: .read,
            config: CombinationConfig(relaysPerAuthor: 2)
        )

        print("\n📊 Optimized relay assignments:")
        for (relay, pubkeys) in relayMap {
            print("  \(relay) -> \(pubkeys.joined(separator: ", "))")
        }

        // Verify optimization
        XCTAssertGreaterThan(relayMap["wss://common.relay"]?.count ?? 0, 1,
                             "Common relay should serve multiple authors")
    }

    func testOutboxCacheIntegration() async throws {
        // Create NDK with file cache
        let cache = try NDKFileCache(path: "test-outbox-cache")
        let ndk = NDK(cacheAdapter: cache)

        // Create test event
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_sig"
        )

        // Store unpublished event
        let targetRelays: Set<String> = ["wss://relay1.com", "wss://relay2.com"]
        let config = OutboxPublishConfig(minSuccessfulRelays: 2)

        await cache.storeUnpublishedEvent(
            event,
            targetRelays: targetRelays,
            publishConfig: config
        )

        // Verify stored
        let unpublishedEvents = await cache.getAllUnpublishedEvents()
        XCTAssertEqual(unpublishedEvents.count, 1)
        XCTAssertEqual(unpublishedEvents.first?.event.id, "test_event_id")

        // Update relay status
        await cache.updateUnpublishedEventStatus(
            eventId: "test_event_id",
            relayURL: "wss://relay1.com",
            status: .succeeded
        )

        await cache.updateUnpublishedEventStatus(
            eventId: "test_event_id",
            relayURL: "wss://relay2.com",
            status: .failed(.connectionFailed)
        )

        // Check retry candidates
        let eventsForRetry = await cache.getEventsForRetry(olderThan: 0)
        XCTAssertEqual(eventsForRetry.count, 1) // Still needs retry

        // Mark as published
        await cache.markEventAsPublished(eventId: "test_event_id")

        let remainingEvents = await cache.getAllUnpublishedEvents()
        XCTAssertEqual(remainingEvents.count, 0)

        // Clean up
        try? FileManager.default.removeItem(at: cache.cacheDirectory)
    }

    func testRelayHealthTracking() async throws {
        let ndk = NDK()

        let relayURL = "wss://test.relay"

        // Simulate relay interactions
        await ndk.updateRelayPerformance(url: relayURL, success: true, responseTime: 0.1)
        await ndk.updateRelayPerformance(url: relayURL, success: true, responseTime: 0.15)
        await ndk.updateRelayPerformance(url: relayURL, success: false)
        await ndk.updateRelayPerformance(url: relayURL, success: true, responseTime: 0.2)

        // Check health score
        let healthScore = await ndk.relayRanker.getRelayHealthScore(relayURL)

        print("📊 Relay health score: \(healthScore)")
        XCTAssertGreaterThan(healthScore, 0.5) // 75% success rate
        XCTAssertLessThanOrEqual(healthScore, 1.0)

        // Test relay ranking with health scores
        await ndk.trackUser("author1")
        await ndk.setRelaysForUser(
            pubkey: "author1",
            readRelays: [relayURL, "wss://unhealthy.relay"],
            writeRelays: []
        )

        // Make unhealthy relay fail consistently
        for _ in 0 ..< 5 {
            await ndk.updateRelayPerformance(url: "wss://unhealthy.relay", success: false)
        }

        let rankedRelays = await ndk.relayRanker.rankRelays(
            [relayURL, "wss://unhealthy.relay"],
            for: ["author1"]
        )

        print("\n📊 Relay rankings:")
        for relay in rankedRelays {
            print("  \(relay.url): \(relay.score)")
        }

        XCTAssertEqual(rankedRelays.first?.url, relayURL)
        XCTAssertGreaterThan(rankedRelays[0].score, rankedRelays[1].score)
    }

    func testPOWGeneration() async throws {
        var event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test content"
        )

        // Generate ID first
        _ = try event.generateID()

        // Generate POW with difficulty 8 (should be fast)
        try await event.generatePow(targetDifficulty: 8)

        // Verify POW tag was added
        let nonceTag = event.tags.first { $0.first == "nonce" }
        XCTAssertNotNil(nonceTag)
        XCTAssertEqual(nonceTag?.count, 3)
        XCTAssertEqual(nonceTag?[2], "8") // Difficulty

        // Verify ID has required leading zeros
        let id = event.id!
        let requiredPrefix = String(repeating: "0", count: 8 / 4)
        XCTAssertTrue(id.hasPrefix(requiredPrefix))

        print("✅ Generated POW: event ID = \(id)")
    }

    func testCleanupOperations() async throws {
        let ndk = NDK()

        // Add some test data
        await ndk.trackUser("user1")
        await ndk.trackUser("user2")

        // Perform cleanup
        await ndk.cleanupOutbox()

        // Verify cleanup was performed
        // (In a real implementation, would check that old data was removed)
        print("✅ Cleanup operations completed")
    }
}
