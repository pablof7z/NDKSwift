import XCTest
@testable import NDKSwiftCore

// DISABLED: This test file needs to be rewritten as it attempts to mock final classes and actors
// which is not possible in Swift. The tests should be rewritten to use proper test doubles
// or test against the public API instead of trying to mock internal components.
/*
/// Comprehensive tests for the Outbox Model implementation
/// Tests cover all nuances documented in Outbox.md and discussed during the refactoring
final class OutboxModelTests: XCTestCase {
    var ndk: NDK!
    var mockPool: MockRelayPool!
    var mockCache: MockCache!
    var mockSigner: MockSigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockSigner = MockSigner()
        mockCache = MockCache()
        mockPool = MockRelayPool()
        
        // Create NDK with mock components
        ndk = NDK(
            signer: mockSigner,
            relayPool: mockPool,
            cache: mockCache,
            outboxEnabled: true
        )
    }
    
    override func tearDown() async throws {
        ndk = nil
        mockPool = nil
        mockCache = nil
        mockSigner = nil
        try await super.tearDown()
    }
    
    // MARK: - Core Principle Tests
    
    func testUserControlFirst_ExplicitRelaysOverrideOutbox() async throws {
        // When user specifies explicit relays, outbox should be bypassed entirely
        let explicitRelays: Set<RelayURL> = ["wss://explicit1.relay", "wss://explicit2.relay"]
        let filter = NDKFilter(authors: ["author1"], kinds: [1])
        
        // Start subscription with explicit relays
        let dataSource = ndk.subscribe(
            filter: filter,
            relays: explicitRelays,
            cachePolicy: .networkOnly
        )
        
        // Verify only explicit relays are used (no outbox discovery)
        await fulfillment(of: [mockPool.relaysUsedExpectation], timeout: 1.0)
        XCTAssertEqual(mockPool.lastUsedRelays, explicitRelays)
        XCTAssertFalse(mockPool.relayDiscoveryTriggered)
    }
    
    func testPerAuthorScaling_TwoRelaysPerAuthor() async throws {
        // Test that relay selection scales with number of authors (2 per author)
        let authors = ["author1", "author2", "author3"]
        let filter = NDKFilter(authors: authors, kinds: [1])
        
        // Set up known relay preferences for each author
        for (index, author) in authors.enumerated() {
            let relayList = createRelayList(
                for: author,
                writeRelays: [
                    "wss://write\(index*2+1).relay",
                    "wss://write\(index*2+2).relay",
                    "wss://write\(index*2+3).relay" // Extra relay to test selection
                ]
            )
            await mockCache.saveEvent(relayList)
        }
        
        // Start subscription without explicit relays (triggers outbox)
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.relaysSelectedExpectation], timeout: 1.0)
        
        // Should select 2 relays per author = 6 total
        XCTAssertEqual(mockPool.selectedRelays.count, 6)
        
        // Verify 2 relays selected per author
        for author in authors {
            let authorRelays = mockPool.selectedRelaysPerAuthor[author] ?? []
            XCTAssertEqual(authorRelays.count, 2, "Should select exactly 2 relays for \(author)")
        }
    }
    
    func testConnectionEfficiency_PrioritizesAlreadyConnected() async throws {
        // Test that already-connected relays are prioritized over new connections
        let connectedRelays: Set<RelayURL> = ["wss://connected1.relay", "wss://connected2.relay"]
        let availableRelays: Set<RelayURL> = ["wss://new1.relay", "wss://new2.relay", "wss://new3.relay"]
        
        mockPool.connectedRelays = connectedRelays
        
        let author = "author1"
        let relayList = createRelayList(
            for: author,
            writeRelays: Array(connectedRelays + availableRelays)
        )
        await mockCache.saveEvent(relayList)
        
        let filter = NDKFilter(authors: [author], kinds: [1])
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.relaysSelectedExpectation], timeout: 1.0)
        
        // Should prefer the 2 already-connected relays
        let selectedRelays = mockPool.selectedRelaysPerAuthor[author] ?? []
        XCTAssertEqual(selectedRelays, Array(connectedRelays))
    }
    
    // MARK: - Subscription Handling Tests
    
    func testInitialSetup_KnownVsUnknownAuthors() async throws {
        // Test proper handling of known vs unknown authors at subscription creation
        let knownAuthor = "known-author"
        let unknownAuthor = "unknown-author"
        
        // Set up relay list for known author only
        let relayList = createRelayList(
            for: knownAuthor,
            writeRelays: ["wss://known1.relay", "wss://known2.relay"]
        )
        await mockCache.saveEvent(relayList)
        
        let filter = NDKFilter(authors: [knownAuthor, unknownAuthor], kinds: [1])
        let dataSource = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        // Track subscription creation
        var subscriptionCount = 0
        for await update in dataSource.relayUpdates {
            if case .subscriptionCreated = update {
                subscriptionCount += 1
            }
        }
        
        // Should create subscriptions for known author immediately
        XCTAssertTrue(mockPool.subscriptionsCreatedFor.contains(knownAuthor))
        
        // Should mark unknown author for discovery
        XCTAssertTrue(ndk.outbox.authorsMarkedForDiscovery.contains(unknownAuthor))
        
        // Should use fallback relays for unknown author
        XCTAssertTrue(mockPool.fallbackRelaysUsedFor.contains(unknownAuthor))
    }
    
    func testBackgroundDiscovery_NonBlocking() async throws {
        // Test that subscription receives events while discovery happens
        let unknownAuthor = "unknown-author"
        let filter = NDKFilter(authors: [unknownAuthor], kinds: [1])
        
        let dataSource = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        var receivedEvents: [NDKEvent] = []
        let eventExpectation = expectation(description: "Receive events during discovery")
        
        Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 2 {
                    eventExpectation.fulfill()
                    break
                }
            }
        }
        
        // Simulate events arriving from fallback relays
        let event1 = createTestEvent(author: unknownAuthor, content: "Event from fallback")
        await mockPool.simulateEventFromFallbackRelay(event1)
        
        // Simulate relay discovery completing
        await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        let relayList = createRelayList(
            for: unknownAuthor,
            writeRelays: ["wss://discovered1.relay", "wss://discovered2.relay"]
        )
        await ndk.outbox.handleRelayDiscovery(for: unknownAuthor, relayList: relayList)
        
        // Simulate event from discovered relay
        let event2 = createTestEvent(author: unknownAuthor, content: "Event from discovered")
        await mockPool.simulateEventFromRelay(event2, relay: "wss://discovered1.relay")
        
        await fulfillment(of: [eventExpectation], timeout: 2.0)
        
        // Should receive events from both fallback and discovered relays
        XCTAssertEqual(receivedEvents.count, 2)
        XCTAssertTrue(receivedEvents.contains { $0.content.contains("fallback") })
        XCTAssertTrue(receivedEvents.contains { $0.content.contains("discovered") })
    }
    
    func testDynamicUpdates_CreatesEnhancedRequirements() async throws {
        // Test that enhanced requirements are created when relays are discovered
        let author = "author-to-discover"
        let filter = NDKFilter(authors: [author], kinds: [1])
        
        // Start with unknown author
        let handle = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        // Wait for initial setup
        await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Simulate relay discovery
        let discoveredRelays: Set<RelayURL> = ["wss://new1.relay", "wss://new2.relay"]
        let relayList = createRelayList(for: author, writeRelays: Array(discoveredRelays))
        
        // This should trigger enhanced requirement creation
        await ndk.dataRequirementManager.handleRelayDiscovery(
            authors: [author],
            relays: discoveredRelays
        )
        
        // Verify enhanced requirements were created
        let enhancedRequirements = await ndk.dataRequirementManager.getEnhancedRequirements(for: handle.id)
        XCTAssertEqual(enhancedRequirements.count, 2) // One per discovered relay
        
        // Verify enhanced subscription IDs follow the pattern
        for requirement in enhancedRequirements {
            XCTAssertTrue(requirement.subscriptionId.contains("_enhanced_"))
        }
    }
    
    // MARK: - Publishing Tests
    
    func testPublishing_ImmediateActionWithFallback() async throws {
        // Test that publishing happens immediately without waiting for discovery
        let author = mockSigner.publicKey
        let unknownPTaggedUser = "unknown-user"
        
        let event = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test message")
            .tag(["p", unknownPTaggedUser])
            .build()
        
        let publishExpectation = expectation(description: "Publish completes")
        var publishedRelays: Set<RelayURL> = []
        
        Task {
            publishedRelays = try await ndk.publish(event)
            publishExpectation.fulfill()
        }
        
        // Should not wait for discovery
        await fulfillment(of: [publishExpectation], timeout: 0.5)
        
        // Should use fallback relays immediately
        XCTAssertFalse(publishedRelays.isEmpty)
        XCTAssertTrue(publishedRelays.isSubset(of: mockPool.fallbackRelays))
    }
    
    func testPublishing_PTagHandling() async throws {
        // Test p-tag handling: <10 includes read relays, >=10 skips
        let author = mockSigner.publicKey
        
        // Set up relay lists for p-tagged users
        for i in 0..<15 {
            let user = "user\(i)"
            let relayList = createRelayList(
                for: user,
                readRelays: ["wss://read\(i).relay"]
            )
            await mockCache.saveEvent(relayList)
        }
        
        // Test with <10 p-tags
        let event9Tags = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Few p-tags")
        for i in 0..<9 {
            event9Tags.tag(["p", "user\(i)"])
        }
        
        let relays9 = try await ndk.publish(event9Tags.build())
        
        // Should include read relays from all 9 users
        for i in 0..<9 {
            XCTAssertTrue(relays9.contains("wss://read\(i).relay"))
        }
        
        // Test with >=10 p-tags
        let event15Tags = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Many p-tags")
        for i in 0..<15 {
            event15Tags.tag(["p", "user\(i)"])
        }
        
        let relays15 = try await ndk.publish(event15Tags.build())
        
        // Should NOT include p-tagged users' relays
        for i in 0..<15 {
            XCTAssertFalse(relays15.contains("wss://read\(i).relay"))
        }
    }
    
    func testPublishing_BackgroundDiscoveryWithTimeout() async throws {
        // Test that background discovery respects 5-second timeout
        let author = mockSigner.publicKey
        let unknownUser = "slow-discovery-user"
        
        let event = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test with slow discovery")
            .tag(["p", unknownUser])
            .build()
        
        // Configure mock to delay discovery beyond timeout
        mockPool.discoveryDelay = 6.0 // 6 seconds
        
        let startTime = Date()
        _ = try await ndk.publish(event)
        let endTime = Date()
        
        // Should complete within ~5 seconds despite slow discovery
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 5.5)
        
        // Should still attempt discovery (non-blocking)
        XCTAssertTrue(ndk.outbox.discoveryAttempted(for: unknownUser))
    }
    
    // MARK: - Relay Selection Tests
    
    func testRelaySelection_UnifiedVsPerRelay() async throws {
        // Test intelligent grouping when authors share relays
        let sharedRelay = "wss://shared.relay"
        let author1Relay = "wss://author1.relay"
        let author2Relay = "wss://author2.relay"
        
        // Authors 1 and 2 share a relay
        let relayList1 = createRelayList(
            for: "author1",
            writeRelays: [sharedRelay, author1Relay]
        )
        let relayList2 = createRelayList(
            for: "author2",
            writeRelays: [sharedRelay, author2Relay]
        )
        let relayList3 = createRelayList(
            for: "author3",
            writeRelays: ["wss://author3a.relay", "wss://author3b.relay"]
        )
        
        await mockCache.saveEvent(relayList1)
        await mockCache.saveEvent(relayList2)
        await mockCache.saveEvent(relayList3)
        
        let filter = NDKFilter(authors: ["author1", "author2", "author3"], kinds: [1])
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.subscriptionGroupingExpectation], timeout: 1.0)
        
        // Should create optimized subscription groups
        let groups = mockPool.subscriptionGroups
        
        // Should have group for shared relay with both authors
        let sharedGroup = groups.first { $0.relays.contains(sharedRelay) }
        XCTAssertNotNil(sharedGroup)
        XCTAssertEqual(sharedGroup?.authors, ["author1", "author2"])
        
        // Should have separate group for author3
        let author3Group = groups.first { $0.authors.contains("author3") }
        XCTAssertNotNil(author3Group)
        XCTAssertEqual(author3Group?.authors, ["author3"])
    }
    
    // MARK: - Enhanced Requirements Tests
    
    func testEnhancedRequirements_AsyncStreamPattern() async throws {
        // Test the new AsyncStream-based enhanced requirements implementation
        let author = "dynamic-author"
        let initialRelay = "wss://initial.relay"
        let discoveredRelays: Set<RelayURL> = ["wss://discovered1.relay", "wss://discovered2.relay"]
        
        // Set up initial relay for author
        let initialRelayList = createRelayList(for: author, writeRelays: [initialRelay])
        await mockCache.saveEvent(initialRelayList)
        
        let filter = NDKFilter(authors: [author], kinds: [1])
        let dataSource = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        var receivedEvents: [NDKEvent] = []
        let enhancedEventExpectation = expectation(description: "Receive enhanced events")
        
        Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 3 {
                    enhancedEventExpectation.fulfill()
                    break
                }
            }
        }
        
        // Event from initial relay
        let event1 = createTestEvent(author: author, content: "From initial relay")
        await mockPool.simulateEventFromRelay(event1, relay: initialRelay)
        
        // Simulate discovery of new relays
        await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        await ndk.dataRequirementManager.handleRelayDiscovery(
            authors: [author],
            relays: discoveredRelays
        )
        
        // Events from discovered relays (through enhanced requirements)
        let event2 = createTestEvent(author: author, content: "From discovered1")
        let event3 = createTestEvent(author: author, content: "From discovered2")
        await mockPool.simulateEventFromRelay(event2, relay: "wss://discovered1.relay")
        await mockPool.simulateEventFromRelay(event3, relay: "wss://discovered2.relay")
        
        await fulfillment(of: [enhancedEventExpectation], timeout: 2.0)
        
        // Should receive events from all relays
        XCTAssertEqual(receivedEvents.count, 3)
        XCTAssertTrue(receivedEvents.contains { $0.content.contains("initial") })
        XCTAssertTrue(receivedEvents.contains { $0.content.contains("discovered1") })
        XCTAssertTrue(receivedEvents.contains { $0.content.contains("discovered2") })
    }
    
    func testEnhancedRequirements_ProperCleanup() async throws {
        // Test that enhanced requirements are properly cleaned up
        let author = "cleanup-test-author"
        let filter = NDKFilter(authors: [author], kinds: [1])
        
        let handle = ndk.subscribe(filter: filter, cachePolicy: .networkOnly).handle
        
        // Trigger relay discovery to create enhanced requirements
        await ndk.dataRequirementManager.handleRelayDiscovery(
            authors: [author],
            relays: ["wss://enhanced.relay"]
        )
        
        // Verify enhanced requirements exist
        let enhancedBefore = await ndk.dataRequirementManager.getEnhancedRequirements(for: handle.id)
        XCTAssertFalse(enhancedBefore.isEmpty)
        
        // Cancel the main requirement
        await handle.cancel()
        
        // Verify enhanced requirements are cleaned up
        let enhancedAfter = await ndk.dataRequirementManager.getEnhancedRequirements(for: handle.id)
        XCTAssertTrue(enhancedAfter.isEmpty)
    }
    
    // MARK: - Cache Integration Tests
    
    func testCacheObservation_CrossFingerprintDelivery() async throws {
        // Test that cache-only subscriptions receive events from network subscriptions
        let author = "cache-test-author"
        let relay = "wss://network.relay"
        
        // Set up relay list
        let relayList = createRelayList(for: author, writeRelays: [relay])
        await mockCache.saveEvent(relayList)
        
        // Create cache-only subscription with broad filter
        let broadFilter = NDKFilter(kinds: [1])
        let cacheDataSource = ndk.subscribe(
            filter: broadFilter,
            cachePolicy: .cacheOnly
        )
        
        // Create network subscription with specific filter
        let specificFilter = NDKFilter(authors: [author], kinds: [1], limit: 10)
        let networkDataSource = ndk.subscribe(
            filter: specificFilter,
            cachePolicy: .networkOnly
        )
        
        var cacheReceivedEvents: [NDKEvent] = []
        let cacheEventExpectation = expectation(description: "Cache receives event")
        
        Task {
            for await event in cacheDataSource.events {
                cacheReceivedEvents.append(event)
                cacheEventExpectation.fulfill()
                break
            }
        }
        
        // Simulate event from network matching specific filter
        let event = createTestEvent(author: author, content: "Network event", kind: 1)
        await mockPool.simulateEventFromRelay(event, relay: relay)
        
        await fulfillment(of: [cacheEventExpectation], timeout: 1.0)
        
        // Cache-only subscription should receive the event
        XCTAssertEqual(cacheReceivedEvents.count, 1)
        XCTAssertEqual(cacheReceivedEvents.first?.id, event.id)
    }
    
    // MARK: - Edge Case Tests
    
    func testRelayListConflicts_UsesMostRecent() async throws {
        // Test handling of conflicting relay lists
        let author = "conflict-author"
        
        // Create two relay lists with different timestamps
        let olderList = createRelayList(
            for: author,
            writeRelays: ["wss://old1.relay", "wss://old2.relay"],
            createdAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        let newerList = createRelayList(
            for: author,
            writeRelays: ["wss://new1.relay", "wss://new2.relay"],
            createdAt: Date() // Now
        )
        
        // Save in reverse order to test timestamp handling
        await mockCache.saveEvent(newerList)
        await mockCache.saveEvent(olderList)
        
        let filter = NDKFilter(authors: [author], kinds: [1])
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.relaysSelectedExpectation], timeout: 1.0)
        
        // Should use relays from newer list
        let selectedRelays = mockPool.selectedRelaysPerAuthor[author] ?? []
        XCTAssertTrue(selectedRelays.contains("wss://new1.relay"))
        XCTAssertTrue(selectedRelays.contains("wss://new2.relay"))
        XCTAssertFalse(selectedRelays.contains("wss://old1.relay"))
    }
    
    func testCircularDependencies_HandledGracefully() async throws {
        // Test circular relay dependencies
        let authorA = "author-a"
        let authorB = "author-b"
        
        // A's relay list is only on B's relays
        let relayListA = createRelayList(
            for: authorA,
            writeRelays: ["wss://a.relay"]
        )
        // B's relay list is only on A's relays
        let relayListB = createRelayList(
            for: authorB,
            writeRelays: ["wss://b.relay"]
        )
        
        // Simulate circular dependency scenario
        mockCache.circularDependency = [
            authorA: "wss://b.relay",
            authorB: "wss://a.relay"
        ]
        
        let filter = NDKFilter(authors: [authorA, authorB], kinds: [1])
        let dataSource = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        // Should not hang or crash
        let timeoutExpectation = expectation(description: "Operation completes")
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            timeoutExpectation.fulfill()
        }
        
        await fulfillment(of: [timeoutExpectation], timeout: 2.0)
        
        // Should fall back to default relays
        XCTAssertTrue(mockPool.fallbackRelaysUsed)
    }
    
    func testMissingRelayLists_UsesFallback() async throws {
        // Test users without relay lists
        let userWithoutList = "no-relay-list-user"
        let filter = NDKFilter(authors: [userWithoutList], kinds: [1])
        
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.relaysUsedExpectation], timeout: 1.0)
        
        // Should use fallback relays
        XCTAssertTrue(mockPool.fallbackRelaysUsedFor.contains(userWithoutList))
        XCTAssertEqual(mockPool.lastUsedRelays, mockPool.fallbackRelays)
    }
    
    // MARK: - Performance Tests
    
    func testLargeScaleSubscriptions_HandlesEfficiently() async throws {
        // Test with many authors and relays
        let authorCount = 100
        let relaysPerAuthor = 50
        
        var authors: [String] = []
        for i in 0..<authorCount {
            let author = "author\(i)"
            authors.append(author)
            
            var relays: [String] = []
            for j in 0..<relaysPerAuthor {
                relays.append("wss://relay\(i)-\(j).relay")
            }
            
            let relayList = createRelayList(for: author, writeRelays: relays)
            await mockCache.saveEvent(relayList)
        }
        
        let startTime = Date()
        let filter = NDKFilter(authors: authors, kinds: [1])
        _ = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        await fulfillment(of: [mockPool.relaysSelectedExpectation], timeout: 2.0)
        let endTime = Date()
        
        // Should complete relay selection quickly
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 0.5) // 500ms for 100 authors
        
        // Should respect per-author limits (2 relays per author)
        let totalSelectedRelays = mockPool.selectedRelays.count
        XCTAssertLessThanOrEqual(totalSelectedRelays, authorCount * 2)
    }
    
    func testReconnectionEfficiency_O1Lookup() async throws {
        // Test efficient subscription replay on reconnection
        let relayCount = 50
        let subscriptionsPerRelay = 100
        
        // Create many subscriptions across many relays
        for i in 0..<relayCount {
            let relay = "wss://relay\(i).relay"
            for j in 0..<subscriptionsPerRelay {
                let filter = NDKFilter(ids: ["event\(i)-\(j)"])
                _ = ndk.subscribe(filter: filter, relays: [relay])
            }
        }
        
        // Simulate relay disconnection and reconnection
        let testRelay = "wss://relay25.relay"
        let startTime = Date()
        await mockPool.simulateReconnection(of: testRelay)
        let lookupTime = Date().timeIntervalSince(startTime)
        
        // Should find relevant subscriptions in O(1) time
        XCTAssertLessThan(lookupTime, 0.001) // Less than 1ms
        
        // Should replay correct number of subscriptions
        let replayedCount = await mockPool.getReplayedSubscriptionCount(for: testRelay)
        XCTAssertEqual(replayedCount, subscriptionsPerRelay)
    }
    
    // MARK: - Helper Methods
    
    private func createRelayList(
        for pubkey: String,
        readRelays: [String] = [],
        writeRelays: [String] = [],
        createdAt: Date = Date()
    ) -> NDKEvent {
        var tags: [[String]] = []
        
        for relay in readRelays {
            tags.append(["r", relay])
        }
        for relay in writeRelays {
            tags.append(["r", relay, "write"])
        }
        
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(date: createdAt),
            kind: 10002,
            tags: tags,
            content: ""
        )
        event.id = event.calculateId()
        event.sig = "mock-signature"
        return event
    }
    
    private func createTestEvent(
        author: String,
        content: String,
        kind: UInt32 = 1
    ) -> NDKEvent {
        let event = NDKEvent(
            pubkey: author,
            createdAt: Timestamp(date: Date()),
            kind: kind,
            tags: [],
            content: content
        )
        event.id = event.calculateId()
        event.sig = "mock-signature"
        return event
    }
}

// MARK: - Mock Components

class MockRelayPool: NDKRelayPool {
    var connectedRelays: Set<RelayURL> = []
    var fallbackRelays: Set<RelayURL> = ["wss://fallback1.relay", "wss://fallback2.relay"]
    var selectedRelays: Set<RelayURL> = []
    var selectedRelaysPerAuthor: [String: [RelayURL]] = [:]
    var lastUsedRelays: Set<RelayURL> = []
    var relayDiscoveryTriggered = false
    var fallbackRelaysUsed = false
    var fallbackRelaysUsedFor: Set<String> = []
    var subscriptionsCreatedFor: Set<String> = []
    var subscriptionGroups: [SubscriptionGroup] = []
    var discoveryDelay: TimeInterval = 0.1
    
    // Expectations
    var relaysUsedExpectation = XCTestExpectation(description: "Relays used")
    var relaysSelectedExpectation = XCTestExpectation(description: "Relays selected")
    var subscriptionGroupingExpectation = XCTestExpectation(description: "Subscriptions grouped")
    
    struct SubscriptionGroup {
        let relays: Set<RelayURL>
        let authors: Set<String>
    }
    
    override func addRelayAndConnect(url: RelayURL, origin: RelayOrigin?) async -> NDKRelay? {
        connectedRelays.insert(url)
        return MockRelay(url: url)
    }
    
    override var connectedRelayURLs: Set<RelayURL> {
        get async { connectedRelays }
    }
    
    func simulateEventFromRelay(_ event: NDKEvent, relay: RelayURL) async {
        // Simulate event delivery
    }
    
    func simulateEventFromFallbackRelay(_ event: NDKEvent) async {
        fallbackRelaysUsed = true
        // Simulate event delivery
    }
    
    func simulateReconnection(of relay: RelayURL) async {
        // Simulate reconnection
    }
    
    func getReplayedSubscriptionCount(for relay: RelayURL) async -> Int {
        return 100 // Mock value
    }
}

class MockCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    var circularDependency: [String: String] = [:]
    
    func saveEvent(_ event: NDKEvent) async throws {
        events[event.id] = event
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        return events.values.filter { event in
            filter.matches(event: event)
        }
    }
    
    func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

class MockSigner: NDKSigner {
    let publicKey = "mock-public-key"
    
    func sign(_ event: inout NDKEvent) async throws {
        event.pubkey = publicKey
        event.sig = "mock-signature"
    }
}

class MockRelay: NDKRelay {
    let url: RelayURL
    
    init(url: RelayURL) {
        self.url = url
        super.init(url: url)
    }
}
*/
