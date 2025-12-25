@testable import NDKSwiftCore
import XCTest

final class NDKBlossomServerManagerTests: XCTestCase {
    // MARK: - NDKBlossomServerInfo Tests

    func testServerInfoInitialization() {
        let info = NDKBlossomServerInfo(
            url: "https://blossom.example.com",
            name: "Example Blossom",
            description: "A test blossom server",
            isPaid: true,
            isAllowlisted: false,
            allowlistMessage: nil,
            paidMessage: "Requires payment"
        )

        XCTAssertEqual(info.id, "https://blossom.example.com")
        XCTAssertEqual(info.url, "https://blossom.example.com")
        XCTAssertEqual(info.name, "Example Blossom")
        XCTAssertEqual(info.description, "A test blossom server")
        XCTAssertTrue(info.isPaid)
        XCTAssertFalse(info.isAllowlisted)
        XCTAssertNil(info.allowlistMessage)
        XCTAssertEqual(info.paidMessage, "Requires payment")
    }

    func testServerInfoFromEvent() {
        // Create a mock event with proper Blossom server tags
        let event = NDKEvent(
            kind: 36363,
            content: "Test Blossom Server Description",
            tags: [
                ["d", "https://blossom.test.com"],
                ["name", "Test Blossom"],
                ["paid", "Payment required for uploads"],
                ["whitelist", "Whitelisted users only"],
            ],
            pubkey: "test-pubkey"
        )

        let info = NDKBlossomServerInfo(from: event)

        XCTAssertEqual(info.url, "https://blossom.test.com")
        XCTAssertEqual(info.name, "Test Blossom")
        XCTAssertEqual(info.description, "Test Blossom Server Description")
        XCTAssertTrue(info.isPaid)
        XCTAssertTrue(info.isAllowlisted)
        XCTAssertEqual(info.paidMessage, "Payment required for uploads")
        XCTAssertEqual(info.allowlistMessage, "Whitelisted users only")
    }

    func testServerNameExtraction() {
        // Test various URL formats
        let testCases = [
            ("https://blossom.example.com", "blossom.example.com"),
            ("https://www.blossom.example.com", "blossom.example.com"),
            ("https://blossom.example.com/", "blossom.example.com"),
            ("https://blossom.example.com/path", "blossom.example.com"),
            ("blossom.example.com", "blossom.example.com"),
            ("www.blossom.example.com", "blossom.example.com"),
        ]

        for (url, expectedName) in testCases {
            let event = NDKEvent(
                kind: 36363,
                content: "",
                tags: [
                    ["d", url],
                    // No name tag, should extract from URL
                ],
                pubkey: "test-pubkey"
            )

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
            isAllowlisted: true
        )
        XCTAssertEqual(paidAndWhitelisted.subtitle, "Paid & Whitelisted")

        let paidOnly = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: true,
            isAllowlisted: false
        )
        XCTAssertEqual(paidOnly.subtitle, "Paid")

        let whitelistedOnly = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: false,
            isAllowlisted: true
        )
        XCTAssertEqual(whitelistedOnly.subtitle, "Whitelisted")

        let free = NDKBlossomServerInfo(
            url: "https://example.com",
            name: "Test",
            isPaid: false,
            isAllowlisted: false
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

    func testServerInfoWithEmptyTags() {
        // Test event with minimal tags
        let event = NDKEvent(
            kind: 36363,
            content: "Minimal server",
            tags: [
                ["d", "https://minimal.example.com"],
            ],
            pubkey: "test-pubkey"
        )

        let info = NDKBlossomServerInfo(from: event)

        XCTAssertEqual(info.url, "https://minimal.example.com")
        XCTAssertEqual(info.name, "minimal.example.com")
        XCTAssertEqual(info.description, "Minimal server")
        XCTAssertFalse(info.isPaid)
        XCTAssertFalse(info.isAllowlisted)
        XCTAssertNil(info.paidMessage)
        XCTAssertNil(info.allowlistMessage)
    }

    func testServerInfoWithMalformedTags() {
        // Test event with malformed tags
        let event = NDKEvent(
            kind: 36363,
            content: "Test",
            tags: [
                ["d", "https://test.com"],
                ["name"], // Missing value
                ["paid"], // No message
                ["whitelist"], // No message
                ["unknown", "value"], // Unknown tag
            ],
            pubkey: "test-pubkey"
        )

        let info = NDKBlossomServerInfo(from: event)

        XCTAssertEqual(info.url, "https://test.com")
        XCTAssertEqual(info.name, "test.com") // Should fallback to extracted name
        XCTAssertTrue(info.isPaid)
        XCTAssertTrue(info.isAllowlisted)
        XCTAssertNil(info.paidMessage)
        XCTAssertNil(info.allowlistMessage)
    }
}
