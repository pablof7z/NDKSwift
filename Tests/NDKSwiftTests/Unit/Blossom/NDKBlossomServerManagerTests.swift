import XCTest
@testable import NDKSwift

final class NDKBlossomServerManagerTests: XCTestCase {
    
    // MARK: - NDKBlossomServerInfo Tests
    
    func testServerInfoInitialization() {
        let info = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom",
            description: "A test blossom server",
            isPaid: true,
            isWhitelisted: false,
            whitelistMessage: nil,
            paidMessage: "Requires payment"
        )
        
        XCTAssertEqual(info.id, "https://blossom.example.com")
        XCTAssertEqual(info.url, "https://blossom.example.com")
        XCTAssertEqual(info.name, "Example Blossom")
        XCTAssertEqual(info.description, "A test blossom server")
        XCTAssertTrue(info.isPaid)
        XCTAssertFalse(info.isWhitelisted)
        XCTAssertNil(info.whitelistMessage)
        XCTAssertEqual(info.paidMessage, "Requires payment")
    }
    
    func testServerInfoFromEvent() throws {
        // Create a mock event with proper Blossom server tags
        let event = try NDKEvent(content: "Test Blossom Server Description", kind: 36363, tags: [
            ["d", "https://blossom.test.com"],
            ["name", "Test Blossom"],
            ["paid", "Payment required for uploads"],
            ["whitelist", "Whitelisted users only"]
        ])
        
        let info = NDKBlossomServerInfo(from: event)
        
        XCTAssertEqual(info.url, "https://blossom.test.com")
        XCTAssertEqual(info.name, "Test Blossom")
        XCTAssertEqual(info.description, "Test Blossom Server Description")
        XCTAssertTrue(info.isPaid)
        XCTAssertTrue(info.isWhitelisted)
        XCTAssertEqual(info.paidMessage, "Payment required for uploads")
        XCTAssertEqual(info.whitelistMessage, "Whitelisted users only")
    }
    
    func testServerNameExtraction() throws {
        // Test various URL formats
        let testCases = [
            ("https://blossom.example.com", "blossom.example.com"),
            ("https://www.blossom.example.com", "blossom.example.com"),
            ("https://blossom.example.com/", "blossom.example.com"),
            ("https://blossom.example.com/path", "blossom.example.com"),
            ("blossom.example.com", "blossom.example.com"),
            ("www.blossom.example.com", "blossom.example.com")
        ]
        
        for (url, expectedName) in testCases {
            let event = try NDKEvent(content: "", kind: 36363, tags: [
                ["d", url]
                // No name tag, should extract from URL
            ])
            
            let info = NDKBlossomServerInfo(from: event)
            XCTAssertEqual(info.name, expectedName, "Failed for URL: \(url)")
        }
    }
    
    func testServerSubtitle() {
        // Test different combinations of paid and whitelisted
        let paidAndWhitelisted = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: true,
            isWhitelisted: true
        )
        XCTAssertEqual(paidAndWhitelisted.subtitle, "Paid & Whitelisted")
        
        let paidOnly = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: true,
            isWhitelisted: false
        )
        XCTAssertEqual(paidOnly.subtitle, "Paid")
        
        let whitelistedOnly = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: false,
            isWhitelisted: true
        )
        XCTAssertEqual(whitelistedOnly.subtitle, "Whitelisted")
        
        let free = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: false,
            isWhitelisted: false
        )
        XCTAssertNil(free.subtitle)
    }
    
    func testServerInfoEquatable() {
        let info1 = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom"
        )
        
        let info2 = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom"
        )
        
        let info3 = NDKBlossomServerInfo(
            url: "https://different.example.com",
            name: "Different Blossom"
        )
        
        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }
    
    func testServerInfoHashable() {
        let info1 = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom"
        )
        
        let info2 = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom"
        )
        
        var set = Set<NDKBlossomServerInfo>()
        set.insert(info1)
        set.insert(info2)
        
        // Should only have one item since they're equal
        XCTAssertEqual(set.count, 1)
    }
    
    func testServerInfoWithEmptyTags() throws {
        // Test event with minimal tags
        let event = try NDKEvent(content: "Minimal server", kind: 36363, tags: [
            ["d", "https://minimal.example.com"]
        ])
        
        let info = NDKBlossomServerInfo(from: event)
        
        XCTAssertEqual(info.url, "https://minimal.example.com")
        XCTAssertEqual(info.name, "minimal.example.com")
        XCTAssertEqual(info.description, "Minimal server")
        XCTAssertFalse(info.isPaid)
        XCTAssertFalse(info.isWhitelisted)
        XCTAssertNil(info.paidMessage)
        XCTAssertNil(info.whitelistMessage)
    }
    
    func testServerInfoWithMalformedTags() throws {
        // Test event with malformed tags
        let event = try NDKEvent(content: "Test", kind: 36363, tags: [
            ["d", "https://test.com"],
            ["name"], // Missing value
            ["paid"], // No message
            ["whitelist"], // No message
            ["unknown", "value"] // Unknown tag
        ])
        
        let info = NDKBlossomServerInfo(from: event)
        
        XCTAssertEqual(info.url, "https://test.com")
        XCTAssertEqual(info.name, "test.com") // Should fallback to extracted name
        XCTAssertTrue(info.isPaid)
        XCTAssertTrue(info.isWhitelisted)
        XCTAssertNil(info.paidMessage)
        XCTAssertNil(info.whitelistMessage)
    }
}