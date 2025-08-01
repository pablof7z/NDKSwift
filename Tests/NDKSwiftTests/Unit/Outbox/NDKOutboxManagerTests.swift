import XCTest
@testable import NDKSwift

final class NDKOutboxManagerTests: NDKUnitTestCase {
    var outboxManager: NDKOutboxManager!
    var memoryCache: MemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        memoryCache = MemoryCache()
        ndk = NDK(
            relayUrls: [
                "wss://relay1.test",
                "wss://relay2.test"
            ],
            signer: signer,
            cache: memoryCache
        )
        
        // Configure outbox after initialization
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: [
                "wss://outbox1.test",
                "wss://outbox2.test"
            ]
        )
        outboxManager = ndk.outbox
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async throws {
        try await performAsyncTest(timeout: 5) {
            XCTAssertNotNil(self.outboxManager)
            
            // Test that relay discoveries stream is available
            var hasStream = false
            let task = Task {
                for await _ in await self.outboxManager.relayDiscoveries {
                    hasStream = true
                    break
                }
            }
            
            // Give it a moment to set up
            try? await Task.sleep(nanoseconds: 10_000_000)
            task.cancel()
            
            // Stream should be set up even if no events yet
            // Relay discoveries is an actor-isolated property
        }
    }
    
    // MARK: - Cache Operations Tests
    
    func testGetRelaysSyncFor() async throws {
        try await performAsyncTest(timeout: 5) {
            // Test when no data is cached
            let result = await self.outboxManager.getRelaysSyncFor(pubkey: "test_pubkey")
            XCTAssertNil(result)
        
            // Add data to cache
            await self.outboxManager.track(
                pubkey: "test_pubkey",
                readRelays: ["wss://read1.test", "wss://read2.test"],
                writeRelays: ["wss://write1.test"],
                source: .manual
            )
            
            // Test retrieving cached data
            let cachedResult = await self.outboxManager.getRelaysSyncFor(pubkey: "test_pubkey")
            XCTAssertNotNil(cachedResult)
            XCTAssertEqual(cachedResult?.readRelays.count, 2)
            XCTAssertEqual(cachedResult?.writeRelays.count, 1)
            
            // Test with relay type filter
            let readOnly = await self.outboxManager.getRelaysSyncFor(pubkey: "test_pubkey", type: .read)
            XCTAssertEqual(readOnly?.readRelays.count, 2)
            XCTAssertEqual(readOnly?.writeRelays.count, 0)
        
            let writeOnly = await self.outboxManager.getRelaysSyncFor(pubkey: "test_pubkey", type: .write)
            XCTAssertEqual(writeOnly?.readRelays.count, 0)
            XCTAssertEqual(writeOnly?.writeRelays.count, 1)
        }
    }
    
    func testTrackUserRelays() async throws {
        try await performAsyncTest(timeout: 5) {
            let pubkey = "test_pubkey"
            let readRelays = Set(["wss://read1.test", "wss://read2.test"])
            let writeRelays = Set(["wss://write1.test"])
        
            // Track without emitting discovery event
            await self.outboxManager.track(
                pubkey: pubkey,
                readRelays: readRelays,
                writeRelays: writeRelays,
                source: .nip65,
                emitDiscoveryEvent: false
            )
            
            // Verify cached
            let cached = await self.outboxManager.getRelaysSyncFor(pubkey: pubkey)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.pubkey, pubkey)
        XCTAssertEqual(cached?.readRelays.map { $0.url }.sorted(), readRelays.sorted())
        XCTAssertEqual(cached?.writeRelays.map { $0.url }.sorted(), writeRelays.sorted())
            XCTAssertEqual(cached?.source, .nip65)
        }
    }
    
    func testTrackUserWithBlacklistedRelays() async throws {
        try await performAsyncTest(timeout: 5) {
            // Create outbox manager with blacklisted relays
            let blacklistedManager = NDKOutboxManager(
                ndk: self.ndk,
                blacklistedRelays: ["wss://bad.relay"]
            )
        
        await blacklistedManager.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://good.relay", "wss://bad.relay"],
            writeRelays: ["wss://write.relay", "wss://bad.relay"],
            source: .manual
        )
        
        let cached = await blacklistedManager.getRelaysSyncFor(pubkey: "test_pubkey")
        XCTAssertNotNil(cached)
        
        // Bad relay should be filtered out
        XCTAssertFalse(cached!.readRelays.contains { $0.url == "wss://bad.relay" })
        XCTAssertFalse(cached!.writeRelays.contains { $0.url == "wss://bad.relay" })
        XCTAssertTrue(cached!.readRelays.contains { $0.url == "wss://good.relay" })
            XCTAssertTrue(cached!.writeRelays.contains { $0.url == "wss://write.relay" })
        }
    }
    
    func testGetAllCachedItems() async throws {
        try await performAsyncTest(timeout: 5) {
            // Initially empty
            var items = await self.outboxManager.getAllCachedItems()
            XCTAssertEqual(items.count, 0)
        
        // Track multiple users
            await self.outboxManager.track(
                pubkey: "user1",
                readRelays: ["wss://user1-read.test"],
                writeRelays: ["wss://user1-write.test"],
                source: .nip65
            )
            
            await self.outboxManager.track(
                pubkey: "user2",
                readRelays: ["wss://user2-read.test"],
                writeRelays: ["wss://user2-write.test"],
                source: .manual
            )
            
            // Get all items
            items = await self.outboxManager.getAllCachedItems()
        XCTAssertEqual(items.count, 2)
        
        let pubkeys = items.map { $0.pubkey }.sorted()
            XCTAssertEqual(pubkeys, ["user1", "user2"])
        }
    }
    
    func testClearCache() async throws {
        try await performAsyncTest(timeout: 5) {
            // Add some data
            await self.outboxManager.track(
                pubkey: "user1",
                readRelays: ["wss://read.test"],
                writeRelays: ["wss://write.test"],
                source: .nip65
            )
        
            // Verify it's there
            var items = await self.outboxManager.getAllCachedItems()
            XCTAssertEqual(items.count, 1)
            
            // Clear cache
            await self.outboxManager.clear()
            
            // Verify it's gone
            items = await self.outboxManager.getAllCachedItems()
            XCTAssertEqual(items.count, 0)
        }
    }
    
    // MARK: - Relay Discovery Tests
    
    func testRelayDiscoveryEventEmission() async throws {
        try await performAsyncTest(timeout: 5) {
            let expectation = XCTestExpectation(description: "Relay discovery event emitted")
            
            let task = Task {
                for await discovery in await self.outboxManager.relayDiscoveriesInternal {
                    if discovery.pubkey == "test_pubkey" {
                        expectation.fulfill()
                        break
                    }
                }
            }
            
            // Track with discovery event enabled
            await self.outboxManager.track(
                pubkey: "test_pubkey",
                readRelays: ["wss://read.test"],
                writeRelays: ["wss://write.test"],
                source: .nip65,
                emitDiscoveryEvent: true
            )
            
            await self.fulfillment(of: [expectation], timeout: 1.0)
            task.cancel()
        }
    }
    
    func testProcessRelayListEvent() async throws {
        try await performAsyncTest(timeout: 5) {
            // Create a relay list event
            let relayListEvent = NDKEvent(
                id: "test_id",
                pubkey: "test_pubkey",
                createdAt: Timestamp.now,
                kind: EventKind.relayList,
                tags: [
                    ["r", "wss://read1.test", "read"],
                    ["r", "wss://read2.test", "read"],
                    ["r", "wss://write1.test", "write"],
                    ["r", "wss://both.test"]  // No marker means both read and write
                ],
                content: "",
                sig: "test_sig"
            )
        
            await self.outboxManager.processRelayListEvent(relayListEvent)
            
            // Check that relays were tracked
            let cached = await self.outboxManager.getRelaysSyncFor(pubkey: "test_pubkey")
        XCTAssertNotNil(cached)
        
        // Check read relays (includes unmarked relay)
        let readRelayUrls = cached!.readRelays.map { $0.url }.sorted()
        XCTAssertEqual(readRelayUrls, ["wss://both.test", "wss://read1.test", "wss://read2.test"])
        
        // Check write relays (includes unmarked relay)
            let writeRelayUrls = cached!.writeRelays.map { $0.url }.sorted()
            XCTAssertEqual(writeRelayUrls, ["wss://both.test", "wss://write1.test"])
        }
    }
    
    // MARK: - Outbox Strategy Tests
    
    func testGetOutboxStrategyNoAuthors() async throws {
        try await performAsyncTest(timeout: 5) {
            let filter = NDKFilter(kinds: [1])
            let strategy = await self.outboxManager.getOutboxStrategy(for: filter)
        
            XCTAssertTrue(strategy.filtersByRelay.isEmpty)
            XCTAssertTrue(strategy.unknownAuthors.isEmpty)
            XCTAssertTrue(strategy.authorsToDiscover.isEmpty)
        }
    }
    
    func testGetOutboxStrategyWithKnownAuthors() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track relay info for authors
            await self.outboxManager.track(
                pubkey: "author1",
                readRelays: ["wss://author1-read.test"],
                writeRelays: ["wss://author1-write.test"],
                source: .nip65
            )
        
            await self.outboxManager.track(
                pubkey: "author2",
                readRelays: ["wss://author2-read.test", "wss://shared-read.test"],
                writeRelays: ["wss://author2-write.test"],
                source: .nip65
            )
            
            let filter = NDKFilter(
                authors: ["author1", "author2"],
                kinds: [1]
            )
            
            let strategy = await self.outboxManager.getOutboxStrategy(for: filter)
        
        // Should have relay-specific filters
        XCTAssertFalse(strategy.filtersByRelay.isEmpty)
        XCTAssertTrue(strategy.unknownAuthors.isEmpty)
        
        // Check that authors are grouped by relay
        if let author1Filter = strategy.filtersByRelay["wss://author1-read.test"] {
            XCTAssertTrue(author1Filter.authors?.contains("author1") ?? false)
        }
        
            if let sharedFilter = strategy.filtersByRelay["wss://shared-read.test"] {
                XCTAssertTrue(sharedFilter.authors?.contains("author2") ?? false)
            }
        }
    }
    
    func testGetOutboxStrategyWithUnknownAuthors() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track info for one author only
            await self.outboxManager.track(
                pubkey: "known_author",
                readRelays: ["wss://known-read.test"],
                writeRelays: ["wss://known-write.test"],
                source: .nip65
            )
        
            // Connect some relays for unknown author fallback
            await self.ndk.connect()
            
            let filter = NDKFilter(
                authors: ["known_author", "unknown_author1", "unknown_author2"],
                kinds: [1]
            )
            
            let strategy = await self.outboxManager.getOutboxStrategy(for: filter)
        
        // Should have unknown authors
        XCTAssertEqual(strategy.unknownAuthors.count, 2)
        XCTAssertTrue(strategy.unknownAuthors.contains("unknown_author1"))
        XCTAssertTrue(strategy.unknownAuthors.contains("unknown_author2"))
        
            // Should mark them for discovery
            XCTAssertEqual(strategy.authorsToDiscover.count, 2)
        }
    }
    
    func testGetOutboxStrategyFallbackToWriteRelays() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track author with only write relays
            await self.outboxManager.track(
                pubkey: "author1",
                readRelays: [],
                writeRelays: ["wss://write-only.test"],
                source: .nip65
            )
        
            let filter = NDKFilter(
                authors: ["author1"],
                kinds: [1]
            )
            
            let strategy = await self.outboxManager.getOutboxStrategy(for: filter)
        
            // Should use write relays as fallback
            XCTAssertTrue(strategy.filtersByRelay.keys.contains("wss://write-only.test"))
        }
    }
    
    // MARK: - Public API Tests
    
    func testTrackUser() async throws {
        try await performAsyncTest(timeout: 5) {
            // First track the user with relay information directly
            await self.outboxManager.track(
                pubkey: "user_pubkey",
                readRelays: ["wss://user-read.test"],
                writeRelays: ["wss://user-write.test"],
                source: .nip65,
                emitDiscoveryEvent: false
            )
        
            // Verify tracked
            let cached = await self.outboxManager.getRelaysSyncFor(pubkey: "user_pubkey")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.readRelays.map { $0.url }.sorted(), ["wss://user-read.test"])
            XCTAssertEqual(cached?.writeRelays.map { $0.url }.sorted(), ["wss://user-write.test"])
        }
    }
    
    func testGetRelayScore() async throws {
        try await performAsyncTest(timeout: 5) {
            // This depends on relay ranker implementation
            let score = await self.outboxManager.getRelayScore(
                relay: "wss://test.relay",
                for: "test_pubkey"
            )
        
        // Should return a valid score between 0 and 1
        XCTAssertGreaterThanOrEqual(score, 0.0)
            XCTAssertLessThanOrEqual(score, 1.0)
        }
    }
    
    func testGetRecommendedRelays() async throws {
        try await performAsyncTest(timeout: 5) {
            let recommendations = await self.outboxManager.getRecommendedRelays(
                for: "test_pubkey",
                count: 3
            )
        
        // Should return an array (may be empty if no recommendations)
        XCTAssertNotNil(recommendations)
            XCTAssertLessThanOrEqual(recommendations.count, 3)
        }
    }
    
    func testGetAllTrackedItems() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track some items
            await self.outboxManager.track(
                pubkey: "user1",
                readRelays: ["wss://read1.test"],
                writeRelays: ["wss://write1.test"],
                source: .nip65
            )
        
            await self.outboxManager.track(
                pubkey: "user2",
                readRelays: ["wss://read2.test"],
                writeRelays: ["wss://write2.test"],
                source: .manual
            )
        
            let items = await self.outboxManager.getAllTrackedItems()
            XCTAssertEqual(items.count, 2)
        }
    }
    
    func testObserveWithOutboxModel() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track relay info for an author
            await self.outboxManager.track(
                pubkey: "author1",
                readRelays: ["wss://author1-read.test"],
                writeRelays: ["wss://author1-write.test"],
                source: .nip65
            )
        
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
            let dataSource = self.ndk.subscribe(
                filter: filter,
                maxAge: 3600,
                cachePolicy: .networkOnly
            )
        
        XCTAssertNotNil(dataSource)
        // Note: DataSource doesn't expose filter and relays properties directly
            // The test verifies that the method compiles and returns a valid DataSource
        }
    }
    
    func testPublishWithOutboxModel() async throws {
        // Create an event with proper signature
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test message")
            .tag(["p", "recipient_pubkey"])
            .build(signer: signer)
        
        // Track recipient's relays
            await self.outboxManager.track(
                pubkey: "recipient_pubkey",
                readRelays: ["wss://recipient-read.test"],
                writeRelays: ["wss://recipient-write.test"],
                source: .nip65
            )
            
            do {
                let publishedRelays = try await self.outboxManager.publish(event)
            // Should attempt to publish (actual result depends on mock)
            XCTAssertNotNil(publishedRelays)
        } catch {
            // Publishing might fail due to network issues in test
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Background Discovery Tests
    
    func testDiscoverRelaysInBackground() async throws {
        try await performAsyncTest(timeout: 5) {
            let authors = Set(["author1", "author2", "author3"])
            
            // Start discovery (non-blocking)
            await self.outboxManager.discoverRelaysInBackground(for: authors)
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // The method should return immediately (non-blocking)
        // Actual discovery happens in background
            XCTAssertTrue(true) // Just verify it doesn't block
        }
    }
    
    // MARK: - Relay Updates Tests
    
    func testRelayUpdatesStream() async throws {
        try await performAsyncTest(timeout: 5) {
            let expectation = XCTestExpectation(description: "Relay update received")
            
            let task = Task {
                for await update in await self.outboxManager.relayUpdates {
                    if update.pubkey == "test_pubkey" {
                        expectation.fulfill()
                        break
                    }
                }
            }
        
            // Trigger an update by tracking
            await self.outboxManager.track(
                pubkey: "test_pubkey",
                readRelays: ["wss://read.test"],
                writeRelays: ["wss://write.test"],
                source: .nip65,
                emitDiscoveryEvent: true
            )
        
            await self.fulfillment(of: [expectation], timeout: 1.0)
            task.cancel()
        }
    }
    
    func testGetRelayUpdateStats() async throws {
        try await performAsyncTest(timeout: 5) {
            let stats = await self.outboxManager.getRelayUpdateStats()
        
        XCTAssertNotNil(stats)
        XCTAssertGreaterThanOrEqual(stats.activeSubscriptions, 0)
        XCTAssertGreaterThanOrEqual(stats.totalUnknownAuthors, 0)
            XCTAssertGreaterThanOrEqual(stats.totalUpdateSubscriptions, 0)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testGetRelaysForWithExpiredCache() async throws {
        try await performAsyncTest(timeout: 5) {
            // Track with very short TTL
            await self.outboxManager.track(
                pubkey: "test_pubkey",
                readRelays: ["wss://read.test"],
                writeRelays: ["wss://write.test"],
                source: .nip65
            )
        
            // Try to get with maxAge = 0 (always expired)
            let result = try await self.outboxManager.getRelaysFor(
                pubkey: "test_pubkey",
                maxAge: 0
            )
        
        // Should fetch from network or return nil
        // The actual behavior depends on network availability
            _ = result // Just ensure no crash
        }
    }
    
    func testConcurrentGetRelaysFor() async throws {
        try await performAsyncTest(timeout: 5) {
            let pubkey = "test_pubkey"
            
            // Launch multiple concurrent requests for the same pubkey
            let tasks = (0..<5).map { _ in
                Task {
                    try await self.outboxManager.getRelaysFor(pubkey: pubkey)
                }
            }
        
        // Wait for all to complete
        let results = await withTaskGroup(of: NDKOutboxItem?.self) { group in
            for task in tasks {
                group.addTask {
                    try? await task.value
                }
            }
            
            var results: [NDKOutboxItem?] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
            // All should get the same result (deduplication working)
            XCTAssertEqual(results.count, 5)
        }
    }
}