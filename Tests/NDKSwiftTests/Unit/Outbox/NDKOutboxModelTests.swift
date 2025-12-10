import XCTest
@testable import NDKSwiftCore

final class NDKOutboxModelTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var cache: MemoryCache!
    
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
    }
    
    override func tearDown() async throws {
        await ndk?.disconnect()
        ndk = nil
        signer = nil
        cache = nil
    }
    
    // MARK: - NIP-65 Outbox Model Tests
    
    func testPublishingWithLessThan10PTags() async throws {
        // Create a mock relay list for each p-tagged user
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user3 = "user3_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // Mock relay lists for p-tagged users
        await setupMockRelayList(for: user1, readRelays: ["wss://user1-read1.com", "wss://user1-read2.com"], writeRelays: ["wss://user1-write1.com"])
        await setupMockRelayList(for: user2, readRelays: ["wss://user2-read1.com"], writeRelays: ["wss://user2-write1.com", "wss://user2-write2.com"])
        await setupMockRelayList(for: user3, readRelays: ["wss://user3-read1.com"], writeRelays: ["wss://user3-write1.com"])
        
        // Create an event with 3 p-tags (< 10)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello everyone!")
            .tag(["p", user1])
            .tag(["p", user2])
            .tag(["p", user3])
            .build()
        
        // Test relay selection
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should include read relays of all p-tagged users according to NIP-65
        let expectedReadRelays = Set([
            "wss://user1-read1.com",
            "wss://user1-read2.com",
            "wss://user2-read1.com", 
            "wss://user3-read1.com"
        ])
        
        // Check that p-tagged users' read relays are included
        for readRelay in expectedReadRelays {
            XCTAssertTrue(selection.relays.contains(readRelay), 
                         "Should include read relay \(readRelay) for p-tagged user")
        }
        
        // Should NOT include write relays of p-tagged users (only their read relays per NIP-65)
        let writeRelaysToNotInclude = Set([
            "wss://user1-write1.com",
            "wss://user2-write1.com",
            "wss://user2-write2.com",
            "wss://user3-write1.com"
        ])
        
        for writeRelay in writeRelaysToNotInclude {
            XCTAssertFalse(selection.relays.contains(writeRelay),
                          "Should NOT include write relay \(writeRelay) for p-tagged user per NIP-65")
        }
    }
    
    func testPublishingWith10OrMorePTags() async throws {
        // Setup author's relay list first
        let authorPubkey = try await signer.pubkey
        await setupMockRelayList(for: authorPubkey, readRelays: ["wss://author-read.com"], writeRelays: ["wss://author-write.com"])
        
        // Create 11 users to exceed the 10 p-tag limit
        var users: [String] = []
        for i in 1...11 {
            let user = String(format: "user%02d_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcd%02d", i, i)
            users.append(user)
            // Setup mock relay lists for each user
            await setupMockRelayList(for: user, readRelays: [String(format: "wss://user%02d-read.com", i)], writeRelays: [String(format: "wss://user%02d-write.com", i)])
        }
        
        // Create an event with 11 p-tags (>= 10)
        var eventBuilder = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello to many people!")
        
        for user in users {
            eventBuilder = eventBuilder.tag(["p", user])
        }
        
        let event = try await eventBuilder.build(signer: signer)
        
        // Test relay selection
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should NOT include read relays of p-tagged users when there are 10+ p-tags
        let shouldNotIncludeRelays = Set([
            "wss://user01-read.com",
            "wss://user02-read.com",
            "wss://user11-read.com"
        ])
        
        for readRelay in shouldNotIncludeRelays {
            XCTAssertFalse(selection.relays.contains(readRelay),
                          "Should NOT include read relay \(readRelay) when event has 10+ p-tags")
        }
        
        // Should primarily use author's own relays and general fallback relays
        XCTAssertGreaterThan(selection.relays.count, 0, "Should still select some relays for publishing")
    }
    
    func testOutboxModelWithUsersHavingOnlyWriteRelays() async throws {
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // Setup users with only write relays (no read relays)
        await setupMockRelayList(for: user1, readRelays: [], writeRelays: ["wss://user1-write1.com", "wss://user1-write2.com"])
        await setupMockRelayList(for: user2, readRelays: [], writeRelays: ["wss://user2-write1.com"])
        
        // Create an event with 2 p-tags (< 10)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello!")
            .tag(["p", user1])
            .tag(["p", user2])
            .build()
        
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should fallback to write relays when no read relays are available
        let expectedFallbackRelays = Set([
            "wss://user1-write1.com",
            "wss://user1-write2.com",
            "wss://user2-write1.com"
        ])
        
        for writeRelay in expectedFallbackRelays {
            XCTAssertTrue(selection.relays.contains(writeRelay),
                         "Should fallback to write relay \(writeRelay) when user has no read relays")
        }
    }
    
    func testOutboxModelWithMixedRelayAvailability() async throws {
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user2 = "user2_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        let user3 = "user3_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // User1: Has both read and write relays
        await setupMockRelayList(for: user1, readRelays: ["wss://user1-read.com"], writeRelays: ["wss://user1-write.com"])
        
        // User2: Has only write relays
        await setupMockRelayList(for: user2, readRelays: [], writeRelays: ["wss://user2-write.com"])
        
        // User3: No relay list available (will be in missingPubkeys)
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Mixed scenario!")
            .tag(["p", user1])
            .tag(["p", user2])
            .tag(["p", user3])
            .build()
        
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should include user1's read relay
        XCTAssertTrue(selection.relays.contains("wss://user1-read.com"))
        
        // Should include user2's write relay (fallback)
        XCTAssertTrue(selection.relays.contains("wss://user2-write.com"))
        
        // Should track user3 as missing relay info
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains(user3))
    }
    
    func testFetchingIgnoresOutboxPTagLimit() async throws {
        // Create 11 users
        var users: [String] = []
        for i in 1...11 {
            let user = String(format: "user%02d_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcd%02d", i, i)
            users.append(user)
            await setupMockRelayList(for: user, readRelays: [String(format: "wss://user%02d-read.com", i)], writeRelays: [String(format: "wss://user%02d-write.com", i)])
        }
        
        // Create a filter that would target events with many p-tags
        let filter = NDKFilter(
            kinds: [1],
            tags: ["p": Set(users)]
        )
        
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)
        
        // For fetching, should include read relays regardless of p-tag count
        let expectedReadRelays = Set([
            "wss://user01-read.com",
            "wss://user05-read.com",
            "wss://user11-read.com"
        ])
        
        for readRelay in expectedReadRelays {
            XCTAssertTrue(selection.relays.contains(readRelay),
                         "Fetching should include read relay \(readRelay) regardless of p-tag count")
        }
    }
    
    func testEventWithNoTags() async throws {
        // Setup author's relay list
        let authorPubkey = try await signer.pubkey
        await setupMockRelayList(for: authorPubkey, readRelays: ["wss://author-read.com"], writeRelays: ["wss://author-write.com"])
        
        // Create an event with no p-tags
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello world!")
            .build(signer: signer)
        
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should have no missing pubkeys since there are no p-tags
        XCTAssertTrue(selection.missingRelayInfoPubkeys.isEmpty)
        
        // Should still select some relays (author's relays + fallback)
        XCTAssertGreaterThan(selection.relays.count, 0)
    }
    
    func testETagRelayHints() async throws {
        let user1 = "user1_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcdef12"
        
        // Create an event with both e-tags (with relay hints) and p-tags
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Reply with mention")
            .tag(["e", "event_id_123", "wss://etag-relay.com"])
            .tag(["p", user1])
            .build()
        
        await setupMockRelayList(for: user1, readRelays: ["wss://user1-read.com"], writeRelays: ["wss://user1-write.com"])
        
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        
        // Should include both e-tag relay hint and p-tag user's read relay
        XCTAssertTrue(selection.relays.contains("wss://etag-relay.com"))
        XCTAssertTrue(selection.relays.contains("wss://user1-read.com"))
    }
    
    // MARK: - Helper Methods
    
    private func setupMockRelayList(for pubkey: String, readRelays: [String], writeRelays: [String]) async {
        // Create a mock NIP-65 relay list event for cache
        var tags: [[String]] = []
        
        // Add read relays
        for relay in readRelays {
            tags.append(["r", relay, "read"])
        }
        
        // Add write relays  
        for relay in writeRelays {
            tags.append(["r", relay, "write"])
        }
        
        // Create the relay list event
        let relayListEvent = NDKEvent(
            id: "relay_list_\(pubkey)",
            pubkey: pubkey,
            createdAt: Timestamp.now,
            kind: NDKRelayList.kind,
            tags: tags,
            content: "",
            sig: "mock_signature"
        )
        
        // Cache the event so the outbox tracker can find it when fetching
        do {
            try await cache.saveEvent(relayListEvent)
        } catch {
            // Handle cache errors gracefully in tests
            NDKLogger.log(.warning, category: .cache, "Failed to cache relay list event: \(error)")
        }
        
        // Manually populate the outbox tracker cache using the track method
        await ndk.outbox.track(
            pubkey: pubkey,
            readRelays: Set(readRelays),
            writeRelays: Set(writeRelays),
            source: .nip65
        )
    }
}