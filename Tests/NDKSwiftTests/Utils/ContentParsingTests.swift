import XCTest
@testable import NDKSwift

final class ContentParsingTests: XCTestCase {
    
    // MARK: - ContentTagger Tests
    
    func testParseContentSegments_PlainText() {
        let content = "This is plain text with no special entities"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 1)
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, content)
        } else {
            XCTFail("Expected text segment")
        }
        XCTAssertEqual(result.tags.count, 0)
    }
    
    func testParseContentSegments_WithHashtags() {
        let content = "Check out #nostr and #bitcoin news!"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 5)
        
        // Verify segments
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, "Check out ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .hashtag(let tag) = result.segments[1] {
            XCTAssertEqual(tag, "nostr")
        } else {
            XCTFail("Expected hashtag segment")
        }
        
        if case .text(let text) = result.segments[2] {
            XCTAssertEqual(text, " and ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .hashtag(let tag) = result.segments[3] {
            XCTAssertEqual(tag, "bitcoin")
        } else {
            XCTFail("Expected hashtag segment")
        }
        
        // Verify tags
        XCTAssertEqual(result.tags.count, 2)
        XCTAssertTrue(result.tags.contains(["t", "nostr"]))
        XCTAssertTrue(result.tags.contains(["t", "bitcoin"]))
    }
    
    func testParseContentSegments_WithMentions() {
        let content = "Hello @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft!"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 3)
        
        // Verify segments
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, "Hello ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .mention(let npub) = result.segments[1] {
            XCTAssertEqual(npub, "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft")
        } else {
            XCTFail("Expected mention segment")
        }
        
        // Verify tags
        XCTAssertEqual(result.tags.count, 1)
        XCTAssertEqual(result.tags[0][0], "p")
        XCTAssertEqual(result.tags[0][1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
    }
    
    func testParseContentSegments_WithNostrEntities() {
        let content = "Check out nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft and nostr:note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpuy0p2x"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 4)
        
        // Verify that nostr: prefixed entities are parsed
        var mentionFound = false
        var eventFound = false
        
        for segment in result.segments {
            switch segment {
            case .mention(let npub):
                XCTAssertEqual(npub, "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft")
                mentionFound = true
            case .event(let nevent):
                XCTAssertEqual(nevent, "note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqpuy0p2x")
                eventFound = true
            default:
                break
            }
        }
        
        XCTAssertTrue(mentionFound, "Mention not found")
        XCTAssertTrue(eventFound, "Event not found")
        
        // Verify tags
        XCTAssertEqual(result.tags.count, 2)
    }
    
    func testParseContentSegments_WithURLs() {
        let content = "Visit https://nostr.com and https://example.org/path for more info"
        let result = ContentTagger.parseContentSegments(from: content)
        
        var urlCount = 0
        for segment in result.segments {
            if case .url = segment {
                urlCount += 1
            }
        }
        
        XCTAssertEqual(urlCount, 2)
    }
    
    func testParseContentSegments_ComplexContent() {
        let content = "Hey @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft, check out #nostr at https://nostr.com"
        let result = ContentTagger.parseContentSegments(from: content)
        
        // Should have: text, mention, text, hashtag, text, url
        XCTAssertEqual(result.segments.count, 6)
        
        var hasText = false
        var hasMention = false
        var hasHashtag = false
        var hasURL = false
        
        for segment in result.segments {
            switch segment {
            case .text: hasText = true
            case .mention: hasMention = true
            case .hashtag: hasHashtag = true
            case .url: hasURL = true
            case .event: break
            }
        }
        
        XCTAssertTrue(hasText)
        XCTAssertTrue(hasMention)
        XCTAssertTrue(hasHashtag)
        XCTAssertTrue(hasURL)
    }
    
    // MARK: - NDK parseContent Tests
    
    func testParseContent_WithFetchDisabled() async throws {
        let ndk = NDK(relayUrls: [])
        let content = "Hello @npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft!"
        
        let options = ParseContentOptions(
            fetchUserProfiles: false,
            fetchReferencedEvents: false
        )
        
        let parsed = try await ndk.parseContent(content, options: options)
        
        XCTAssertEqual(parsed.original, content)
        XCTAssertEqual(parsed.segments.count, 3)
        
        // Should still create NDKUser without fetching profile
        if case .mention(let user) = parsed.segments[1] {
            XCTAssertEqual(user.npub, "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft")
            XCTAssertNil(await user.profile)
        } else {
            XCTFail("Expected mention segment")
        }
    }
    
    func testParseContent_InvalidNpub() async throws {
        let ndk = NDK(relayUrls: [])
        let content = "Hello @npub1invalid!"
        
        let parsed = try await ndk.parseContent(content)
        
        // Invalid npub should be treated as text
        var foundInvalidAsText = false
        for segment in parsed.segments {
            if case .text(let text) = segment, text.contains("@npub1invalid") {
                foundInvalidAsText = true
            }
        }
        
        XCTAssertTrue(foundInvalidAsText, "Invalid npub should be treated as text")
    }
    
    func testParseContent_HashtagsAndURLsOptions() async throws {
        let ndk = NDK(relayUrls: [])
        let content = "Check out #nostr at https://nostr.com"
        
        // Test with hashtags and URLs disabled
        let options = ParseContentOptions(
            fetchUserProfiles: false,
            fetchReferencedEvents: false,
            includeHashtags: false,
            includeURLs: false
        )
        
        let parsed = try await ndk.parseContent(content, options: options)
        
        // Hashtags and URLs should be converted to text
        for segment in parsed.segments {
            switch segment {
            case .hashtag:
                XCTFail("Hashtags should be disabled")
            case .url:
                XCTFail("URLs should be disabled")
            default:
                break
            }
        }
    }
}

// MARK: - Test Helpers

extension Array where Element == ContentTagger.ParseSegment {
    func contains(text: String) -> Bool {
        return self.contains { segment in
            if case .text(let segmentText) = segment {
                return segmentText == text
            }
            return false
        }
    }
}