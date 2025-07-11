import XCTest
@testable import NDKSwift

final class ContentTaggerNostrEntityTests: XCTestCase {
    
    // Use valid test entities
    let validNpub = TestEntities.validNpub
    let validNpub2 = TestEntities.validNpub2
    let validNote = TestEntities.validNote
    let validNevent = TestEntities.validNevent
    let validNprofile = TestEntities.validNprofile
    let validNaddr = TestEntities.validNaddr
    
    func testNeventGeneratesQTag() throws {
        let content = "Check out this event: nostr:\(validNevent)"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("=== testNeventGeneratesQTag ===")
        print("Input content: \(content)")
        print("Output content: \(result.content)")
        print("Generated tags: \(result.tags)")
        print("Tag count: \(result.tags.count)")
        
        // Should generate a 'q' tag for the event
        let qTags = result.tags.filter { $0.first == "q" }
        XCTAssertEqual(qTags.count, 1, "Should generate exactly one 'q' tag")
        
        if let qTag = qTags.first {
            XCTAssertEqual(qTag.count, 3, "Q tag should have 3 elements: ['q', eventId, relay]")
            XCTAssertEqual(qTag[0], "q")
            XCTAssertEqual(qTag[1], TestEntities.testEventId)
            XCTAssertTrue(qTag[2].contains("wss://"), "Third element should be a relay URL")
        }
        
        // Should also generate a 'p' tag for the author
        let pTags = result.tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1, "Should generate exactly one 'p' tag for the author")
    }
    
    func testNprofileGeneratesPTag() throws {
        let content = "Follow this person: nostr:\(validNprofile)"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        
        // Should generate a 'p' tag for the profile
        let pTags = result.tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1, "Should generate exactly one 'p' tag")
        
        if let pTag = pTags.first {
            XCTAssertEqual(pTag.count, 2, "P tag should have 2 elements: ['p', pubkey]")
            XCTAssertEqual(pTag[0], "p")
            XCTAssertEqual(pTag[1], "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
        }
    }
    
    func testNaddrGeneratesQAndPTags() throws {
        let content = "Read this article: nostr:\(validNaddr)"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        
        // Should generate a 'q' tag for the addressable event
        let qTags = result.tags.filter { $0.first == "q" }
        XCTAssertEqual(qTags.count, 1, "Should generate exactly one 'q' tag")
        
        if let qTag = qTags.first {
            XCTAssertEqual(qTag.count, 3, "Q tag should have 3 elements: ['q', eventId, relay]")
            XCTAssertEqual(qTag[0], "q")
            // For naddr, eventId is constructed as "kind:pubkey:identifier"
            XCTAssertTrue(qTag[1].contains(":"), "naddr eventId should be in format kind:pubkey:identifier")
        }
        
        // Should also generate a 'p' tag for the author
        let pTags = result.tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1, "Should generate exactly one 'p' tag for the author")
    }
    
    func testMultipleEntitiesInContent() throws {
        let content = """
        Check out nostr:\(validNevent) by nostr:\(validNprofile).
        Also read nostr:\(validNaddr) and follow nostr:\(validNpub2)!
        """
        
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        print("Number of tags: \(result.tags.count)")
        
        // Count different types of tags
        let qTags = result.tags.filter { $0.first == "q" }
        let pTags = result.tags.filter { $0.first == "p" }
        
        print("Q tags: \(qTags.count)")
        print("P tags: \(pTags.count)")
        
        // Should have 2 'q' tags (nevent and naddr)
        XCTAssertEqual(qTags.count, 2, "Should generate two 'q' tags")
        
        // Should have multiple 'p' tags (but duplicates removed)
        XCTAssertGreaterThanOrEqual(pTags.count, 2, "Should generate at least two 'p' tags")
    }
    
    func testAtMentionFormat() throws {
        let content = "Hey @\(validNpub), check this out!"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        
        // Should convert @npub to nostr:npub format
        XCTAssertTrue(result.content.contains("nostr:\(validNpub)"), "Should convert @npub to nostr:npub format")
        
        // Should generate a 'p' tag
        let pTags = result.tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1, "Should generate exactly one 'p' tag")
    }
    
    func testInvalidBech32HandledGracefully() throws {
        let content = "This is invalid: nostr:npub1invalid and nostr:neventbaddata"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        
        // Should not crash and should leave invalid entities unchanged
        XCTAssertTrue(result.content.contains("nostr:npub1invalid"), "Invalid entities should remain in content")
        XCTAssertTrue(result.content.contains("nostr:neventbaddata"), "Invalid entities should remain in content")
        
        // Should not generate tags for invalid entities
        XCTAssertEqual(result.tags.count, 0, "Should not generate tags for invalid entities")
    }
    
    func testHashtagsAlongWithNostrEntities() throws {
        let content = "Check out nostr:\(validNevent) #nostr #bitcoin"
        let result = ContentTagger.generateContentTags(from: content)
        
        print("Content: \(result.content)")
        print("Tags: \(result.tags)")
        
        // Should have both 'q' and 't' tags
        let qTags = result.tags.filter { $0.first == "q" }
        let tTags = result.tags.filter { $0.first == "t" }
        
        XCTAssertEqual(qTags.count, 1, "Should generate one 'q' tag")
        XCTAssertEqual(tTags.count, 2, "Should generate two 't' tags for hashtags")
        
        // Check hashtag values are lowercase
        for tTag in tTags {
            if tTag.count > 1 {
                XCTAssertEqual(tTag[1], tTag[1].lowercased(), "Hashtag should be lowercase")
            }
        }
    }
    
    func testParseContentSegments() throws {
        let content = "Hey @\(validNpub), check out nostr:\(validNevent) #nostr"
        let result = ContentTagger.parseContentSegments(from: content)
        
        print("Segments: \(result.segments)")
        print("Tags: \(result.tags)")
        
        // Verify segment types
        var hasText = false
        var hasMention = false
        var hasEvent = false
        var hasHashtag = false
        
        for segment in result.segments {
            switch segment {
            case .text:
                hasText = true
            case .mention:
                hasMention = true
            case .event:
                hasEvent = true
            case .hashtag:
                hasHashtag = true
            case .url:
                break
            }
        }
        
        XCTAssertTrue(hasText, "Should have text segments")
        XCTAssertTrue(hasMention, "Should have mention segment")
        XCTAssertTrue(hasEvent, "Should have event segment")
        XCTAssertTrue(hasHashtag, "Should have hashtag segment")
        
        // Verify tags were generated
        let pTags = result.tags.filter { $0.first == "p" }
        let qTags = result.tags.filter { $0.first == "q" }
        let tTags = result.tags.filter { $0.first == "t" }
        
        XCTAssertGreaterThan(pTags.count, 0, "Should generate p tags")
        XCTAssertGreaterThan(qTags.count, 0, "Should generate q tags")
        XCTAssertGreaterThan(tTags.count, 0, "Should generate t tags")
    }
}