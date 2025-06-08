import XCTest
@testable import NDKSwift

final class TagHelpersTests: XCTestCase {
    
    // MARK: - Safe Array Access Tests
    
    func testSafeArrayAccess() {
        let array = ["a", "b", "c"]
        
        XCTAssertEqual(array[safe: 0], "a")
        XCTAssertEqual(array[safe: 2], "c")
        XCTAssertNil(array[safe: 3])
        XCTAssertNil(array[safe: -1])
    }
    
    // MARK: - Tag Validation Tests
    
    func testTagValidation() {
        // Valid tags
        let validEventTag: Tag = ["e", String(repeating: "a", count: 64)]
        XCTAssertTrue(validEventTag.isValid)
        
        let validPubkeyTag: Tag = ["p", String(repeating: "f", count: 64)]
        XCTAssertTrue(validPubkeyTag.isValid)
        
        let validAddressableTag: Tag = ["a", "30023:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef:identifier"]
        XCTAssertTrue(validAddressableTag.isValid)
        
        let validHashtagTag: Tag = ["t", "nostr"]
        XCTAssertTrue(validHashtagTag.isValid)
        
        let validURLTag: Tag = ["r", "https://example.com"]
        XCTAssertTrue(validURLTag.isValid)
        
        // Invalid tags
        let emptyTag: Tag = []
        XCTAssertFalse(emptyTag.isValid)
        
        let shortEventTag: Tag = ["e", "tooshort"]
        XCTAssertFalse(shortEventTag.isValid)
        
        let invalidHexTag: Tag = ["p", String(repeating: "g", count: 64)] // 'g' is not hex
        XCTAssertFalse(invalidHexTag.isValid)
        
        let malformedAddressableTag: Tag = ["a", "invalid-format"]
        XCTAssertFalse(malformedAddressableTag.isValid)
    }
    
    func testTagProperties() {
        let tag: Tag = ["e", "eventid", "wss://relay.com", "reply"]
        
        XCTAssertEqual(tag.name, "e")
        XCTAssertEqual(tag.value, "eventid")
        XCTAssertEqual(tag.relayHint, "wss://relay.com")
        XCTAssertEqual(tag.marker, "reply")
        
        let shortTag: Tag = ["t", "nostr"]
        XCTAssertEqual(shortTag.name, "t")
        XCTAssertEqual(shortTag.value, "nostr")
        XCTAssertNil(shortTag.relayHint)
        XCTAssertNil(shortTag.marker)
    }
    
    // MARK: - Tag Creation Tests
    
    func testTagCreationHelpers() {
        let event = NDKEvent(
            pubkey: "testpubkey",
            kind: 1,
            tags: [],
            content: "Test"
        )
        let referencedEvent = NDKEvent(
            id: "ref123",
            pubkey: "pubkey123",
            createdAt: 0,
            kind: 1,
            tags: [],
            content: "Referenced",
            sig: "sig123"
        )
        
        // Test reply tag
        event.tagReply(to: referencedEvent, relay: "wss://relay.com")
        XCTAssertTrue(event.tags.contains { $0 == ["e", "ref123", "wss://relay.com", "reply"] })
        
        // Test root tag
        event.tagRoot(referencedEvent)
        XCTAssertTrue(event.tags.contains { $0 == ["e", "ref123", "", "root"] })
        
        // Test mention tag
        event.tagMention(referencedEvent, relay: "wss://relay2.com")
        XCTAssertTrue(event.tags.contains { $0 == ["e", "ref123", "wss://relay2.com", "mention"] })
        
        // Test hashtag
        event.tagHashtag("#nostr")
        XCTAssertTrue(event.tags.contains { $0 == ["t", "nostr"] })
        
        event.tagHashtag("Bitcoin") // Without #
        XCTAssertTrue(event.tags.contains { $0 == ["t", "bitcoin"] })
        
        // Test URL tag
        event.tagURL("https://nostr.com", petname: "Nostr Website")
        XCTAssertTrue(event.tags.contains { $0 == ["r", "https://nostr.com", "Nostr Website"] })
        
        // Test subject tag
        event.tagSubject("Test Subject")
        XCTAssertTrue(event.tags.contains { $0 == ["subject", "Test Subject"] })
        
        // Test image tag
        event.tagImage("https://example.com/image.jpg", width: 800, height: 600)
        XCTAssertTrue(event.tags.contains { $0 == ["image", "https://example.com/image.jpg", "800x600"] })
    }
    
    func testAddressableEventTag() {
        let event = NDKEvent(
            pubkey: "testpubkey",
            kind: 1,
            tags: [],
            content: "Test"
        )
        let addressableEvent = NDKEvent(
            id: "addr123",
            pubkey: String(repeating: "a", count: 64),
            createdAt: 0,
            kind: 30023, // Long-form content
            tags: [["d", "my-article"]],
            content: "Article content",
            sig: "sig123"
        )
        
        event.tagAddressableEvent(addressableEvent, relay: "wss://relay.com")
        let expectedTag = ["a", "30023:\(String(repeating: "a", count: 64)):my-article", "wss://relay.com"]
        XCTAssertTrue(event.tags.contains { $0 == expectedTag })
    }
    
    // MARK: - Tag Query Tests
    
    func testTagQueries() {
        let event = NDKEvent(
            content: "Test",
            tags: [
                ["e", "event1", "wss://relay1.com", "root"],
                ["e", "event2", "wss://relay2.com", "reply"],
                ["e", "event3", "", "mention"],
                ["p", "pubkey1"],
                ["p", "pubkey2", "wss://relay3.com"],
                ["t", "nostr"],
                ["t", "bitcoin"],
                ["r", "https://example.com", "Example"],
                ["r", "https://nostr.com"],
                ["subject", "Test Subject"]
            ]
        )
        
        // Test tagValues
        let eventIds = event.tagValues("e")
        XCTAssertEqual(eventIds, ["event1", "event2", "event3"])
        
        let relays = event.tagValues("e", at: 2)
        XCTAssertEqual(relays, ["wss://relay1.com", "wss://relay2.com", ""])
        
        // Test tags with marker
        let rootTags = event.tags(withName: "e", marker: "root")
        XCTAssertEqual(rootTags.count, 1)
        XCTAssertEqual(rootTags[0][1], "event1")
        
        // Test specific queries
        XCTAssertEqual(event.rootEventId, "event1")
        XCTAssertEqual(event.replyToEventId, "event2")
        XCTAssertEqual(event.mentionedEventIds, ["event3"])
        XCTAssertEqual(event.mentionedPubkeys, ["pubkey1", "pubkey2"])
        XCTAssertEqual(event.hashtags, ["nostr", "bitcoin"])
        XCTAssertEqual(event.subject, "Test Subject")
        XCTAssertTrue(event.isReplyEvent)
        XCTAssertFalse(event.isRootPost)
        
        // Test URLs
        let urls = event.urls
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].url, "https://example.com")
        XCTAssertEqual(urls[0].petname, "Example")
        XCTAssertEqual(urls[1].url, "https://nostr.com")
        XCTAssertNil(urls[1].petname)
    }
    
    func testThreadDetection() {
        // Root post
        let rootPost = NDKEvent(content: "Root", tags: [])
        XCTAssertTrue(rootPost.isRootPost)
        XCTAssertFalse(rootPost.isReplyEvent)
        XCTAssertNil(rootPost.rootEventId)
        XCTAssertNil(rootPost.replyToEventId)
        
        // Reply with markers
        let reply = NDKEvent(
            content: "Reply",
            tags: [
                ["e", "root123", "", "root"],
                ["e", "reply123", "", "reply"]
            ]
        )
        XCTAssertFalse(reply.isRootPost)
        XCTAssertTrue(reply.isReplyEvent)
        XCTAssertEqual(reply.rootEventId, "root123")
        XCTAssertEqual(reply.replyToEventId, "reply123")
        
        // Legacy reply (no markers)
        let legacyReply = NDKEvent(
            content: "Legacy Reply",
            tags: [
                ["e", "event123"]
            ]
        )
        XCTAssertTrue(legacyReply.isReplyEvent)
        XCTAssertEqual(legacyReply.rootEventId, "event123")
    }
    
    // MARK: - Thread Building Tests
    
    func testCreateReply() {
        let ndk = NDK(relayPool: MockRelayPool(), signer: nil)
        
        let originalEvent = NDKEvent(
            id: "original123",
            pubkey: "author123",
            createdAt: 0,
            kind: 1,
            tags: [["t", "test"]],
            content: "Original post",
            sig: "sig123"
        )
        originalEvent.ndk = ndk
        
        let reply = originalEvent.createReply(content: "This is a reply")
        
        // Check basic properties
        XCTAssertEqual(reply.content, "This is a reply")
        XCTAssertEqual(reply.kind, 1)
        XCTAssertEqual(reply.ndk, ndk)
        
        // Check tags
        let eTags = reply.tags(withName: "e")
        XCTAssertEqual(eTags.count, 2) // root and reply
        
        // Should have reply tag
        XCTAssertTrue(reply.tags.contains { tag in
            tag == ["e", "original123", "", "reply"]
        })
        
        // Should have root tag (pointing to original)
        XCTAssertTrue(reply.tags.contains { tag in
            tag == ["e", "original123", "", "root"]
        })
        
        // Should tag the author
        XCTAssertTrue(reply.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == "author123"
        })
    }
    
    func testCreateReplyToReply() {
        let threadRoot = NDKEvent(
            id: "root123",
            pubkey: "rootauthor",
            createdAt: 0,
            kind: 1,
            tags: [],
            content: "Root",
            sig: "sig1"
        )
        
        let firstReply = NDKEvent(
            id: "reply123",
            pubkey: "replyauthor",
            createdAt: 1,
            kind: 1,
            tags: [
                ["e", "root123", "", "root"],
                ["e", "root123", "", "reply"],
                ["p", "rootauthor"]
            ],
            content: "First reply",
            sig: "sig2"
        )
        
        let secondReply = firstReply.createReply(content: "Second reply")
        
        // Should maintain root reference
        XCTAssertTrue(secondReply.tags.contains { tag in
            tag == ["e", "root123", "", "root"]
        })
        
        // Should reply to first reply
        XCTAssertTrue(secondReply.tags.contains { tag in
            tag == ["e", "reply123", "", "reply"]
        })
        
        // Should have both p tags
        let pTags = secondReply.tags(withName: "p")
        XCTAssertTrue(pTags.contains { $0[safe: 1] == "replyauthor" })
        XCTAssertTrue(pTags.contains { $0[safe: 1] == "rootauthor" })
    }
    
    // MARK: - Batch Operations Tests
    
    func testBatchTagOperations() {
        let event = NDKEvent(
            content: "Test",
            tags: [
                ["e", "event1"],
                ["p", "pubkey1"],
                ["e", "event2"],
                ["t", "nostr"],
                ["p", "pubkey2"]
            ]
        )
        
        // Test removeTags
        event.removeTags(withName: "e")
        XCTAssertEqual(event.tags(withName: "e").count, 0)
        XCTAssertEqual(event.tags(withName: "p").count, 2)
        XCTAssertEqual(event.tags(withName: "t").count, 1)
        
        // Test replaceTags
        let newPTags: [Tag] = [["p", "newpubkey1"], ["p", "newpubkey2"]]
        event.replaceTags(withName: "p", with: newPTags)
        let pTags = event.tags(withName: "p")
        XCTAssertEqual(pTags.count, 2)
        XCTAssertEqual(pTags[0][1], "newpubkey1")
        XCTAssertEqual(pTags[1][1], "newpubkey2")
        
        // Test addTags
        let additionalTags: [Tag] = [
            ["r", "https://example.com"],
            ["t", "bitcoin"]
        ]
        event.addTags(additionalTags)
        XCTAssertEqual(event.tags(withName: "r").count, 1)
        XCTAssertEqual(event.tags(withName: "t").count, 2)
    }
    
    func testTagDeduplication() {
        let event = NDKEvent(
            content: "Test",
            tags: [
                ["e", "event1", "", "root"],
                ["e", "event1", "", "root"], // Duplicate
                ["p", "pubkey1"],
                ["p", "pubkey1"], // Duplicate
                ["t", "nostr"],
                ["t", "bitcoin"],
                ["t", "nostr"] // Duplicate
            ]
        )
        
        event.deduplicateTags()
        
        XCTAssertEqual(event.tags.count, 4)
        XCTAssertEqual(event.tags(withName: "e").count, 1)
        XCTAssertEqual(event.tags(withName: "p").count, 1)
        XCTAssertEqual(event.tags(withName: "t").count, 2)
    }
    
    func testRemoveInvalidTags() {
        let event = NDKEvent(
            content: "Test",
            tags: [
                ["e", String(repeating: "a", count: 64)], // Valid
                ["e", "tooshort"], // Invalid
                ["p", String(repeating: "f", count: 64)], // Valid
                ["p", String(repeating: "g", count: 64)], // Invalid (non-hex)
                [], // Invalid (empty)
                ["t", "nostr"] // Valid
            ]
        )
        
        event.removeInvalidTags()
        
        XCTAssertEqual(event.tags.count, 3)
        XCTAssertTrue(event.tags.allSatisfy { $0.isValid })
    }
    
    // MARK: - Tag Builder Tests
    
    func testTagBuilder() {
        var builder = TagBuilder()
        
        let tags = builder
            .event("event123", relay: "wss://relay.com", marker: "root")
            .event("event456", marker: "reply")
            .pubkey("pubkey123", relay: "wss://relay2.com")
            .pubkey("pubkey456", petname: "Alice")
            .hashtag("#nostr")
            .hashtag("bitcoin")
            .url("https://example.com", petname: "Example")
            .custom(["custom", "value"])
            .build()
        
        XCTAssertEqual(tags.count, 8)
        
        // Verify specific tags
        XCTAssertTrue(tags.contains { $0 == ["e", "event123", "wss://relay.com", "root"] })
        XCTAssertTrue(tags.contains { $0 == ["e", "event456", "", "reply"] })
        XCTAssertTrue(tags.contains { $0 == ["p", "pubkey123", "wss://relay2.com"] })
        XCTAssertTrue(tags.contains { $0 == ["p", "pubkey456", "", "Alice"] })
        XCTAssertTrue(tags.contains { $0 == ["t", "nostr"] })
        XCTAssertTrue(tags.contains { $0 == ["t", "bitcoin"] })
        XCTAssertTrue(tags.contains { $0 == ["r", "https://example.com", "Example"] })
        XCTAssertTrue(tags.contains { $0 == ["custom", "value"] })
    }
    
    // MARK: - Filter Tag Helpers Tests
    
    func testFilterTagHelpers() {
        var filter = NDKFilter()
        
        // Test hashtag filter
        filter.addHashtagFilter("Nostr", "Bitcoin", "Lightning")
        XCTAssertEqual(filter.tagFilters["#t"], ["nostr", "bitcoin", "lightning"])
        
        // Test URL filter
        filter.addURLFilter("https://nostr.com", "https://bitcoin.org")
        XCTAssertEqual(filter.tagFilters["#r"], ["https://nostr.com", "https://bitcoin.org"])
        
        // Test hasTagFilter
        XCTAssertTrue(filter.hasTagFilter("t"))
        XCTAssertTrue(filter.hasTagFilter("r"))
        XCTAssertFalse(filter.hasTagFilter("a"))
    }
    
    // MARK: - Performance Tests
    
    func testTagOperationPerformance() {
        let event = NDKEvent(
            pubkey: "testpubkey",
            kind: 1,
            tags: [],
            content: "Performance test"
        )
        
        // Add many tags
        for i in 0..<1000 {
            event.addTag(["t", "tag\(i)"])
            if i % 2 == 0 {
                event.addTag(["p", String(repeating: "a", count: 64)])
            }
        }
        
        measure {
            // Test tag queries
            _ = event.hashtags
            _ = event.mentionedPubkeys
            _ = event.tags(withName: "t")
            
            // Test deduplication
            let copy = event
            copy.deduplicateTags()
        }
    }
}

// MARK: - Mock Objects

class MockRelayPool: NDKRelayPool {
    init() {
        super.init(ndk: nil)
    }
}