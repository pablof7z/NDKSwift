@testable import NDKSwift
import XCTest

final class NDKFetchingStrategyTests: XCTestCase {
    var ndk: NDK!
    var tracker: NDKOutboxTracker!
    var ranker: NDKRelayRanker!
    var selector: NDKRelaySelector!
    var strategy: NDKFetchingStrategy!

    override func setUp() async throws {
        ndk = NDK()
        tracker = NDKOutboxTracker(ndk: ndk)
        ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
        selector = NDKRelaySelector(ndk: ndk, tracker: tracker, ranker: ranker)
        strategy = NDKFetchingStrategy(ndk: ndk, selector: selector, ranker: ranker)
    }

    func testStrategyInitialization() {
        XCTAssertNotNil(strategy)
        XCTAssertNotNil(ndk)
        XCTAssertNotNil(tracker)
        XCTAssertNotNil(ranker)
        XCTAssertNotNil(selector)
    }

    func testRelaySelection() async throws {
        // Add some relays to test with
        _ = await ndk.relayPool.addRelay(url: "wss://relay1.com")
        _ = await ndk.relayPool.addRelay(url: "wss://relay2.com")
        
        // Track some authors
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        // Test that we can get relay information
        XCTAssertEqual(ndk.relays.count, 2)
        
        let relayUrls = await tracker.getReadRelays(for: "author1")
        XCTAssertEqual(relayUrls.count, 2)
        XCTAssertTrue(relayUrls.contains("wss://relay1.com"))
        XCTAssertTrue(relayUrls.contains("wss://relay2.com"))
    }

    func testFilterPreparation() {
        let filter = NDKFilter(
            authors: ["author1", "author2"],
            kinds: [1, 6]
        )
        
        // Test basic filter properties
        XCTAssertEqual(filter.authors?.count, 2)
        XCTAssertEqual(filter.kinds?.count, 2)
        XCTAssertTrue(filter.authors?.contains("author1") ?? false)
        XCTAssertTrue(filter.kinds?.contains(1) ?? false)
    }

    func testMultipleAuthorTracking() async throws {
        // Test tracking multiple authors
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com"]
        )
        
        await tracker.track(
            pubkey: "author2", 
            readRelays: ["wss://relay2.com"]
        )
        
        let author1Relays = await tracker.getReadRelays(for: "author1")
        let author2Relays = await tracker.getReadRelays(for: "author2")
        
        XCTAssertEqual(author1Relays.count, 1)
        XCTAssertEqual(author2Relays.count, 1)
        XCTAssertTrue(author1Relays.contains("wss://relay1.com"))
        XCTAssertTrue(author2Relays.contains("wss://relay2.com"))
    }

    // MARK: - Helper Methods
    
    private func createTestEvent(
        id: String = "test_id",
        pubkey: String = "test_pubkey",
        content: String = "Test content"
    ) -> NDKEvent {
        return NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: content
        )
    }
}