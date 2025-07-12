import XCTest
@testable import NDKSwift

final class ContentTaggerTests: XCTestCase {
    
    // MARK: - Hashtag Tests
    
    func testHashtagExtraction() {
        let content = "Hello #nostr world! #bitcoin is awesome #Lightning"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 3)
        XCTAssertEqual(hashtags[0], "nostr")
        XCTAssertEqual(hashtags[1], "bitcoin")
        XCTAssertEqual(hashtags[2], "Lightning")
    }
    
    func testHashtagDuplicateHandling() {
        let content = "#bitcoin is great! I love #Bitcoin and #BITCOIN"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 1)
        XCTAssertEqual(hashtags[0], "bitcoin") // First occurrence
    }
    
    func testHashtagWithSpecialCharacters() {
        let content = "#valid-tag #also_valid #not!valid #no@valid"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 4)
        XCTAssertEqual(hashtags[0], "valid-tag")
        XCTAssertEqual(hashtags[1], "also_valid")
        XCTAssertEqual(hashtags[2], "not")  // Extracts valid part before !
        XCTAssertEqual(hashtags[3], "no")   // Extracts valid part before @
    }
    
    func testHashtagAtStart() {
        let content = "#start of the message"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 1)
        XCTAssertEqual(hashtags[0], "start")
    }
    
    // MARK: - Nostr Entity Tests
    
    func testNpubDecoding() throws {
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let decoded = try ContentTagger.decodeNostrEntity(npub)
        
        XCTAssertEqual(decoded.type, "npub")
        XCTAssertNotNil(decoded.pubkey)
        XCTAssertEqual(decoded.pubkey?.count, 64) // Hex string length
    }
    
    func testNoteDecoding() throws {
        let note = "note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqxawlyf"
        let decoded = try ContentTagger.decodeNostrEntity(note)
        
        XCTAssertEqual(decoded.type, "note")
        XCTAssertNotNil(decoded.eventId)
        XCTAssertEqual(decoded.eventId?.count, 64)
    }
    
    // MARK: - Content Tag Generation Tests
    
    func testSimpleHashtagGeneration() {
        let content = "Hello #nostr world!"
        let result = ContentTagger.generateContentTags(from: content)
        
        XCTAssertEqual(result.content, content) // Content unchanged for hashtags
        XCTAssertEqual(result.tags.count, 1)
        XCTAssertEqual(result.tags[0], ["t", "nostr"])
    }
    
    func testNpubMentionGeneration() {
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let content = "Hello @\(npub)!"
        let result = ContentTagger.generateContentTags(from: content)
        
        XCTAssertEqual(result.content, "Hello nostr:\(npub)!")
        XCTAssertEqual(result.tags.count, 1)
        XCTAssertEqual(result.tags[0][0], "p")
        XCTAssertNotNil(result.tags[0][1])
    }
    
    func testNostrPrefixedEntity() {
        // Use a valid bech32 npub
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let content = "Check out nostr:\(npub)"
        let result = ContentTagger.generateContentTags(from: content)
        
        XCTAssertEqual(result.content, content) // Already in nostr: format
        XCTAssertEqual(result.tags.count, 1)
        XCTAssertEqual(result.tags[0][0], "p")
    }
    
    func testMixedContent() {
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let note = "note1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqxawlyf"
        let content = "Hello @\(npub)! Check out nostr:\(note) #nostr #bitcoin"
        
        let result = ContentTagger.generateContentTags(from: content)
        
        // Check content normalization
        XCTAssertTrue(result.content.contains("nostr:\(npub)"))
        XCTAssertTrue(result.content.contains("nostr:\(note)"))
        
        // Check tags
        let pTags = result.tags.filter { $0[0] == "p" }
        let qTags = result.tags.filter { $0[0] == "q" }
        let tTags = result.tags.filter { $0[0] == "t" }
        
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(qTags.count, 1)
        XCTAssertEqual(tTags.count, 2)
        XCTAssertTrue(tTags.contains(["t", "nostr"]))
        XCTAssertTrue(tTags.contains(["t", "bitcoin"]))
    }
    
    func testDuplicateTagHandling() {
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let content = "Hello @\(npub) and @\(npub) again #nostr #nostr"
        
        let result = ContentTagger.generateContentTags(from: content)
        
        let pTags = result.tags.filter { $0[0] == "p" }
        let tTags = result.tags.filter { $0[0] == "t" }
        
        XCTAssertEqual(pTags.count, 1) // Duplicate removed
        XCTAssertEqual(tTags.count, 1) // Duplicate removed
    }
    
    // MARK: - Tag Merging Tests
    
    func testMergeTagsBasic() {
        let tags1 = [["p", "pubkey1"], ["t", "nostr"]]
        let tags2 = [["p", "pubkey2"], ["t", "bitcoin"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        XCTAssertEqual(merged.count, 4)
    }
    
    func testMergeTagsDuplicates() {
        let tags1 = [["p", "pubkey1"], ["t", "nostr"]]
        let tags2 = [["p", "pubkey1"], ["t", "bitcoin"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        XCTAssertEqual(merged.count, 3) // One duplicate removed
    }
    
    func testMergeTagsWithRelayHints() {
        let tags1 = [["p", "pubkey1"]]
        let tags2 = [["p", "pubkey1", "wss://relay.example.com"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].count, 3) // Longer tag with relay hint preferred
    }
    
    // MARK: - Parse Content Segments Tests
    
    func testParseContentSegments() {
        let npub = "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqsdty9mx"
        let content = "Hello @\(npub) #nostr https://example.com"
        
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 6)
        
        // Check segment types
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, "Hello ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .mention = result.segments[1] {
            // Success
        } else {
            XCTFail("Expected mention segment")
        }
        
        if case .text(let text) = result.segments[2] {
            XCTAssertEqual(text, " ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .hashtag(let tag) = result.segments[3] {
            XCTAssertEqual(tag, "nostr")
        } else {
            XCTFail("Expected hashtag segment")
        }
        
        if case .text(let text) = result.segments[4] {
            XCTAssertEqual(text, " ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .url = result.segments[5] {
            // Success
        } else {
            XCTFail("Expected URL segment")
        }
    }
    
    func testParseContentWithNoEntities() {
        let content = "Just plain text"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 1)
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, content)
        } else {
            XCTFail("Expected text segment")
        }
        XCTAssertEqual(result.tags.count, 0)
    }
}