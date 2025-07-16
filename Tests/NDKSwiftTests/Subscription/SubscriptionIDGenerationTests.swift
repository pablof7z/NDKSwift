import XCTest
@testable import NDKSwift

final class SubscriptionIDGenerationTests: XCTestCase {
    
    func testSubscriptionIDFormat() {
        // Test with kinds filter
        let filter1 = NDKFilter(kinds: [1, 3, 7])
        let sub1 = NDKSubscription(filters: [filter1])
        
        // Should have format: "kinds:1,3,7-xxxxx" where xxxxx is random
        XCTAssertTrue(sub1.id.contains("kinds:1,3,7-"))
        XCTAssertTrue(sub1.id.contains("-"))
        let parts = sub1.id.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last?.count, 5) // Random suffix should be 5 chars
    }
    
    func testSubscriptionIDWithMultipleFilterTypes() {
        // Test with multiple filter criteria
        let filter = NDKFilter(
            authors: ["pubkey1", "pubkey2"],
            kinds: [1],
            since: 1234567890
        )
        let sub = NDKSubscription(filters: [filter])
        
        // Should contain kinds and filter type indicators
        XCTAssertTrue(sub.id.contains("kinds:1"))
        XCTAssertTrue(sub.id.contains("auth"))
        XCTAssertTrue(sub.id.contains("time"))
    }
    
    func testSubscriptionIDWithUserProvidedID() {
        // Test that user-provided ID is used
        let filter = NDKFilter(kinds: [1])
        let customId = "my-custom-subscription"
        let sub = NDKSubscription(id: customId, filters: [filter])
        
        XCTAssertEqual(sub.id, customId)
    }
    
    func testSubscriptionIDUniqueness() {
        // Test that multiple subscriptions with same filter get different IDs
        let filter = NDKFilter(kinds: [1])
        let sub1 = NDKSubscription(filters: [filter])
        let sub2 = NDKSubscription(filters: [filter])
        
        XCTAssertNotEqual(sub1.id, sub2.id)
        
        // But they should have the same prefix
        let prefix1 = sub1.id.split(separator: "-").dropLast().joined(separator: "-")
        let prefix2 = sub2.id.split(separator: "-").dropLast().joined(separator: "-")
        XCTAssertEqual(prefix1, prefix2)
    }
    
    func testFilterFingerprint() {
        // Test fingerprint generation
        let filter1 = NDKFilter(kinds: [1, 3, 7])
        XCTAssertEqual(filter1.fingerprint, "kinds:1,3,7")
        
        // Test with authors (should truncate)
        let longPubkey = "abcdefghijklmnopqrstuvwxyz0123456789"
        let filter2 = NDKFilter(authors: [longPubkey])
        XCTAssertTrue(filter2.fingerprint.contains("authors:abcdefgh"))
        
        // Test empty filter
        let filter3 = NDKFilter()
        XCTAssertEqual(filter3.fingerprint, "empty-filter")
        
        // Test long fingerprint gets hashed
        let filter4 = NDKFilter(
            ids: ["id1", "id2", "id3"],
            authors: ["author1", "author2"],
            kinds: [1, 2, 3, 4, 5],
            events: ["event1", "event2"],
            pubkeys: ["pubkey1", "pubkey2"]
        )
        // Should be hashed to 15 chars
        XCTAssertEqual(filter4.fingerprint.count, 15)
    }
    
    func testSubscriptionIDNoFilters() {
        // Test with empty filters array
        let sub = NDKSubscription(filters: [])
        
        // Should have format: "sub-xxxxx"
        XCTAssertTrue(sub.id.hasPrefix("sub-"))
        let parts = sub.id.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last?.count, 5)
    }
}