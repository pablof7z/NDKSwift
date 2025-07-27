import XCTest
@testable import NDKSwift

final class DateFormattersTests: XCTestCase {
    
    func testISO8601Formatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.iso8601.string(from: date)
        
        // Should contain standard ISO8601 components
        XCTAssertTrue(formatted.contains("2021-01-01"))
        XCTAssertTrue(formatted.contains("T"))
        XCTAssertTrue(formatted.contains("Z") || formatted.contains("+") || formatted.contains("-"))
    }
    
    func testISO8601BasicFormatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.iso8601Basic.string(from: date)
        
        // Should contain standard ISO8601 components without fractional seconds
        XCTAssertTrue(formatted.contains("2021-01-01"))
        XCTAssertTrue(formatted.contains("T"))
        XCTAssertFalse(formatted.contains(".")) // No fractional seconds
    }
    
    func testDisplayFormatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.display.string(from: date)
        
        // Should have both date and time components
        XCTAssertFalse(formatted.isEmpty)
        // Note: Exact format depends on locale, so we can't test specific format
    }
    
    func testDateOnlyFormatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.dateOnly.string(from: date)
        
        // Should have date but no time components
        XCTAssertFalse(formatted.isEmpty)
        // Should not contain time-like patterns (basic check)
        XCTAssertFalse(formatted.contains(":"))
    }
    
    func testTimeOnlyFormatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.timeOnly.string(from: date)
        
        // Should have time but no date components
        XCTAssertFalse(formatted.isEmpty)
        // Should contain time separator
        XCTAssertTrue(formatted.contains(":") || formatted.contains("."))
    }
    
    func testCustomFormatter() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatter = DateFormatters.custom(format: "yyyy-MM-dd HH:mm:ss")
        let formatted = formatter.string(from: date)
        
        // Should match our custom format
        XCTAssertTrue(formatted.contains("2021-01-01"))
    }
    
    func testCustomFormatterWithLocale() {
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let formatter = DateFormatters.custom(format: "EEEE, MMMM d", locale: Locale(identifier: "en_US"))
        let formatted = formatter.string(from: date)
        
        // Should contain English day/month names
        XCTAssertTrue(formatted.contains("Friday") || formatted.contains("January"))
    }
    
    func testRelativeFormatter() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        let formatted = DateFormatters.relative.localizedString(for: oneHourAgo, relativeTo: now)
        
        // Should contain some relative time indication
        XCTAssertFalse(formatted.isEmpty)
        // Should contain "hour" or "ago" in English locale
        XCTAssertTrue(formatted.lowercased().contains("hour") || formatted.lowercased().contains("ago"))
    }
    
    func testRelativeShortFormatter() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        let formatted = DateFormatters.relativeShort.localizedString(for: oneHourAgo, relativeTo: now)
        
        // Should be shorter than full relative format
        let fullFormatted = DateFormatters.relative.localizedString(for: oneHourAgo, relativeTo: now)
        XCTAssertTrue(formatted.count <= fullFormatted.count)
    }
    
    func testFormatTimestamp() {
        let timestamp: Int64 = 1609459200 // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.formatTimestamp(timestamp)
        
        // Should be valid ISO8601 format
        XCTAssertTrue(formatted.contains("2021-01-01"))
        XCTAssertTrue(formatted.contains("T"))
    }
    
    func testFormatTimestampForDisplay() {
        let timestamp: Int64 = 1609459200 // 2021-01-01 00:00:00 UTC
        let formatted = DateFormatters.formatTimestampForDisplay(timestamp)
        
        // Should have some content
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testFormatTimestampRelative() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let timestamp = Int64(oneHourAgo.timeIntervalSince1970)
        
        let formatted = DateFormatters.formatTimestampRelative(timestamp)
        
        // Should have relative time content
        XCTAssertFalse(formatted.isEmpty)
    }
    
    func testFormatterReuse() {
        // Test that formatters are reused (same instance)
        let formatter1 = DateFormatters.iso8601
        let formatter2 = DateFormatters.iso8601
        
        XCTAssertTrue(formatter1 === formatter2, "Formatters should be reused for performance")
    }
}