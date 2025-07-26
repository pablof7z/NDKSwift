import XCTest
@testable import NDKSwift

final class ContentParserTests: XCTestCase {
    
    func testBasicTextParsing() {
        let content = "Hello World"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        XCTAssertEqual(entities.count, 1)
        if case .text(let text) = entities[0] {
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected text segment")
        }
        XCTAssertEqual(normalizedContent, "Hello World")
    }
    
    func testHashtagExtraction() {
        let content = "Testing #nostr #bitcoin tags"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Count hashtag entities
        let hashtagCount = entities.filter { entity in
            if case .hashtag = entity { return true }
            return false
        }.count
        
        XCTAssertEqual(hashtagCount, 2)
    }
    
    func testURLExtraction() {
        let content = "Visit https://nostr.com for more info"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Check for URL entity
        let hasURL = entities.contains { entity in
            if case .url = entity { return true }
            return false
        }
        
        XCTAssertTrue(hasURL)
    }
    
    func testNostrEntityExtraction() {
        let content = "Check out nostr:npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find npub entity
        let hasNpub = entities.contains { entity in
            if case .npub = entity { return true }
            return false
        }
        
        XCTAssertTrue(hasNpub)
        XCTAssertEqual(normalizedContent, content) // Should remain unchanged
    }
    
    func testAtMentionNormalization() {
        let content = "Hello @npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should normalize @ mentions to nostr: format
        XCTAssertTrue(normalizedContent.contains("nostr:npub"))
        XCTAssertFalse(normalizedContent.contains("@npub"))
        
        // Should find npub entity
        let hasNpub = entities.contains { entity in
            if case .npub = entity { return true }
            return false
        }
        XCTAssertTrue(hasNpub)
    }
    
    func testEmptyContent() {
        let (entities, normalizedContent) = ContentParser.parseContent("")
        XCTAssertTrue(entities.isEmpty)
        XCTAssertEqual(normalizedContent, "")
    }
    
    func testMixedContent() {
        let content = "#nostr is awesome! Check https://nostr.com"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Should have multiple entity types
        let hasHashtag = entities.contains { entity in
            if case .hashtag = entity { return true }
            return false
        }
        let hasURL = entities.contains { entity in
            if case .url = entity { return true }
            return false
        }
        let hasText = entities.contains { entity in
            if case .text = entity { return true }
            return false
        }
        
        XCTAssertTrue(hasHashtag)
        XCTAssertTrue(hasURL)
        XCTAssertTrue(hasText)
    }
}