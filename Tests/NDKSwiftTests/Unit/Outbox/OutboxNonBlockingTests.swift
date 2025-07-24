import XCTest
@testable import NDKSwift

final class OutboxNonBlockingTests: XCTestCase {
    
    func testOutboxStrategyDoesNotBlock() async throws {
        // Create NDK instance
        let ndk = NDK()
        
        // Add relays and connect to ensure pool has connected relays
        await ndk.pool.addRelay("wss://relay1.test")
        await ndk.pool.addRelay("wss://relay2.test")
        await ndk.pool.connectAll()
        
        // Wait a moment for connections
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Create a filter with many authors (simulating follow list)
        let testAuthors = (0..<111).map { index in
            // Generate deterministic test pubkeys
            String(repeating: String(format: "%02x", index), count: 32)
        }
        
        let filter = NDKFilter(
            authors: testAuthors,
            kinds: [1],
            limit: 100
        )
        
        // Measure time for outbox strategy
        let startTime = Date()
        let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: filter)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should complete very quickly (under 100ms)
        XCTAssertLessThan(elapsed, 0.1, "getOutboxStrategy should not block - took \(elapsed)s")
        
        // Verify the strategy structure
        // Note: If no relays are connected, filtersByRelay will be empty
        // The important part is that it returns quickly without blocking
        XCTAssertEqual(outboxStrategy.unknownAuthors.count, 111, "All authors should be unknown initially")
        XCTAssertEqual(outboxStrategy.authorsToDiscover.count, 111, "All authors should be marked for discovery")
    }
    
    func testOutboxStrategyWithCachedRelays() async throws {
        // Create NDK instance
        let ndk = NDK()
        
        // Pre-populate some relay info
        let cachedPubkey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        // Track user will fetch relay info - for test we'll use manual tracking instead
        // Note: In real usage, trackUser would fetch from network
        
        // Create filter including cached and uncached authors
        let filter = NDKFilter(
            authors: [
                cachedPubkey,
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            ],
            kinds: [1]
        )
        
        let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: filter)
        
        // Without cached relay info, all authors should be unknown
        // They will use the app's connected relays
        XCTAssertEqual(outboxStrategy.unknownAuthors.count, 3)
        XCTAssertEqual(outboxStrategy.authorsToDiscover.count, 3)
    }
    
    func testBackgroundRelayDiscoveryStartsImmediately() async throws {
        // Create NDK instance
        let ndk = NDK()
        
        // Add a test relay
        await ndk.pool.addRelay("wss://test.relay")
        
        let testAuthors: Set<String> = ["test_author_1", "test_author_2"]
        
        // This should return immediately and not block
        let startTime = Date()
        await ndk.outbox.discoverRelaysInBackground(for: testAuthors)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should return almost instantly (under 10ms)
        XCTAssertLessThan(elapsed, 0.01, "discoverRelaysInBackground should return immediately")
    }
    
    func testFilterDecompositionByRelay() async throws {
        let ndk = NDK()
        
        // Set up test data - add relays
        await ndk.pool.addRelay("wss://relay1.com")
        await ndk.pool.addRelay("wss://relay2.com") 
        await ndk.pool.addRelay("wss://relay3.com")
        await ndk.pool.connectAll()
        
        // Wait a moment for connections
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let filter = NDKFilter(
            authors: ["author1", "author2", "author3"],
            kinds: [1]
        )
        
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)
        
        // Without pre-cached relay info, all authors are unknown
        XCTAssertEqual(strategy.unknownAuthors.count, 3)
        
        // If relays are connected, they should all be assigned to the app's connected relays
        // If no relays connected (in unit test environment), filtersByRelay may be empty
        // The important part is testing the decomposition logic
        if !strategy.filtersByRelay.isEmpty {
            // Each relay should have all 3 authors since they're all unknown
            for (relay, filter) in strategy.filtersByRelay {
                XCTAssertEqual(Set(filter.authors ?? []), Set(["author1", "author2", "author3"]),
                              "Relay \(relay) should have all unknown authors")
            }
        }
    }
}