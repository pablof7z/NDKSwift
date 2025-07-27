import XCTest
@testable import NDKSwift

final class NDKLogFormatterTests: XCTestCase {
    
    func testTruncateMessage_NonJSON() {
        let message = "This is a regular message"
        let result = NDKLogFormatter.truncateMessage(message)
        XCTAssertEqual(result, message)
    }
    
    func testTruncateMessage_SmallArray() {
        let message = """
        ["EVENT", {"id": "test"}]
        """
        let result = NDKLogFormatter.truncateMessage(message)
        XCTAssertEqual(result, message)
    }
    
    func testTruncateMessage_REQWithLargeFilter() {
        // Create a REQ message with a large filter
        var largeAuthors = [String]()
        for i in 0..<150 {
            largeAuthors.append(String(format: "%064x", i))
        }
        
        let filter: [String: Any] = [
            "authors": largeAuthors,
            "kinds": [1],
            "limit": 100
        ]
        
        let reqMessage: [Any] = ["REQ", "sub123", filter]
        let jsonData = try! JSONSerialization.data(withJSONObject: reqMessage)
        let message = String(data: jsonData, encoding: .utf8)!
        
        let result = NDKLogFormatter.truncateMessage(message)
        
        // Should contain REQ and subscription ID
        XCTAssertTrue(result.contains("\"REQ\""))
        XCTAssertTrue(result.contains("\"sub123\""))
        
        // Should truncate large authors array
        XCTAssertTrue(result.contains("<150-authors>"))
        XCTAssertFalse(result.contains(largeAuthors[0])) // Actual author values should be removed
        
        // Should keep other fields
        XCTAssertTrue(result.contains("\"kinds\":[1]"))
        XCTAssertTrue(result.contains("\"limit\":100"))
    }
    
    func testTruncateMessage_REQWithMultipleFilters() {
        let filter1: [String: Any] = [
            "kinds": [1],
            "limit": 10
        ]
        
        var largeIds = [String]()
        for i in 0..<200 {
            largeIds.append(String(format: "%064x", i))
        }
        let filter2: [String: Any] = [
            "ids": largeIds,
            "kinds": [30023]
        ]
        
        let reqMessage: [Any] = ["REQ", "multi-filter", filter1, filter2]
        let jsonData = try! JSONSerialization.data(withJSONObject: reqMessage)
        let message = String(data: jsonData, encoding: .utf8)!
        
        let result = NDKLogFormatter.truncateMessage(message)
        
        // Should handle multiple filters
        XCTAssertTrue(result.contains("\"REQ\""))
        XCTAssertTrue(result.contains("\"multi-filter\""))
        
        // First filter should be unchanged
        XCTAssertTrue(result.contains("\"kinds\":[1]"))
        XCTAssertTrue(result.contains("\"limit\":10"))
        
        // Second filter should have truncated ids
        XCTAssertTrue(result.contains("<200-ids>"))
    }
    
    func testTruncateMessage_NonREQMessage() {
        let message = """
        ["EVENT", "sub123", {"id": "test", "content": "hello"}]
        """
        let result = NDKLogFormatter.truncateMessage(message)
        XCTAssertEqual(result, message)
    }
    
    func testEmojiForCategory() {
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.network), "📡")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.relay), "🔗")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.subscription), "🔍")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.event), "📝")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.cache), "💾")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.auth), "🔐")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.wallet), "💰")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.general), "ℹ️")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.connection), "🔌")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.outbox), "🎯")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.signer), "✍️")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.sync), "🔄")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.performance), "⚡")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.security), "🛡️")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.database), "🗄️")
        XCTAssertEqual(NDKLogFormatter.emojiForCategory(.signature), "🔏")
    }
    
    func testTruncateMessage_InvalidJSON() {
        let message = "[\"REQ\", invalid json"
        let result = NDKLogFormatter.truncateMessage(message)
        XCTAssertEqual(result, message) // Should return as-is when JSON parsing fails
    }
    
    func testTruncateMessage_FilterWithExactly100Items() {
        // Test edge case with exactly 100 items (should not truncate)
        var exactAuthors = [String]()
        for i in 0..<100 {
            exactAuthors.append(String(format: "%064x", i))
        }
        
        let filter: [String: Any] = [
            "authors": exactAuthors,
            "kinds": [1]
        ]
        
        let reqMessage: [Any] = ["REQ", "exact100", filter]
        let jsonData = try! JSONSerialization.data(withJSONObject: reqMessage)
        let message = String(data: jsonData, encoding: .utf8)!
        
        let result = NDKLogFormatter.truncateMessage(message)
        
        // Should NOT truncate arrays with exactly 100 items
        XCTAssertFalse(result.contains("<100-authors>"))
        XCTAssertTrue(result.contains(exactAuthors[0]))
    }
}