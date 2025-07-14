import XCTest
@testable import NDKSwift

final class NDKEventBuilderContentTagTests: XCTestCase {
    
    let mockSigner = MockSigner(privateKey: "9ef8c7f55e2ac89b8cf3796c915c5b37e3b2dc4fa6cd887a32065df5790b3c96")
    
    // MARK: - Basic Content Tag Generation
    
    func testHashtagGeneration() async throws {
        let event = try await NDKEventBuilder()
            .content("Hello #nostr world! #bitcoin")
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        // Check that hashtags were added
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)
        XCTAssertTrue(tTags.contains(["t", "nostr"]))
        XCTAssertTrue(tTags.contains(["t", "bitcoin"]))
        
        // Content should remain unchanged for hashtags
        XCTAssertEqual(event.content, "Hello #nostr world! #bitcoin")
    }
    
    func testNpubMentionGeneration() async throws {
        let npub = TestEntities.validNpub
        let content = "Hello @\(npub)!"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        // Check that p tag was added
        let pTags = event.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertNotNil(pTags[0][1])
        
        // Content should be normalized
        XCTAssertEqual(event.content, "Hello nostr:\(npub)!")
    }
    
    func testDisableContentTagGeneration() async throws {
        let event = try await NDKEventBuilder()
            .content("Hello #nostr @" + TestEntities.validNpub)
            .kind(EventKind.textNote)
            .build(signer: mockSigner, generateContentTags: false)
        
        // No tags should be generated
        XCTAssertEqual(event.tags.count, 0)
        
        // Content should remain unchanged
        XCTAssertTrue(event.content.contains("@npub"))
    }
    
    // MARK: - Mixed Content Tests
    
    func testMixedContentWithExistingTags() async throws {
        let npub = TestEntities.validNpub
        let content = "Reply to @\(npub) #nostr"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .tag(["e", "replyEventId", "", "reply"]) // Existing reply tag
            .build(signer: mockSigner)
        
        // Should have both existing and generated tags
        let eTags = event.tags.filter { $0[0] == "e" }
        let pTags = event.tags.filter { $0[0] == "p" }
        let tTags = event.tags.filter { $0[0] == "t" }
        
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags[0], ["t", "nostr"])
    }
    
    func testEventMentionGeneration() async throws {
        let note = TestEntities.validNote
        let content = "Check out this note: nostr:\(note)"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        // Check that q tag was added
        let qTags = event.tags.filter { $0[0] == "q" }
        XCTAssertEqual(qTags.count, 1)
        XCTAssertEqual(qTags[0].count, 3) // ["q", eventId, relay]
        XCTAssertNotNil(qTags[0][1])
        XCTAssertEqual(qTags[0][2], "") // Empty relay hint
    }
    
    // MARK: - Builder Method Tests
    
    func testManualGenerateContentTags() async throws {
        let builder = NDKEventBuilder()
            .content("Hello #nostr")
            .kind(EventKind.textNote)
        
        // Manually call generateContentTags
        _ = builder.generateContentTags()
        
        let event = try await builder.build(signer: mockSigner, generateContentTags: false)
        
        // Tags should still be present even though auto-generation was disabled
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags[0], ["t", "nostr"])
    }
    
    func testContentNormalization() async throws {
        let npub = TestEntities.validNpub
        let content = "Multiple mentions: @\(npub) and nostr:\(npub)"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        // Both mentions should be normalized to nostr: format
        XCTAssertEqual(event.content, "Multiple mentions: nostr:\(npub) and nostr:\(npub)")
        
        // Should only have one p tag (duplicate removed)
        let pTags = event.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1)
    }
    
    // MARK: - Factory Method Tests
    
    func testTextNoteFactoryWithContentTags() async throws {
        let event = try await NDKEventBuilder
            .textNote("Hello #nostr world!")
            .build(signer: mockSigner)
        
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags[0], ["t", "nostr"])
    }
    
    func testReplyFactoryWithContentTags() async throws {
        let npub = TestEntities.validNpub
        let event = try await NDKEventBuilder
            .reply("Thanks @\(npub) #grateful", to: "eventId123", author: "authorPubkey")
            .build(signer: mockSigner)
        
        // Should have reply tags plus content tags
        let eTags = event.tags.filter { $0[0] == "e" }
        let pTags = event.tags.filter { $0[0] == "p" }
        let tTags = event.tags.filter { $0[0] == "t" }
        
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags[0][3], "reply")
        
        XCTAssertEqual(pTags.count, 2) // One from reply, one from content
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags[0], ["t", "grateful"])
        
        // Content should be normalized
        XCTAssertTrue(event.content.contains("nostr:\(npub)"))
    }
    
    // MARK: - Edge Cases
    
    func testEmptyContent() async throws {
        let event = try await NDKEventBuilder()
            .content("")
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        XCTAssertEqual(event.tags.count, 0)
        XCTAssertEqual(event.content, "")
    }
    
    func testInvalidNostrEntities() async throws {
        let content = "@npubinvalid #nostr nostr:noteinvalid"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        // Only valid hashtag should be processed
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags[0], ["t", "nostr"])
        
        // Invalid entities should remain unchanged
        XCTAssertTrue(event.content.contains("@npubinvalid"))
        XCTAssertTrue(event.content.contains("nostr:noteinvalid"))
    }
    
    func testSpecialCharactersInHashtags() async throws {
        let content = "#valid-tag #also_valid #not!valid #emoji😀"
        
        let event = try await NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .build(signer: mockSigner)
        
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 4) // Captures parts before special chars
        XCTAssertTrue(tTags.contains(["t", "valid-tag"]))
        XCTAssertTrue(tTags.contains(["t", "also_valid"]))
        XCTAssertTrue(tTags.contains(["t", "not"])) // Part before !
        XCTAssertTrue(tTags.contains(["t", "emoji😀"])) // Emoji is included
    }
}