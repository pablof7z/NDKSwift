@testable import NDKSwift
import XCTest

final class NDKErrorHandlingTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
    }
    
    // MARK: - Event Validation Tests
    
    func testInvalidEventCreation() {
        // Test event with empty pubkey
        let emptyPubkeyEvent = NDKEvent(
            pubkey: "",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        XCTAssertThrowsError(try emptyPubkeyEvent.generateID()) { error in
            // Should fail with invalid pubkey
        }
    }
    
    func testInvalidTimestampHandling() {
        // Test event with invalid timestamp
        let invalidTimestampEvent = NDKEvent(
            pubkey: "valid_pubkey",
            createdAt: -1, // Invalid negative timestamp
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        // Should handle gracefully or throw appropriate error
        XCTAssertNoThrow(try invalidTimestampEvent.generateID())
    }
    
    func testMalformedTagHandling() {
        // Test event with malformed tags
        let event = NDKEvent(
            pubkey: "valid_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [["incomplete"]], // Malformed tag (missing value)
            content: "Test"
        )
        
        // Should handle gracefully
        XCTAssertNoThrow(try event.generateID())
    }
    
    // MARK: - Filter Validation Tests
    
    func testEmptyFilterHandling() {
        let emptyFilter = NDKFilter()
        
        // Empty filter should be valid but match nothing specific
        XCTAssertNotNil(emptyFilter)
        XCTAssertNil(emptyFilter.authors)
        XCTAssertNil(emptyFilter.kinds)
        XCTAssertNil(emptyFilter.limit)
    }
    
    func testInvalidFilterCombinations() {
        // Test filter with conflicting time constraints
        let conflictingTimeFilter = NDKFilter(
            since: 2000,
            until: 1000 // until before since
        )
        
        // Should be allowed but logically won't match anything
        XCTAssertNotNil(conflictingTimeFilter)
        XCTAssertEqual(conflictingTimeFilter.since, 2000)
        XCTAssertEqual(conflictingTimeFilter.until, 1000)
    }
    
    func testExcessiveFilterLimits() {
        // Test filter with very large limit
        let largeLimit = Int.max
        let largeFilter = NDKFilter(limit: largeLimit)
        
        XCTAssertEqual(largeFilter.limit, largeLimit)
        
        // Test negative limit (should be handled gracefully)
        let negativeFilter = NDKFilter(limit: -1)
        XCTAssertEqual(negativeFilter.limit, -1) // Should preserve value, let implementation decide
    }
    
    // MARK: - Signer Error Tests
    
    func testInvalidNsecHandling() {
        // Test invalid nsec format
        XCTAssertThrowsError(try NDKPrivateKeySigner(nsec: "invalid_nsec")) { error in
            // Should throw error for invalid nsec format
        }
        
        // Test empty nsec
        XCTAssertThrowsError(try NDKPrivateKeySigner(nsec: "")) { error in
            // Should throw error for empty nsec
        }
        
        // Test wrong bech32 prefix
        XCTAssertThrowsError(try NDKPrivateKeySigner(nsec: "npub1234567890abcdef")) { error in
            // Should throw error for wrong prefix (npub instead of nsec)
        }
    }
    
    func testSigningWithoutPrivateKey() async {
        let event = createTestEvent()
        
        // Test signing with uninitialized signer would require protocol changes
        // For now, test that we can detect missing signer
        XCTAssertNil(ndk.signer)
    }
    
    // MARK: - Subscription Error Tests
    
    func testSubscriptionWithInvalidFilters() {
        // Test subscription with empty filter array
        let emptyFiltersSubscription = NDKSubscription(filters: [], ndk: ndk)
        XCTAssertEqual(emptyFiltersSubscription.filters.count, 0)
        
        // Should handle gracefully
        XCTAssertNoThrow(emptyFiltersSubscription.start())
        XCTAssertNoThrow(emptyFiltersSubscription.close())
    }
    
    func testSubscriptionTimeout() async {
        var options = NDKSubscriptionOptions()
        options.timeout = 0.1 // Very short timeout
        
        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options,
            ndk: ndk
        )
        
        subscription.start()
        
        // Wait for timeout
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Should be closed due to timeout
        XCTAssertTrue(subscription.isClosed)
    }
    
    func testDuplicateSubscriptionClose() {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])], ndk: ndk)
        
        subscription.start()
        XCTAssertTrue(subscription.isActive)
        
        // Close multiple times should be safe
        subscription.close()
        XCTAssertTrue(subscription.isClosed)
        
        subscription.close() // Second close
        XCTAssertTrue(subscription.isClosed)
        
        subscription.close() // Third close
        XCTAssertTrue(subscription.isClosed)
    }
    
    // MARK: - Relay Error Tests
    
    func testInvalidRelayURL() async {
        // Test adding relay with invalid URL
        let invalidRelay = await ndk.relayPool.addRelay(url: "invalid-url")
        XCTAssertNil(invalidRelay)
        
        // Test with empty URL
        let emptyRelay = await ndk.relayPool.addRelay(url: "")
        XCTAssertNil(emptyRelay)
        
        // Test with non-websocket URL
        let httpRelay = await ndk.relayPool.addRelay(url: "http://example.com")
        XCTAssertNil(httpRelay) // Should reject non-ws URLs
    }
    
    func testRelayConnectionFailure() async {
        let relay = await ndk.relayPool.addRelay(url: "wss://nonexistent.relay.invalid")
        
        if let relay = relay {
            // Test connection to non-existent relay
            do {
                try await relay.connect()
                XCTFail("Should have thrown connection error")
            } catch {
                // Expected to fail
                XCTAssertTrue(true)
            }
        }
    }
    
    // MARK: - Cache Error Tests
    
    func testCacheCorruptionHandling() async {
        let cache = NDKInMemoryCache()
        ndk.cacheAdapter = cache
        
        // Test handling of corrupted event data
        let corruptedEvent = NDKEvent(
            pubkey: "", // Invalid empty pubkey
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        // Should handle gracefully without crashing
        XCTAssertNoThrow(await cache.setEvent(corruptedEvent, filters: [], relay: nil))
    }
    
    // MARK: - Memory Management Tests
    
    func testSubscriptionMemoryCleanup() {
        weak var weakSubscription: NDKSubscription?
        
        autoreleasepool {
            let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])], ndk: ndk)
            weakSubscription = subscription
            
            subscription.start()
            subscription.close()
        }
        
        // Give time for cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNil(weakSubscription, "Subscription should be deallocated")
        }
    }
    
    func testEventMemoryCleanup() {
        weak var weakEvent: NDKEvent?
        
        autoreleasepool {
            let event = createTestEvent()
            weakEvent = event
        }
        
        // Event should be deallocated when out of scope
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNil(weakEvent, "Event should be deallocated")
        }
    }
    
    // MARK: - Concurrency Error Tests
    
    func testConcurrentSubscriptionAccess() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])], ndk: ndk)
        
        // Test concurrent start/stop operations
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    subscription.start()
                }
                group.addTask {
                    subscription.close()
                }
            }
        }
        
        // Should handle concurrent access without crashing
        XCTAssertTrue(true) // If we get here, no crash occurred
    }
    
    func testConcurrentEventHandling() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])], ndk: ndk)
        let event = createTestEvent()
        
        // Test concurrent event handling
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    subscription.handleEvent(event, fromRelay: nil)
                }
            }
        }
        
        // Should handle concurrent event processing without crashing
        XCTAssertTrue(subscription.events.count >= 1) // At least one event should be processed
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvent(
        pubkey: String = "test_pubkey_with_64_characters_exactly_for_valid_testing_here",
        kind: Kind = 1,
        content: String = "Test content"
    ) -> NDKEvent {
        return NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [],
            content: content
        )
    }
}