import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

final class NDKUIRelativeTimeTests: XCTestCase {
    
    func testRelativeTimeInitialization() {
        let timestamp = Date.currentNostrTimestamp
        let relativeTime = NDKUIRelativeTime(timestamp: timestamp)
        
        // Test that view initializes without crashing
        let mirror = Mirror(reflecting: relativeTime)
        XCTAssertNotNil(mirror.descendant("timestamp"))
    }
    
    func testRelativeTimeWithCustomInterval() {
        let timestamp = Date.currentNostrTimestamp
        let relativeTime = NDKUIRelativeTime(timestamp: timestamp, updateInterval: 30)
        
        // Test that view initializes with custom update interval
        let mirror = Mirror(reflecting: relativeTime)
        XCTAssertNotNil(mirror.descendant("updateInterval"))
    }
    
    func testStaticFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test various time differences
        let testCases: [(offset: Timestamp, expected: String)] = [
            (0, "now"),                      // Current time
            (-30, "now"),                    // 30 seconds ago
            (-90, "1m"),                     // 1.5 minutes ago
            (-300, "5m"),                    // 5 minutes ago
            (-3600, "1h"),                   // 1 hour ago
            (-7200, "2h"),                   // 2 hours ago
            (-86400, "Yesterday"),           // 1 day ago
            (-172800, "2d"),                 // 2 days ago
            (-604800, "1w"),                 // 1 week ago
            (-2592000, "1mo"),              // 30 days ago
            (-31536000, "1y"),              // 1 year ago
            (-63072000, "2y"),              // 2 years ago
            (3600, "in the future")          // Future date
        ]
        
        for (offset, expected) in testCases {
            let timestamp = now + offset
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, expected, "Offset \(offset) should format as '\(expected)'")
        }
    }
    
    func testMinutesFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test minute formatting
        for minutes in [1, 2, 5, 10, 30, 59] {
            let timestamp = now - Timestamp(minutes * 60)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, "\(minutes)m")
        }
    }
    
    func testHoursFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test hour formatting
        for hours in [1, 2, 6, 12, 23] {
            let timestamp = now - Timestamp(hours * 3600)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, "\(hours)h")
        }
    }
    
    func testDaysFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test day formatting
        let dayTests: [(days: Int, expected: String)] = [
            (1, "Yesterday"),
            (2, "2d"),
            (3, "3d"),
            (6, "6d")
        ]
        
        for (days, expected) in dayTests {
            let timestamp = now - Timestamp(days * 86400)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, expected)
        }
    }
    
    func testWeeksFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test week formatting
        for weeks in [1, 2, 3, 4] {
            let timestamp = now - Timestamp(weeks * 604800)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, "\(weeks)w")
        }
    }
    
    func testMonthsFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test month formatting (using 30-day months)
        for months in [1, 2, 6, 11] {
            let timestamp = now - Timestamp(months * 2592000)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, "\(months)mo")
        }
    }
    
    func testYearsFormatting() {
        let now = Date.currentNostrTimestamp
        
        // Test year formatting
        for years in [1, 2, 5, 10] {
            let timestamp = now - Timestamp(years * 31536000)
            let formatted = NDKUIRelativeTime.format(timestamp)
            XCTAssertEqual(formatted, "\(years)y")
        }
    }
}