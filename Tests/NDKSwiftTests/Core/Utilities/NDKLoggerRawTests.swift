import XCTest
@testable import NDKSwift

final class NDKLoggerRawTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        NDKLogger.logNetworkTraffic = true
    }
    
    func testRawLoggingWithSmallArrays() throws {
        // Create a simple filter
        let filter = NDKFilter(kinds: [1111])
        let message = NostrMessage.req(subscriptionId: "test123", filters: [filter])
        
        // Serialize the message
        let serialized = try message.serialize()
        
        // Expected format: ["REQ","test123",{"kinds":[1111]}]
        XCTAssertTrue(serialized.contains("\"REQ\""))
        XCTAssertTrue(serialized.contains("\"test123\""))
        XCTAssertTrue(serialized.contains("\"kinds\":[1111]"))
        
        // Test that truncation doesn't occur for small arrays
        let truncated = NDKLogger.truncateMessage(serialized)
        XCTAssertEqual(serialized, truncated)
    }
    
    func testRawLoggingWithLargeAuthorsArray() throws {
        // Create filter with many authors (>100 items)
        var largeAuthors: [String] = []
        for i in 0..<150 {
            largeAuthors.append("pubkey\(i)")
        }
        let filter = NDKFilter(authors: largeAuthors, kinds: [1, 30023])
        let message = NostrMessage.req(subscriptionId: "large_test", filters: [filter])
        
        // Serialize and truncate
        let serialized = try message.serialize()
        let truncated = NDKLogger.truncateMessage(serialized)
        
        // Verify truncation occurred
        XCTAssertTrue(truncated.contains("<150-authors>"))
        XCTAssertFalse(truncated.contains("pubkey149")) // Last author should be truncated
        XCTAssertTrue(truncated.contains("\"kinds\":[1,30023]")) // Kinds should remain
    }
    
    func testRawLoggingWithMultipleLargeArrays() throws {
        // Create filter with multiple large arrays
        var largeAuthors: [String] = []
        for i in 0..<200 {
            largeAuthors.append("author\(i)")
        }
        
        var largeTags: [String: Set<String>] = [:]
        var pTags: Set<String> = []
        for i in 0..<150 {
            pTags.insert("pubkey\(i)")
        }
        largeTags["p"] = pTags
        
        let filter = NDKFilter(authors: largeAuthors, kinds: [1], tags: largeTags)
        let message = NostrMessage.req(subscriptionId: "multi_large", filters: [filter])
        
        // Serialize and truncate
        let serialized = try message.serialize()
        let truncated = NDKLogger.truncateMessage(serialized)
        
        // Verify both arrays were truncated
        XCTAssertTrue(truncated.contains("<200-authors>"))
        XCTAssertTrue(truncated.contains("<150-#p>"))
    }
    
    func testNonREQMessagesPassThrough() throws {
        // Test that non-REQ messages are not truncated
        let messages: [NostrMessage] = [
            .close(subscriptionId: "test123"),
            .eose(subscriptionId: "test123"),
            .notice(message: "Test notice"),
            .ok(eventId: "event123", accepted: true, message: "Success")
        ]
        
        for message in messages {
            let serialized = try message.serialize()
            let truncated = NDKLogger.truncateMessage(serialized)
            XCTAssertEqual(serialized, truncated, "Non-REQ messages should not be truncated")
        }
    }
}