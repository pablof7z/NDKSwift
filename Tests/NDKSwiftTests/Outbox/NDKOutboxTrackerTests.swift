import XCTest
@testable import NDKSwift

final class NDKOutboxTrackerTests: XCTestCase {
    var ndk: NDK!
    var tracker: NDKOutboxTracker!
    
    override func setUp() async throws {
        ndk = NDK()
        tracker = NDKOutboxTracker(
            ndk: ndk,
            capacity: 10,
            ttl: 60,
            blacklistedRelays: ["wss://blacklisted.relay"]
        )
    }
    
    func testManualTracking() async {
        // Track user relays manually
        await tracker.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://read1.relay", "wss://read2.relay"],
            writeRelays: ["wss://write1.relay", "wss://write2.relay"],
            source: .manual
        )
        
        // Verify tracked data
        let item = await tracker.getRelaysSyncFor(pubkey: "test_pubkey")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.readRelays.count, 2)
        XCTAssertEqual(item?.writeRelays.count, 2)
        XCTAssertEqual(item?.source, .manual)
    }
    
    func testBlacklistedRelays() async {
        // Track with blacklisted relay
        await tracker.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://read1.relay", "wss://blacklisted.relay"],
            writeRelays: ["wss://write1.relay", "wss://blacklisted.relay"]
        )
        
        let item = await tracker.getRelaysSyncFor(pubkey: "test_pubkey")
        XCTAssertNotNil(item)
        
        // Blacklisted relay should be filtered out
        let readURLs = item?.readRelays.map { $0.url } ?? []
        let writeURLs = item?.writeRelays.map { $0.url } ?? []
        
        XCTAssertFalse(readURLs.contains("wss://blacklisted.relay"))
        XCTAssertFalse(writeURLs.contains("wss://blacklisted.relay"))
        XCTAssertEqual(item?.readRelays.count, 1)
        XCTAssertEqual(item?.writeRelays.count, 1)
    }
    
    func testRelayTypeFiltering() async {
        await tracker.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://read1.relay", "wss://read2.relay"],
            writeRelays: ["wss://write1.relay", "wss://write2.relay"]
        )
        
        // Test read-only filter
        let readItem = await tracker.getRelaysSyncFor(pubkey: "test_pubkey", type: .read)
        XCTAssertEqual(readItem?.readRelays.count, 2)
        XCTAssertEqual(readItem?.writeRelays.count, 0)
        
        // Test write-only filter
        let writeItem = await tracker.getRelaysSyncFor(pubkey: "test_pubkey", type: .write)
        XCTAssertEqual(writeItem?.readRelays.count, 0)
        XCTAssertEqual(writeItem?.writeRelays.count, 2)
        
        // Test both
        let bothItem = await tracker.getRelaysSyncFor(pubkey: "test_pubkey", type: .both)
        XCTAssertEqual(bothItem?.readRelays.count, 2)
        XCTAssertEqual(bothItem?.writeRelays.count, 2)
    }
    
    func testUpdateRelayMetadata() async {
        // Track initial relays
        await tracker.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://relay1.com", "wss://relay2.com"],
            writeRelays: ["wss://relay1.com"]
        )
        
        // Update metadata for relay1
        let metadata = RelayMetadata(
            score: 0.95,
            lastConnectedAt: Date(),
            avgResponseTime: 150,
            failureCount: 2,
            authRequired: true,
            paymentRequired: false
        )
        
        await tracker.updateRelayMetadata(url: "wss://relay1.com", metadata: metadata)
        
        // Verify metadata was updated
        let item = await tracker.getRelaysSyncFor(pubkey: "test_pubkey")
        
        let readRelay = item?.readRelays.first { $0.url == "wss://relay1.com" }
        XCTAssertNotNil(readRelay?.metadata)
        XCTAssertEqual(readRelay?.metadata?.score, 0.95)
        XCTAssertEqual(readRelay?.metadata?.authRequired, true)
        
        let writeRelay = item?.writeRelays.first { $0.url == "wss://relay1.com" }
        XCTAssertNotNil(writeRelay?.metadata)
        XCTAssertEqual(writeRelay?.metadata?.score, 0.95)
    }
    
    func testCacheMiss() async {
        // Try to get relays for non-tracked user
        let item = await tracker.getRelaysSyncFor(pubkey: "unknown_pubkey")
        XCTAssertNil(item)
    }
    
    func testClear() async {
        // Track multiple users
        await tracker.track(pubkey: "user1", readRelays: ["wss://relay1.com"])
        await tracker.track(pubkey: "user2", readRelays: ["wss://relay2.com"])
        
        // Clear cache
        await tracker.clear()
        
        // Verify all cleared
        let item1 = await tracker.getRelaysSyncFor(pubkey: "user1")
        let item2 = await tracker.getRelaysSyncFor(pubkey: "user2")
        
        XCTAssertNil(item1)
        XCTAssertNil(item2)
    }
    
    func testAllRelayURLs() async {
        await tracker.track(
            pubkey: "test_pubkey",
            readRelays: ["wss://relay1.com", "wss://relay2.com"],
            writeRelays: ["wss://relay2.com", "wss://relay3.com"]
        )
        
        let item = await tracker.getRelaysSyncFor(pubkey: "test_pubkey")
        let allURLs = item?.allRelayURLs ?? []
        
        // Should contain unique URLs from both read and write
        XCTAssertEqual(allURLs.count, 3)
        XCTAssertTrue(allURLs.contains("wss://relay1.com"))
        XCTAssertTrue(allURLs.contains("wss://relay2.com"))
        XCTAssertTrue(allURLs.contains("wss://relay3.com"))
    }
    
    func testConcurrentAccess() async {
        // Test concurrent tracking
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await self.tracker.track(
                        pubkey: "user\(i)",
                        readRelays: ["wss://relay\(i).com"],
                        writeRelays: ["wss://write\(i).com"]
                    )
                }
            }
        }
        
        // Test concurrent reads
        await withTaskGroup(of: NDKOutboxItem?.self) { group in
            for i in 0..<10 {
                group.addTask {
                    return await self.tracker.getRelaysSyncFor(pubkey: "user\(i)")
                }
            }
            
            var foundCount = 0
            for await item in group {
                if item != nil {
                    foundCount += 1
                }
            }
            
            XCTAssertEqual(foundCount, 10)
        }
    }
}

// MARK: - Mock Implementations for Testing

class MockNDKForTrackerTests: NDK {
    var mockRelayListEvents: [NDKEvent] = []
    var mockContactListEvents: [NDKEvent] = []
    
    override func fetchEvents(filter: NDKFilter, relays: Set<NDKRelay>? = nil) async throws -> Set<NDKEvent> {
        if filter.kinds?.contains(NDKRelayList.kind) == true {
            return Set(mockRelayListEvents.filter { event in
                filter.authors?.contains(event.pubkey) ?? true
            })
        } else if filter.kinds?.contains(NDKContactList.kind) == true {
            return Set(mockContactListEvents.filter { event in
                filter.authors?.contains(event.pubkey) ?? true
            })
        }
        return []
    }
}

final class NDKOutboxTrackerFetchTests: XCTestCase {
    var mockNDK: MockNDKForTrackerTests!
    var tracker: NDKOutboxTracker!
    
    override func setUp() async throws {
        mockNDK = MockNDKForTrackerTests()
        tracker = NDKOutboxTracker(ndk: mockNDK)
    }
    
    func testFetchNIP65RelayList() async throws {
        // Create mock NIP-65 event
        let relayListEvent = createMockRelayListEvent(
            pubkey: "test_pubkey",
            readRelays: ["wss://read1.com", "wss://read2.com"],
            writeRelays: ["wss://write1.com"],
            bothRelays: ["wss://both1.com"]
        )
        
        mockNDK.mockRelayListEvents = [relayListEvent]
        
        // Fetch relays (should trigger network fetch)
        let item = try await tracker.getRelaysFor(pubkey: "test_pubkey")
        
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.source, .nip65)
        XCTAssertEqual(item?.readRelays.count, 3) // read1, read2, both1
        XCTAssertEqual(item?.writeRelays.count, 2) // write1, both1
    }
    
    func testFallbackToContactList() async throws {
        // No NIP-65 events
        mockNDK.mockRelayListEvents = []
        
        // Create mock contact list event
        let contactListEvent = createMockContactListEvent(
            pubkey: "test_pubkey",
            relays: ["wss://contact1.com", "wss://contact2.com"]
        )
        
        mockNDK.mockContactListEvents = [contactListEvent]
        
        // Fetch relays (should fallback to contact list)
        let item = try await tracker.getRelaysFor(pubkey: "test_pubkey")
        
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.source, .contactList)
        XCTAssertEqual(item?.readRelays.count, 2)
        XCTAssertEqual(item?.writeRelays.count, 2) // Same relays for read/write
    }
    
    func testPendingFetchDeduplication() async throws {
        // Create a slow-loading event
        let relayListEvent = createMockRelayListEvent(
            pubkey: "test_pubkey",
            readRelays: ["wss::///read1.com"]
        )
        
        mockNDK.mockRelayListEvents = [relayListEvent]
        
        // Start multiple concurrent fetches for same pubkey
        async let fetch1 = tracker.getRelaysFor(pubkey: "test_pubkey")
        async let fetch2 = tracker.getRelaysFor(pubkey: "test_pubkey")
        async let fetch3 = tracker.getRelaysFor(pubkey: "test_pubkey")
        
        let results = try await [fetch1, fetch2, fetch3]
        
        // All should return the same result
        XCTAssertNotNil(results[0])
        XCTAssertEqual(results[0]?.pubkey, results[1]?.pubkey)
        XCTAssertEqual(results[1]?.pubkey, results[2]?.pubkey)
    }
    
    // MARK: - Helper Methods
    
    private func createMockRelayListEvent(
        pubkey: String,
        readRelays: [String] = [],
        writeRelays: [String] = [],
        bothRelays: [String] = []
    ) -> NDKEvent {
        var tags: [[String]] = []
        
        for relay in readRelays {
            tags.append(["r", relay, "read"])
        }
        for relay in writeRelays {
            tags.append(["r", relay, "write"])
        }
        for relay in bothRelays {
            tags.append(["r", relay])
        }
        
        return NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: NDKRelayList.kind,
            tags: tags,
            content: ""
        )
    }
    
    private func createMockContactListEvent(
        pubkey: String,
        relays: [String]
    ) -> NDKEvent {
        var content: [String: Any] = [:]
        for relay in relays {
            content[relay] = ["read": true, "write": true]
        }
        
        let contentData = try! JSONSerialization.data(withJSONObject: content)
        let contentString = String(data: contentData, encoding: .utf8)!
        
        return NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: NDKContactList.kind,
            tags: [],
            content: contentString
        )
    }
}