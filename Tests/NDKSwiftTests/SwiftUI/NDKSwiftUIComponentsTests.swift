import XCTest
import SwiftUI
@testable import NDKSwift
@testable import NDKSwiftUI

/// Comprehensive tests for NDKSwiftUI components
final class NDKSwiftUIComponentsTests: XCTestCase {
    
    // MARK: - NDKUIFollowButton Tests
    
    func testNDKUIFollowButtonInitialization() {
        // Test basic initialization
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let button = NDKUIFollowButton(pubkey: pubkey)
        XCTAssertNotNil(button)
        
        // Test with different styles
        let standardButton = NDKUIFollowButton(pubkey: pubkey, style: .standard)
        XCTAssertNotNil(standardButton)
        
        let compactButton = NDKUIFollowButton(pubkey: pubkey, style: .compact)
        XCTAssertNotNil(compactButton)
        
        let minimalButton = NDKUIFollowButton(pubkey: pubkey, style: .minimal)
        XCTAssertNotNil(minimalButton)
        
        // Test convenience initializers
        let compactConvenience = NDKUIFollowButton.compact(pubkey: pubkey)
        XCTAssertNotNil(compactConvenience)
        
        let minimalConvenience = NDKUIFollowButton.minimal(pubkey: pubkey)
        XCTAssertNotNil(minimalConvenience)
        
        // Test with options
        let buttonWithOptions = NDKUIFollowButton(
            pubkey: pubkey,
            style: .standard,
            showFollowText: false,
            confirmUnfollow: false
        )
        XCTAssertNotNil(buttonWithOptions)
    }
    
    func testNDKUIFollowButtonCallbacks() {
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let button = NDKUIFollowButton(pubkey: pubkey)
            .onFollowChanged { isFollowing in
                // Test callback configuration
            }
        XCTAssertNotNil(button)
    }
    
    // MARK: - NDKUIZapButton Tests
    
    func testNDKUIZapButtonInitialization() throws {
        // Test that NDKUIZapButton can be created with an event
        let event = NDKEvent(
            id: "test_event_id_123456789012345678901234567890123456789012345678",
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "test_signature_123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678"
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
        
        // Test with different button styles
        let compactButton = NDKZapButton(
            event: event,
            style: .compact
        )
        XCTAssertNotNil(compactButton)
        
        // Test with different default amount
        let buttonWithAmount = NDKZapButton(
            event: event,
            defaultAmount: 100
        )
        XCTAssertNotNil(buttonWithAmount)
    }
    
    func testNDKUIZapButtonCallbacks() throws {
        let event = NDKEvent(
            id: "test_event_id_123456789012345678901234567890123456789012345678",
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "test_signature_123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678"
        )
        
        let button = NDKZapButton(event: event)
            .onZapSent { amount, comment in
                // Test callback configuration
            }
        XCTAssertNotNil(button)
    }
    
    // MARK: - NDKUIReactionButton Tests
    
    func testNDKUIReactionButtonInitialization() throws {
        // Test that NDKUIReactionButton can be created
        let event = NDKEvent(
            id: "test_event_id_123456789012345678901234567890123456789012345678",
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "test_signature_123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678"
        )
        
        let button = NDKUIReactionButton(event: event)
        XCTAssertNotNil(button)
        
        // Test with custom reaction
        let customButton = NDKUIReactionButton(event: event, reaction: "❤️")
        XCTAssertNotNil(customButton)
        
        // Test with different styles
        let compactButton = NDKUIReactionButton(event: event, style: .compact)
        XCTAssertNotNil(compactButton)
        
        let minimalButton = NDKUIReactionButton(event: event, style: .minimal)
        XCTAssertNotNil(minimalButton)
        
        // Test with initial reacted state
        let reactedButton = NDKUIReactionButton(
            event: event,
            reaction: "🔥",
            hasReacted: true
        )
        XCTAssertNotNil(reactedButton)
    }
    
    func testNDKUIReactionButtonCallbacks() throws {
        let event = NDKEvent(
            id: "test_event_id_123456789012345678901234567890123456789012345678",
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "test_signature_123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678"
        )
        
        let button = NDKUIReactionButton(event: event)
            .onReactionChanged { hasReacted in
                // Test callback configuration
            }
        XCTAssertNotNil(button)
    }
    
    // MARK: - NDKUIProfilePicture Tests
    
    func testNDKUIProfilePictureInitialization() {
        // Test basic initialization
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let profilePicture = NDKUIProfilePicture(pubkey: pubkey)
        XCTAssertNotNil(profilePicture)
        
        // Test with different sizes
        let smallPicture = NDKUIProfilePicture(pubkey: pubkey, size: 24)
        XCTAssertNotNil(smallPicture)
        
        let largePicture = NDKUIProfilePicture(pubkey: pubkey, size: 100)
        XCTAssertNotNil(largePicture)
        
        // Test with placeholder image
        let withPlaceholder = NDKUIProfilePicture(
            pubkey: pubkey,
            size: 50,
            placeholderImage: "person.circle.fill"
        )
        XCTAssertNotNil(withPlaceholder)
    }
    
    // MARK: - NDKUIDisplayName Tests
    
    func testNDKUIDisplayNameInitialization() {
        // Test basic initialization
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let displayName = NDKUIDisplayName(pubkey: pubkey)
        XCTAssertNotNil(displayName)
        
        // Test with different styles
        let boldName = NDKUIDisplayName(pubkey: pubkey, font: .headline)
        XCTAssertNotNil(boldName)
        
        let smallName = NDKUIDisplayName(pubkey: pubkey, font: .caption)
        XCTAssertNotNil(smallName)
        
        // Test with show username option
        let withUsername = NDKUIDisplayName(pubkey: pubkey, showUsername: true)
        XCTAssertNotNil(withUsername)
        
        // Test with max width
        let truncatedName = NDKUIDisplayName(pubkey: pubkey, maxWidth: 150)
        XCTAssertNotNil(truncatedName)
    }
    
    // MARK: - NDKUIMarkdownRenderer Tests
    
    func testNDKUIMarkdownRendererInitialization() {
        // Test basic markdown rendering
        let markdown = "# Hello World\n\nThis is **bold** text."
        let ndk = NDK()
        let renderer = NDKUIMarkdownRenderer(markdown, ndk: ndk)
        XCTAssertNotNil(renderer)
        
        // Test with nostr entities
        let markdownWithNostr = "Check out nostr:npub1234 and #bitcoin"
        let nostrRenderer = NDKUIMarkdownRenderer(markdownWithNostr, ndk: ndk)
        XCTAssertNotNil(nostrRenderer)
        
        // Test with custom configuration
        var config = MarkdownConfiguration()
        config.showImages = false
        config.fontSize = 14
        let customRenderer = NDKUIMarkdownRenderer(
            markdown,
            ndk: ndk,
            configuration: config
        )
        XCTAssertNotNil(customRenderer)
        
        // Test with event context
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: markdown
        )
        let eventRenderer = NDKUIMarkdownRenderer(
            markdown,
            ndk: ndk,
            event: event
        )
        XCTAssertNotNil(eventRenderer)
    }
    
    // MARK: - NDKUIEventView Tests
    
    func testNDKUIEventViewInitialization() throws {
        // Test text note event
        let textEvent = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 1,
            tags: [],
            content: "Test event content"
        )
        let textView = NDKUIEventView(event: textEvent)
        XCTAssertNotNil(textView)
        
        // Test long form article
        let articleEvent = NDKEvent(
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Date.now,
            kind: 30023,
            tags: [["title", "Test Article"]],
            content: "# Article Content\n\nThis is a test article."
        )
        let articleView = NDKUIEventView(event: articleEvent)
        XCTAssertNotNil(articleView)
        
        // Test with options
        let customView = NDKUIEventView(
            event: textEvent,
            showAuthor: false,
            showInteractions: false
        )
        XCTAssertNotNil(customView)
    }
    
    func testNDKEventAuthorHeaderInitialization() throws {
        // Test that NDKEventAuthorHeader can be created
        let event = NDKEvent(
            id: "test_event_id_123456789012345678901234567890123456789012345678",
            pubkey: "test_pubkey_123456789012345678901234567890123456789012345678901234",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "test_signature_123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678"
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
    
    // MARK: - Helper Components Tests
    
    func testNDKUIRelativeTime() {
        // Test component initialization
        let date = Date().addingTimeInterval(-3600)
        let relativeTime = NDKUIRelativeTime(date: date)
        XCTAssertNotNil(relativeTime)
        
        // Test with custom style
        let compactTime = NDKUIRelativeTime(date: date, style: .compact)
        XCTAssertNotNil(compactTime)
    }
    
    func testNDKUIUsername() {
        let pubkey = "test_pubkey_123456789012345678901234567890123456789012345678901234"
        let username = NDKUIUsername(pubkey: pubkey)
        XCTAssertNotNil(username)
        
        // Test with prefix
        let withPrefix = NDKUIUsername(pubkey: pubkey, showPrefix: true)
        XCTAssertNotNil(withPrefix)
    }
    
    func testNDKRichText() {
        let content = "This is a test with #bitcoin and @npub1234"
        let ndk = NDK()
        let richText = NDKRichText(content: content, ndk: ndk)
        XCTAssertNotNil(richText)
        
        // Test with event context
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Date.now,
            kind: 1,
            tags: [["t", "bitcoin"]],
            content: content
        )
        let eventRichText = NDKRichText(content: content, ndk: ndk, event: event)
        XCTAssertNotNil(eventRichText)
    }
    
    func testNDKUIRelativeTimeFormatting() {
        // Test relative time formatting
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)
        let oneWeekAgo = now.addingTimeInterval(-604800)
        
        let relativeMinute = NDKUIRelativeTime.format(Timestamp(oneMinuteAgo.timeIntervalSince1970))
        let relativeHour = NDKUIRelativeTime.format(Timestamp(oneHourAgo.timeIntervalSince1970))
        let relativeDay = NDKUIRelativeTime.format(Timestamp(oneDayAgo.timeIntervalSince1970))
        let relativeWeek = NDKUIRelativeTime.format(Timestamp(oneWeekAgo.timeIntervalSince1970))
        
        XCTAssertFalse(relativeMinute.isEmpty)
        XCTAssertFalse(relativeHour.isEmpty)
        XCTAssertFalse(relativeDay.isEmpty)
        XCTAssertFalse(relativeWeek.isEmpty)
        
        // Test edge cases
        let future = now.addingTimeInterval(60)
        let relativeFuture = NDKUIRelativeTime.format(Timestamp(future.timeIntervalSince1970))
        XCTAssertFalse(relativeFuture.isEmpty)
    }
}