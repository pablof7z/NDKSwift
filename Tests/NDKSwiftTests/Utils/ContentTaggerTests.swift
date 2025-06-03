import XCTest
@testable import NDKSwift

final class ContentTaggerTests: XCTestCase {
    
    // MARK: - Hashtag Tests
    
    func testGenerateHashtags() {
        let content = "This is a #test with multiple #hashtags and #Bitcoin"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 3)
        XCTAssertTrue(hashtags.contains("test"))
        XCTAssertTrue(hashtags.contains("hashtags"))
        XCTAssertTrue(hashtags.contains("Bitcoin"))
    }
    
    func testGenerateHashtagsWithDuplicates() {
        let content = "Testing #bitcoin and #BITCOIN and #Bitcoin"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        // Should only return the first occurrence (case-insensitive deduplication)
        XCTAssertEqual(hashtags.count, 1)
        XCTAssertEqual(hashtags.first, "bitcoin")
    }
    
    func testGenerateHashtagsWithSpecialCharacters() {
        let content = "Invalid #test@ #test! #test# but valid #test_123 and #test-456"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        // Should only include valid hashtags (no special characters except _ and -)
        XCTAssertEqual(hashtags.count, 2)
        XCTAssertTrue(hashtags.contains("test_123"))
        XCTAssertTrue(hashtags.contains("test-456"))
    }
    
    func testGenerateHashtagsAtStringBoundaries() {
        let content = "#start middle #end"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 2)
        XCTAssertTrue(hashtags.contains("start"))
        XCTAssertTrue(hashtags.contains("end"))
    }
    
    // MARK: - Nostr Entity Decoding Tests
    
    func testDecodeNpub() throws {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let decoded = try ContentTagger.decodeNostrEntity(npub)
        
        XCTAssertEqual(decoded.type, "npub")
        XCTAssertEqual(decoded.pubkey, "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
        XCTAssertNil(decoded.eventId)
        XCTAssertNil(decoded.relays)
    }
    
    func testDecodeNote() throws {
        let note = "note1fntxf5qq4z6fmk186mwwu7t0972rcez8cejatp0698lrzspsuyqq9m4vm7"
        let decoded = try ContentTagger.decodeNostrEntity(note)
        
        XCTAssertEqual(decoded.type, "note")
        XCTAssertNotNil(decoded.eventId)
        XCTAssertEqual(decoded.eventId?.count, 64) // Should be 32 bytes = 64 hex chars
        XCTAssertNil(decoded.pubkey)
        XCTAssertNil(decoded.relays)
    }
    
    // MARK: - Content Tag Generation Tests
    
    func testGenerateContentTagsWithHashtags() {
        let content = "This is a #test post about #bitcoin"
        let result = ContentTagger.generateContentTags(from: content)
        
        XCTAssertEqual(result.content, content) // Content should remain unchanged for hashtags
        
        let tTags = result.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)
        
        let tagValues = tTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(tagValues.contains("test"))
        XCTAssertTrue(tagValues.contains("bitcoin"))
    }
    
    func testGenerateContentTagsWithNpub() {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let content = "Hello @\(npub) how are you?"
        let result = ContentTagger.generateContentTags(from: content)
        
        // Content should be normalized to nostr: format
        XCTAssertTrue(result.content.contains("nostr:\(npub)"))
        
        // Should have a 'p' tag with hex pubkey
        let pTags = result.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
    }
    
    func testGenerateContentTagsWithNostrPrefix() {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let content = "Hello nostr:\(npub) how are you?"
        let result = ContentTagger.generateContentTags(from: content)
        
        // Content should remain the same (already normalized)
        XCTAssertEqual(result.content, content)
        
        // Should have a 'p' tag with hex pubkey
        let pTags = result.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?[1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
    }
    
    func testGenerateContentTagsWithNote() {
        let note = "note1fntxf5qq4z6fmk186mwwu7t0972rcez8cejatp0698lrzspsuyqq9m4vm7"
        let content = "Check out this note: @\(note)"
        let result = ContentTagger.generateContentTags(from: content)
        
        // Content should be normalized
        XCTAssertTrue(result.content.contains("nostr:\(note)"))
        
        // Should have a 'q' tag with hex event ID
        let qTags = result.tags.filter { $0[0] == "q" }
        XCTAssertEqual(qTags.count, 1)
        XCTAssertEqual(qTags.first?.count, 3) // q, eventId, relay (empty)
        XCTAssertEqual(qTags.first?[1].count, 64) // Hex event ID should be 64 chars
    }
    
    func testGenerateContentTagsWithMixedContent() {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let content = "Hello @\(npub)! This is about #bitcoin and #nostr"
        let result = ContentTagger.generateContentTags(from: content)
        
        // Should have both p tags and t tags
        let pTags = result.tags.filter { $0[0] == "p" }
        let tTags = result.tags.filter { $0[0] == "t" }
        
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(tTags.count, 2)
        XCTAssertEqual(pTags.first?[1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
        
        let tagValues = tTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(tagValues.contains("bitcoin"))
        XCTAssertTrue(tagValues.contains("nostr"))
    }
    
    func testGenerateContentTagsWithExistingTags() {
        let existingTags: [Tag] = [["p", "existing_pubkey"], ["t", "existing_tag"]]
        let content = "This is about #bitcoin"
        let result = ContentTagger.generateContentTags(from: content, existingTags: existingTags)
        
        // Should preserve existing tags and add new ones
        XCTAssertTrue(result.tags.contains(["p", "existing_pubkey"]))
        XCTAssertTrue(result.tags.contains(["t", "existing_tag"]))
        XCTAssertTrue(result.tags.contains(["t", "bitcoin"]))
        XCTAssertEqual(result.tags.count, 3)
    }
    
    func testGenerateContentTagsWithDuplicateTags() {
        let existingTags: [Tag] = [["t", "bitcoin"]]
        let content = "This is about #bitcoin again"
        let result = ContentTagger.generateContentTags(from: content, existingTags: existingTags)
        
        // Should not duplicate existing tags
        let tTags = result.tags.filter { $0[0] == "t" && $0[1] == "bitcoin" }
        XCTAssertEqual(tTags.count, 1)
    }
    
    func testGenerateContentTagsWithInvalidEntities() {
        let content = "Invalid @npub123 and @invalidformat should be ignored"
        let result = ContentTagger.generateContentTags(from: content)
        
        // Should not add any p tags for invalid entities
        let pTags = result.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 0)
        
        // Content should remain unchanged for invalid entities
        XCTAssertEqual(result.content, content)
    }
    
    // MARK: - Tag Merging Tests
    
    func testMergeTags() {
        let tags1: [Tag] = [["p", "pubkey1"], ["t", "bitcoin"]]
        let tags2: [Tag] = [["p", "pubkey2"], ["t", "bitcoin"], ["e", "eventid1"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        // Should contain all unique tags
        XCTAssertTrue(merged.contains(["p", "pubkey1"]))
        XCTAssertTrue(merged.contains(["p", "pubkey2"]))
        XCTAssertTrue(merged.contains(["e", "eventid1"]))
        
        // Should deduplicate identical tags
        let bitcoinTags = merged.filter { $0.count > 1 && $0[0] == "t" && $0[1] == "bitcoin" }
        XCTAssertEqual(bitcoinTags.count, 1)
    }
    
    func testMergeTagsWithContainment() {
        let tags1: [Tag] = [["e", "eventid1"]]
        let tags2: [Tag] = [["e", "eventid1", "relay.example.com"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        // Should prefer the more detailed tag
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first, ["e", "eventid1", "relay.example.com"])
    }
    
    // MARK: - Edge Cases
    
    func testGenerateContentTagsWithEmptyContent() {
        let result = ContentTagger.generateContentTags(from: "")
        
        XCTAssertEqual(result.content, "")
        XCTAssertEqual(result.tags.count, 0)
    }
    
    func testGenerateContentTagsWithOnlyWhitespace() {
        let result = ContentTagger.generateContentTags(from: "   \n\t  ")
        
        XCTAssertEqual(result.content, "   \n\t  ")
        XCTAssertEqual(result.tags.count, 0)
    }
    
    func testGenerateHashtagsWithUnicodeCharacters() {
        let content = "Testing #bitcoin #ビットコイン #🚀"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        // Should handle unicode characters in hashtags
        XCTAssertTrue(hashtags.contains("bitcoin"))
        XCTAssertTrue(hashtags.contains("ビットコイン"))
        XCTAssertTrue(hashtags.contains("🚀"))
    }
}