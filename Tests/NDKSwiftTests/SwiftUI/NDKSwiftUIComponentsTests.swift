import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

/// Basic tests for NDKSwiftUI components to ensure they can be instantiated
final class NDKSwiftUIComponentsTests: XCTestCase {
    
    func testNDKFollowButtonInitialization() {
        // Test that NDKFollowButton can be created with a pubkey
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let button = NDKFollowButton(pubkey: pubkey)
        
        // If it compiles and creates, the test passes
        XCTAssertNotNil(button)
    }
    
    func testNDKZapButtonInitialization() throws {
        // Test that NDKZapButton can be created with an event
        let event = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: "Test event"
        )
        
        let button = NDKZapButton(event: event)
        XCTAssertNotNil(button)
        
        // Test with custom configuration
        let customButton = NDKZapButton(
            event: event,
            amounts: [10, 50, 100],
            defaultAmount: 10
        )
        XCTAssertNotNil(customButton)
    }
    
    func testNDKReactionButtonInitialization() throws {
        // Test that NDKReactionButton can be created
        let event = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: "Test event"
        )
        
        let button = NDKReactionButton(event: event)
        XCTAssertNotNil(button)
        
        // Test with custom reaction
        let customButton = NDKReactionButton(event: event, reaction: "❤️")
        XCTAssertNotNil(customButton)
    }
    
    func testNDKProfilePictureInitialization() {
        // Test that NDKProfilePicture can be created
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let profilePicture = NDKProfilePicture(pubkey: pubkey)
        
        XCTAssertNotNil(profilePicture)
    }
    
    func testNDKDisplayNameInitialization() {
        // Test that NDKDisplayName can be created
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let displayName = NDKDisplayName(pubkey: pubkey)
        
        XCTAssertNotNil(displayName)
    }
    
    func testNDKMarkdownRendererInitialization() {
        // Test that NDKMarkdownRenderer can be created
        let markdown = "# Hello World\n\nThis is **bold** text."
        let ndk = NDK()
        let renderer = NDKMarkdownRenderer(markdown, ndk: ndk)
        
        XCTAssertNotNil(renderer)
    }
    
    func testNDKEventViewInitialization() throws {
        // Test that NDKEventView can be created
        let event = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: "Test event content"
        )
        
        let eventView = NDKEventView(event: event)
        XCTAssertNotNil(eventView)
    }
    
    func testNDKEventAuthorHeaderInitialization() throws {
        // Test that NDKEventAuthorHeader can be created
        let event = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: "Test event"
        )
        
        let header = NDKEventAuthorHeader(event: event)
        XCTAssertNotNil(header)
    }
    
    func testNDKColorsConstants() {
        // Test that color constants are available
        XCTAssertNotNil(NDKColors.primary)
        XCTAssertNotNil(NDKColors.secondary)
        XCTAssertNotNil(NDKColors.accent)
        XCTAssertNotNil(NDKColors.background)
        XCTAssertNotNil(NDKColors.surface)
        XCTAssertNotNil(NDKColors.error)
        XCTAssertNotNil(NDKColors.success)
        XCTAssertNotNil(NDKColors.warning)
    }
    
    func testUIConstants() {
        // Test that UI constants are defined
        XCTAssertGreaterThan(UIConstants.Spacing.small, 0)
        XCTAssertGreaterThan(UIConstants.Spacing.medium, UIConstants.Spacing.small)
        XCTAssertGreaterThan(UIConstants.Spacing.large, UIConstants.Spacing.medium)
        
        XCTAssertGreaterThan(UIConstants.Radius.small, 0)
        XCTAssertGreaterThan(UIConstants.Radius.medium, UIConstants.Radius.small)
        XCTAssertGreaterThan(UIConstants.Radius.large, UIConstants.Radius.medium)
    }
    
    func testNDKRelativeTimeFormatting() {
        // Test relative time formatting
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)
        
        let relativeHour = NDKRelativeTime.format(oneHourAgo)
        let relativeDay = NDKRelativeTime.format(oneDayAgo)
        
        XCTAssertFalse(relativeHour.isEmpty)
        XCTAssertFalse(relativeDay.isEmpty)
    }
}