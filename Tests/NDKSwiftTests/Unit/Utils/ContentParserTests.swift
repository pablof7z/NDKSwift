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
        XCTAssertEqual(entities.countOf(.hashtag), 2)
    }
    
    func testURLExtraction() {
        let content = "Visit https://nostr.com for more info"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Check for URL entity
        XCTAssertTrue(entities.containsURL())
    }
    
    func testNostrEntityExtraction() {
        let content = "Check out nostr:npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find npub entity
        XCTAssertTrue(entities.containsNpub())
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
        XCTAssertTrue(entities.containsHashtag())
        XCTAssertTrue(entities.containsURL())
        XCTAssertTrue(entities.containsText())
    }
    
    func testNprofileExtraction() {
        let content = "Follow nostr:nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpz4mhxue69uhhyetvv9ujuerpd46hxtnfduhszrnhwden5te0dehhxtnvdakz7qg3waehxw309ahx7um5wgh8w6twv5hsygczx"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find nprofile entity
        XCTAssertTrue(entities.containsNprofile())
        XCTAssertEqual(normalizedContent, content) // Should remain unchanged
    }
    
    func testNoteExtraction() {
        let content = "Check out this note: nostr:note1g0825j5xv09h0dcnq6h9s0d2ckfg7xl29fy8xgksx8u3qj3n5hwqmeukjh"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find note entity
        XCTAssertTrue(entities.containsNote())
        XCTAssertEqual(normalizedContent, content) // Should remain unchanged
    }
    
    func testNeventExtraction() {
        let content = "Event reference: nostr:nevent1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpz4mhxue69uhkyetvv9ujuumn0wd68ytnvv9hxgurhv5hsz9thwden5te0wfjkccte9ejxzmt4wvhxjme0qyv8wumn8ghj7mn0wd68ytnddakj7a8f9uh"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find nevent entity
        XCTAssertTrue(entities.containsNevent())
        XCTAssertEqual(normalizedContent, content) // Should remain unchanged
    }
    
    func testNaddrExtraction() {
        let content = "Address: nostr:naddr1qq9rzd3exgenyv3exverwwp5xqmn2d3exuuxxd3kxqmrjv3jxqcnvdpnxqcnvdejxqcnvdekxqcrqvpsxqcrqvpsxqcrqvps8qhrzd3exgenyv3exverwwp5qqgywfvj0v5cxjmrv9ejx2tcpr4sp8t50j9ph3k9u0kavq9xge6r4l3ff5j9"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Should find naddr entity
        XCTAssertTrue(entities.containsNaddr())
        XCTAssertEqual(normalizedContent, content) // Should remain unchanged
    }
    
    func testMultipleHashtagsExtraction() {
        let content = "Building with #nostr #swift #iOS #development"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Count hashtag entities
        XCTAssertEqual(entities.countOf(.hashtag), 4)
        
        // Verify specific hashtags
        let hashtags = entities.hashtags
        
        XCTAssertTrue(hashtags.contains("nostr"))
        XCTAssertTrue(hashtags.contains("swift"))
        XCTAssertTrue(hashtags.contains("iOS"))
        XCTAssertTrue(hashtags.contains("development"))
    }
    
    func testComplexMixedContent() {
        let content = "Hey @npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk, check out #bitcoin at https://bitcoin.org and this note: nostr:note1g0825j5xv09h0dcnq6h9s0d2ckfg7xl29fy8xgksx8u3qj3n5hwqmeukjh"
        let (entities, normalizedContent) = ContentParser.parseContent(content)
        
        // Check that @ mention was normalized to nostr: format
        XCTAssertTrue(normalizedContent.contains("nostr:npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk"))
        XCTAssertFalse(normalizedContent.contains("@npub"))
        
        // Should have all entity types
        let entityTypes = entities.map { entity -> String in
            switch entity {
            case .text: return "text"
            case .npub: return "npub"
            case .nprofile: return "nprofile"
            case .note: return "note"
            case .nevent: return "nevent"
            case .naddr: return "naddr"
            case .hashtag: return "hashtag"
            case .url: return "url"
            case .userMention: return "userMention"
            case .eventMention: return "eventMention"
            }
        }
        
        XCTAssertTrue(entityTypes.contains("npub"))
        XCTAssertTrue(entityTypes.contains("hashtag"))
        XCTAssertTrue(entityTypes.contains("url"))
        XCTAssertTrue(entityTypes.contains("note"))
        XCTAssertTrue(entityTypes.contains("text"))
    }
    
    func testInvalidNostrEntity() {
        let content = "Invalid entity: nostr:npub1invalidstring"
        let (entities, _) = ContentParser.parseContent(content)
        
        // Should treat invalid entity as text
        XCTAssertGreaterThan(entities.countOf(.text), 0)
    }
    
    func testWhitespacePreservation() {
        let content = "  Start with spaces\n\nDouble newline\t\tTabs  "
        let (_, normalizedContent) = ContentParser.parseContent(content)
        
        // Should preserve whitespace
        XCTAssertEqual(normalizedContent, content)
    }
}