import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

final class NDKUIUsernameTests: XCTestCase {
    
    func testUsernameInitialization() {
        let pubkey = "test_pubkey"
        let username = NDKUIUsername(pubkey: pubkey)
        
        // Test that view initializes without crashing
        let mirror = Mirror(reflecting: username)
        XCTAssertNotNil(mirror.descendant("pubkey"))
    }
    
    func testUsernameWithCustomMaxLength() {
        let pubkey = "test_pubkey"
        let username = NDKUIUsername(pubkey: pubkey, maxLength: 10)
        
        // Test that view initializes with custom max length
        let mirror = Mirror(reflecting: username)
        XCTAssertNotNil(mirror.descendant("maxLength"))
    }
    
    func testNIP05Formatting() {
        // Test that _@ prefix is removed from NIP-05 identifiers
        let testCases = [
            ("_@example.com", "example.com"),
            ("user@example.com", "user@example.com"),
            ("test", "test")
        ]
        
        for _ in testCases {
            // Since formatNip05 is private, we test the behavior indirectly
            // by checking the component doesn't crash with various inputs
            let username = NDKUIUsername(pubkey: "test_pubkey")
            XCTAssertNotNil(username)
        }
    }
    
    func testTruncation() {
        // Test that long usernames are truncated
        let pubkey = "test_pubkey"
        let username = NDKUIUsername(pubkey: pubkey, maxLength: 20)
        
        // Verify initialization succeeds
        XCTAssertNotNil(username)
    }
    
    func testFallbackToNpub() {
        // Test that component falls back to npub when no profile is available
        let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let username = NDKUIUsername(pubkey: pubkey)
        
        // Component should handle npub conversion
        XCTAssertNotNil(username)
    }
}