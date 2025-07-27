import XCTest
@testable import NDKSwift

final class ContentTaggerTests: XCTestCase {
    
    // MARK: - Hashtag Generation Tests
    
    func testGenerateHashtags_basicHashtags() {
        let content = "Hello #nostr community! #Bitcoin is amazing #NoStr"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 2)
        XCTAssertEqual(hashtags[0], "nostr")
        XCTAssertEqual(hashtags[1], "Bitcoin")
        // #NoStr is not included because it's case-insensitive duplicate
    }
    
    func testGenerateHashtags_withSpecialCharacters() {
        let content = "#test-tag #test.stop #test! #test@ #test#nested #test/slash"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 2)
        XCTAssertEqual(hashtags[0], "test-tag")
        XCTAssertEqual(hashtags[1], "test")
    }
    
    func testGenerateHashtags_atStartOfLine() {
        let content = "#start of line and #middle and at end #end"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 3)
        XCTAssertEqual(hashtags[0], "start")
        XCTAssertEqual(hashtags[1], "middle")
        XCTAssertEqual(hashtags[2], "end")
    }
    
    func testGenerateHashtags_noHashtags() {
        let content = "No hashtags in this content"
        let hashtags = ContentTagger.generateHashtags(from: content)
        
        XCTAssertEqual(hashtags.count, 0)
    }
    
    // MARK: - Decode Nostr Entity Tests
    
    func testDecodeNostrEntity_npub() throws {
        let npub = "npub1zxn88cfevsk4x06ngz6uuywv9de3dzp274qnwq6rsjrvgl0kgdqq9m2s4e"
        let decoded = try ContentTagger.decodeNostrEntity(npub)
        
        XCTAssertEqual(decoded.type, "npub")
        XCTAssertNotNil(decoded.pubkey)
        XCTAssertEqual(decoded.pubkey?.count, 64)
        XCTAssertNil(decoded.eventId)
        XCTAssertNil(decoded.relays)
    }
    
    func testDecodeNostrEntity_note() throws {
        let note = "note1gmtnz6q2m55epmlpe3semjdcpxay3lykfemgjua2g3s37s89qtqstskvl"
        let decoded = try ContentTagger.decodeNostrEntity(note)
        
        XCTAssertEqual(decoded.type, "note")
        XCTAssertNotNil(decoded.eventId)
        XCTAssertEqual(decoded.eventId?.count, 64)
        XCTAssertNil(decoded.pubkey)
        XCTAssertNil(decoded.relays)
    }
    
    func testDecodeNostrEntity_invalidBech32() {
        let invalidEntity = "npub1invalid"
        
        XCTAssertThrowsError(try ContentTagger.decodeNostrEntity(invalidEntity)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testDecodeNostrEntity_wrongDataLength() {
        // This is a valid bech32 but with wrong data length for npub
        let invalidNpub = "npub1qq"
        
        XCTAssertThrowsError(try ContentTagger.decodeNostrEntity(invalidNpub)) { error in
            if let ndkError = error as? NDKError {
                switch ndkError {
                case .invalidInput(let message):
                    XCTAssertTrue(message.contains("Expected 32 bytes"))
                default:
                    XCTFail("Wrong error type")
                }
            }
        }
    }
    
    // MARK: - Parse Content Segments Tests
    
    func testParseContentSegments_mixedContent() {
        let content = "Hello @npub1zxn88cfevsk4x06ngz6uuywv9de3dzp274qnwq6rsjrvgl0kgdqq9m2s4e! Check out #nostr and visit https://nostr.com"
        let result = ContentTagger.parseContentSegments(from: content)
        
        XCTAssertEqual(result.segments.count, 6)
        
        // Check segments
        if case .text(let text) = result.segments[0] {
            XCTAssertEqual(text, "Hello ")
        } else {
            XCTFail("Expected text segment")
        }
        
        if case .mention(let npub) = result.segments[1] {
            XCTAssertTrue(npub.hasPrefix("npub"))
        } else {
            XCTFail("Expected mention segment")
        }
        
        // Check tags
        XCTAssertTrue(result.tags.contains { $0[0] == "p" })
        XCTAssertTrue(result.tags.contains { $0[0] == "t" && $0[1] == "nostr" })
    }
    
    func testParseContentSegments_nostrPrefixedEntities() {
        let content = "Check this nostr:npub1zxn88cfevsk4x06ngz6uuywv9de3dzp274qnwq6rsjrvgl0kgdqq9m2s4e and nostr:note1gmtnz6q2m55epmlpe3semjdcpxay3lykfemgjua2g3s37s89qtqstskvl"
        let result = ContentTagger.parseContentSegments(from: content)
        
        // Should have text, mention, text, event, and possibly trailing text
        XCTAssertGreaterThanOrEqual(result.segments.count, 4)
        
        // Check tags
        XCTAssertTrue(result.tags.contains { $0[0] == "p" })
        XCTAssertTrue(result.tags.contains { $0[0] == "q" })
    }
    
    func testParseContentSegments_hashtags() {
        let content = "Topics: #bitcoin #lightning #nostr"
        let result = ContentTagger.parseContentSegments(from: content)
        
        let hashtagCount = result.segments.filter { segment in
            if case .hashtag = segment { return true }
            return false
        }.count
        
        XCTAssertEqual(hashtagCount, 3)
        XCTAssertEqual(result.tags.filter { $0[0] == "t" }.count, 3)
    }
    
    func testParseContentSegments_urls() {
        let content = "Check out https://nostr.com and https://github.com/nostr"
        let result = ContentTagger.parseContentSegments(from: content)
        
        let urlCount = result.segments.filter { segment in
            if case .url = segment { return true }
            return false
        }.count
        
        XCTAssertEqual(urlCount, 2)
    }
    
    // MARK: - Generate Content Tags Tests
    
    func testGenerateContentTags_basicContent() {
        let content = "Hello @npub1zxn88cfevsk4x06ngz6uuywv9de3dzp274qnwq6rsjrvgl0kgdqq9m2s4e #nostr"
        let contentTag = ContentTagger.generateContentTags(from: content)
        
        // Should normalize @npub to nostr:npub
        XCTAssertTrue(contentTag.content.contains("nostr:npub"))
        XCTAssertFalse(contentTag.content.contains("@npub"))
        
        // Should have p tag and t tag
        XCTAssertTrue(contentTag.tags.contains { $0[0] == "p" })
        XCTAssertTrue(contentTag.tags.contains { $0[0] == "t" && $0[1] == "nostr" })
    }
    
    func testGenerateContentTags_withExistingTags() {
        let content = "#bitcoin"
        let existingTags: [Tag] = [["e", "existingeventid"]]
        let contentTag = ContentTagger.generateContentTags(from: content, existingTags: existingTags)
        
        // Should preserve existing tags
        XCTAssertTrue(contentTag.tags.contains { $0[0] == "e" && $0[1] == "existingeventid" })
        // And add new ones
        XCTAssertTrue(contentTag.tags.contains { $0[0] == "t" && $0[1] == "bitcoin" })
    }
    
    func testGenerateContentTags_nostrPrefixNotDuplicated() {
        let content = "Check nostr:npub1zxn88cfevsk4x06ngz6uuywv9de3dzp274qnwq6rsjrvgl0kgdqq9m2s4e"
        let contentTag = ContentTagger.generateContentTags(from: content)
        
        // Should not modify already prefixed entities
        XCTAssertEqual(contentTag.content, content)
        
        // Should still generate tags
        XCTAssertTrue(contentTag.tags.contains { $0[0] == "p" })
    }
    
    // MARK: - Merge Tags Tests
    
    func testMergeTags_removeDuplicates() {
        let tags1: [Tag] = [["p", "pubkey1"], ["t", "nostr"]]
        let tags2: [Tag] = [["p", "pubkey1"], ["t", "bitcoin"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        // Should have 3 unique tags
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.filter { $0[0] == "p" && $0[1] == "pubkey1" }.count, 1)
    }
    
    func testMergeTags_preferLongerTags() {
        let tags1: [Tag] = [["e", "eventid"]]
        let tags2: [Tag] = [["e", "eventid", "wss://relay.nostr.com"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        // Should keep the longer tag with relay hint
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].count, 3)
        XCTAssertEqual(merged[0][2], "wss://relay.nostr.com")
    }
    
    func testMergeTags_differentTags() {
        let tags1: [Tag] = [["p", "pubkey1"], ["e", "event1"]]
        let tags2: [Tag] = [["p", "pubkey2"], ["t", "nostr"]]
        
        let merged = ContentTagger.mergeTags(tags1, tags2)
        
        // All tags should be preserved
        XCTAssertEqual(merged.count, 4)
    }
    
    // MARK: - Tag Validation Tests
    
    func testTagValidation_validTags() {
        let validPTag: Tag = ["p", String(repeating: "a", count: 64)]
        let validETag: Tag = ["e", String(repeating: "b", count: 64)]
        let validATag: Tag = ["a", "30023:pubkeyhex123456789012345678901234567890123456789012345678901234:identifier"]
        let validDTag: Tag = ["d", "identifier"]
        let validTTag: Tag = ["t", "hashtag"]
        let validRTag: Tag = ["r", "https://example.com"]
        
        XCTAssertTrue(validPTag.isValid)
        XCTAssertTrue(validETag.isValid)
        XCTAssertTrue(validATag.isValid)
        XCTAssertTrue(validDTag.isValid)
        XCTAssertTrue(validTTag.isValid)
        XCTAssertTrue(validRTag.isValid)
    }
    
    func testTagValidation_invalidTags() {
        let emptyTag: Tag = []
        let shortPTag: Tag = ["p", "tooshort"]
        let missingValueTag: Tag = ["t"]
        let invalidATag: Tag = ["a", "invalid:format"]
        
        XCTAssertFalse(emptyTag.isValid)
        XCTAssertFalse(shortPTag.isValid)
        XCTAssertFalse(missingValueTag.isValid)
        XCTAssertFalse(invalidATag.isValid)
    }
    
    func testTagAccessors() {
        let tag: Tag = ["e", "eventid", "wss://relay.com", "reply"]
        
        XCTAssertEqual(tag.name, "e")
        XCTAssertEqual(tag.value, "eventid")
        XCTAssertEqual(tag.relayHint, "wss://relay.com")
        XCTAssertEqual(tag.marker, "reply")
    }
    
    // MARK: - NDKFilter Extension Tests
    
    func testNDKFilterExtensions() {
        var filter = NDKFilter()
        
        filter.addHashtagFilter("Nostr", "Bitcoin")
        XCTAssertTrue(filter.hasTagFilter("t"))
        XCTAssertEqual(filter.tagFilter("t"), ["nostr", "bitcoin"]) // Should be lowercased
        
        filter.addURLFilter("https://example.com")
        XCTAssertTrue(filter.hasTagFilter("r"))
        XCTAssertEqual(filter.tagFilter("r"), ["https://example.com"])
    }
}