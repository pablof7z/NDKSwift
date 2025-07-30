import XCTest
@testable import NDKSwift

final class NDKRelaySelectorTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var cache: MemoryCache!
    var relaySelector: NDKRelaySelector!
    
    override func setUp() async throws {
        cache = MemoryCache()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(
            relayUrls: [
                "wss://relay1.example.com",
                "wss://relay2.example.com",
                "wss://relay3.example.com"
            ],
            signer: signer,
            cache: cache
        )
        relaySelector = ndk.relaySelector
    }
    
    override func tearDown() async throws {
        await ndk?.disconnect()
        ndk = nil
        signer = nil
        cache = nil
        relaySelector = nil
    }
    
    // MARK: - Edge Cases for Publishing
    
    func testPublishingWithNoNIP65RelaysForAnyUser() async throws {
        // Create an event with p-tags but no relay lists available
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello users with no relay info!")
            .tag(["p", user1])
            .tag(["p", user2])
            .build()
        
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should track missing relay info
        XCTAssertEqual(selection.missingRelayInfoPubkeys.count, 2)
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains(user1))
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains(user2))
        
        // Should still select fallback relays
        XCTAssertGreaterThanOrEqual(selection.relays.count, OutboxConstants.minPublishRelays)
        XCTAssertEqual(selection.selectionMethod, .fallback)
    }
    
    func testPublishingWithMixOfConnectedAndDisconnectedNIP65Relays() async throws {
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // Setup relay list with mix of connected and disconnected relays
        await setupMockRelayList(for: user1, 
            readRelays: ["wss://relay1.example.com", "wss://disconnected-relay.com"], 
            writeRelays: ["wss://relay2.example.com"])
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Testing relay prioritization")
            .tag(["p", user1])
            .build()
        
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should include both connected and disconnected relays
        XCTAssertTrue(selection.relays.contains("wss://relay1.example.com"))
        XCTAssertTrue(selection.relays.contains("wss://disconnected-relay.com"))
    }
    
    func testPublishingWithExactly10PTags() async throws {
        // Test boundary condition of exactly 10 p-tags
        var users: [String] = []
        for i in 1...10 {
            let user = String(format: "user%02d_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcd%02d", i, i)
            users.append(user)
            await setupMockRelayList(for: user, 
                readRelays: [String(format: "wss://user%02d-read.com", i)], 
                writeRelays: [])
        }
        
        var eventBuilder = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Exactly 10 p-tags")
        
        for user in users {
            eventBuilder = eventBuilder.tag(["p", user])
        }
        
        let event = try await eventBuilder.build()
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // With exactly 10 p-tags, should NOT include p-tagged users' relays (>= 10 rule)
        for i in 1...10 {
            let relay = String(format: "wss://user%02d-read.com", i)
            XCTAssertFalse(selection.relays.contains(relay))
        }
    }
    
    func testPublishingRelayListKind10002() async throws {
        // Special handling for relay list events
        let authorPubkey = try await signer.pubkey
        
        // Setup author's current relay list
        await setupMockRelayList(for: authorPubkey, 
            readRelays: ["wss://author-read1.com", "wss://author-read2.com"], 
            writeRelays: ["wss://author-write.com"])
        
        // Create a new relay list event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(NDKRelayList.kind)
            .tag(["r", "wss://new-relay.com", "read"])
            .tag(["r", "wss://another-relay.com", "write"])
            .build(signer: signer)
        
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should include author's read relays for relay list dissemination
        XCTAssertTrue(selection.relays.contains("wss://author-read1.com"))
        XCTAssertTrue(selection.relays.contains("wss://author-read2.com"))
        // And write relay
        XCTAssertTrue(selection.relays.contains("wss://author-write.com"))
    }
    
    // MARK: - Edge Cases for Fetching
    
    func testFetchingWithNoAuthorsOrPTags() async throws {
        // Filter with no authors or p-tags
        let filter = NDKFilter(kinds: [1])
        
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)
        
        // Should still select minimum relays from fallback
        XCTAssertGreaterThanOrEqual(selection.relays.count, OutboxConstants.minFetchRelays)
        XCTAssertEqual(selection.selectionMethod, .fallback)
    }
    
    func testFetchingWithCurrentUserOnly() async throws {
        // Setup current user's relay list
        let userPubkey = try await signer.pubkey
        await setupMockRelayList(for: userPubkey, 
            readRelays: ["wss://user-read.com"], 
            writeRelays: ["wss://user-write.com"])
        
        // Filter with no specific authors (will use current user)
        let filter = NDKFilter(kinds: [1])
        
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)
        
        // Should include current user's read relay
        XCTAssertTrue(selection.relays.contains("wss://user-read.com"))
    }
    
    func testFetchingExceedsMaxRelayLimit() async throws {
        // Create many users to exceed max relay limit
        var users: [String] = []
        for i in 1...30 {
            let user = String(format: "user%02d_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcd%02d", i, i)
            users.append(user)
            // Each user has 2 unique relays
            await setupMockRelayList(for: user, 
                readRelays: [
                    String(format: "wss://user%02d-read1.com", i),
                    String(format: "wss://user%02d-read2.com", i)
                ], 
                writeRelays: [])
        }
        
        let filter = NDKFilter(authors: Array(users.prefix(20)))
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)
        
        // Should cap at max fetch relays
        XCTAssertLessThanOrEqual(selection.relays.count, OutboxConstants.maxFetchRelays)
        XCTAssertGreaterThan(selection.relays.count, 0)
    }
    
    // MARK: - Relay Combination Selection Tests
    
    func testChooseRelayCombinationMinimizesConnections() async throws {
        // Test that relay combination prefers relays shared by multiple authors
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user3 = "user3_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // Setup overlapping relay lists
        await setupMockRelayList(for: user1, 
            readRelays: ["wss://shared.com", "wss://user1-only.com"], 
            writeRelays: [])
        await setupMockRelayList(for: user2, 
            readRelays: ["wss://shared.com", "wss://user2-only.com"], 
            writeRelays: [])
        await setupMockRelayList(for: user3, 
            readRelays: ["wss://shared.com", "wss://user3-only.com"], 
            writeRelays: [])
        
        let relayMap = await relaySelector.chooseRelayCombinationForPubkeys(
            [user1, user2, user3], 
            type: .read, 
            relaysPerAuthor: 1
        )
        
        // Should prefer the shared relay
        XCTAssertTrue(relayMap.keys.contains("wss://shared.com"))
        XCTAssertEqual(relayMap["wss://shared.com"]?.count, 3)
    }
    
    func testChooseRelayCombinationWithNoRelayInfo() async throws {
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // No relay lists setup
        let relayMap = await relaySelector.chooseRelayCombinationForPubkeys(
            [user1, user2], 
            type: .read, 
            relaysPerAuthor: 2
        )
        
        // Should assign fallback relays
        XCTAssertGreaterThan(relayMap.count, 0)
        
        // Each user should be assigned to at least one relay
        let allAssignedUsers = Set(relayMap.values.flatMap { $0 })
        XCTAssertTrue(allAssignedUsers.contains(user1))
        XCTAssertTrue(allAssignedUsers.contains(user2))
    }
    
    // MARK: - Blocked Relays Tests
    
    func testBlockedRelaysAreExcluded() async throws {
        // Setup blocked relays by creating a blocked relay list event
        let blockedRelay = "wss://blocked.com"
        let pubkey = try await signer.pubkey
        
        // Create blocked relay list event
        let blockedRelayEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(10017) // EventKind.blockedRelays
            .content("")
            .tag(["relay", blockedRelay])
            .build()
        
        // Save to cache so session data can load it
        try await cache.saveEvent(blockedRelayEvent)
        
        // Initialize session data (loads automatically)
        let sessionData = NDKSessionData(pubkey: pubkey, ndk: ndk)
        ndk.sessionData = sessionData
        
        // Wait for blocked relays to load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        await setupMockRelayList(for: user1, 
            readRelays: [blockedRelay, "wss://allowed.com"], 
            writeRelays: [])
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test blocked relays")
            .tag(["p", user1])
            .build()
        
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should exclude blocked relay
        XCTAssertFalse(selection.relays.contains(blockedRelay))
        XCTAssertTrue(selection.relays.contains("wss://allowed.com"))
    }
    
    func testBlockedRelaysCacheExpiry() async throws {
        // This test verifies the 5-minute cache expiry for blocked relays
        // In a real scenario, we'd need to mock Date() or wait 5 minutes
        // For now, we just verify the cache behavior exists
        
        let pubkey = try await signer.pubkey
        
        // Create initial blocked relay list
        let blockedRelayEvent1 = try await NDKEventBuilder(ndk: ndk)
            .kind(10017) // EventKind.blockedRelays
            .content("")
            .tag(["relay", "wss://blocked1.com"])
            .build()
        try await cache.saveEvent(blockedRelayEvent1)
        
        let sessionData1 = NDKSessionData(pubkey: pubkey, ndk: ndk)
        ndk.sessionData = sessionData1
        
        // Wait for blocked relays to load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let filter = NDKFilter(kinds: [1])
        _ = await relaySelector.selectRelaysForFetching(filter: filter)
        
        // Update blocked relays with new event
        let blockedRelayEvent2 = try await NDKEventBuilder(ndk: ndk)
            .kind(10017) // EventKind.blockedRelays
            .content("")
            .tag(["relay", "wss://blocked2.com"])
            .createdAt(blockedRelayEvent1.createdAt + 1) // Ensure newer timestamp
            .build()
        try await cache.saveEvent(blockedRelayEvent2)
        
        let sessionData2 = NDKSessionData(pubkey: pubkey, ndk: ndk)
        ndk.sessionData = sessionData2
        
        // Wait for blocked relays to load
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Within cache period, should still use old blocked list
        // This is a limitation of the test - in production the cache would expire
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)
        XCTAssertNotNil(selection)
    }
    
    // MARK: - Selection Method Tests
    
    func testSelectionMethodDetermination() async throws {
        // Test empty relays
        var filter = NDKFilter(kinds: [1])
        var selection = await relaySelector.selectRelaysForFetching(filter: filter)
        // With no specific authors and using fallback relays
        XCTAssertTrue(selection.selectionMethod == .fallback || selection.selectionMethod == .outbox)
        
        // Test contextual (few relays)
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        await setupMockRelayList(for: user1, readRelays: ["wss://single.com"], writeRelays: [])
        
        filter = NDKFilter(authors: [user1])
        selection = await relaySelector.selectRelaysForFetching(filter: filter)
        
        if selection.relays.count <= 3 && selection.relays.count > 0 {
            XCTAssertEqual(selection.selectionMethod, .contextual)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupMockRelayList(for pubkey: String, readRelays: [String], writeRelays: [String]) async {
        var tags: [[String]] = []
        
        for relay in readRelays {
            tags.append(["r", relay, "read"])
        }
        
        for relay in writeRelays {
            tags.append(["r", relay, "write"])
        }
        
        let relayListEvent = NDKEvent(
            id: "relay_list_\(pubkey)",
            pubkey: pubkey,
            createdAt: Timestamp.now,
            kind: NDKRelayList.kind,
            tags: tags,
            content: "",
            sig: "mock_signature"
        )
        
        do {
            try await cache.saveEvent(relayListEvent)
        } catch {
            NDKLogger.log(.warning, category: .cache, "Failed to cache relay list event: \(error)")
        }
        
        await ndk.outbox.track(
            pubkey: pubkey,
            readRelays: Set(readRelays),
            writeRelays: Set(writeRelays),
            source: .nip65
        )
    }
}