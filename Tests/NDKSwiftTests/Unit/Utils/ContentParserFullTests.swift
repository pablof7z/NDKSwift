@testable import NDKSwiftCore
import XCTest

final class ContentParserFullTests: XCTestCase {
    // MARK: - Basic Entity Extraction Tests

    func testParseTextOnly() {
        // Given
        let content = "This is just plain text with no entities"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertEqual(result.entities.count, 1)
        XCTAssertEqual(result.entities.first, .text(content))
        XCTAssertEqual(result.normalizedContent, content)
    }

    func testParseHashtags() {
        // Given
        let content = "Check out #bitcoin and #nostr today!"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertEqual(result.entities.count, 5)
        XCTAssertEqual(result.entities[0], .text("Check out "))
        XCTAssertEqual(result.entities[1], .hashtag("bitcoin"))
        XCTAssertEqual(result.entities[2], .text(" and "))
        XCTAssertEqual(result.entities[3], .hashtag("nostr"))
        XCTAssertEqual(result.entities[4], .text(" today!"))
    }

    func testParseHashtagsWithSpecialChars() {
        // Given
        let content = "#hello_world #test-123 #nostr2024"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let hashtags = result.entities.hashtags
        XCTAssertEqual(hashtags, ["hello_world", "test-123", "nostr2024"])
    }

    func testParseHashtagsIgnoreInvalid() {
        // Given
        let content = "#valid #[invalid] #!bad #@wrong"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let hashtags = result.entities.hashtags
        XCTAssertEqual(hashtags, ["valid"])
    }

    func testParseURLs() {
        // Given
        let content = "Visit https://nostr.com and http://example.org for more info"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let urls = result.entities.urls
        XCTAssertEqual(urls, ["https://nostr.com", "http://example.org"])
    }

    func testParseNpub() {
        // Given
        let npub = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let content = "Follow @\(npub) for updates"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.npub(npub)))
        XCTAssertEqual(result.normalizedContent, "Follow nostr:\(npub) for updates")
    }

    func testParseNostrPrefixedEntities() {
        // Given
        let npub = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let note = "note1xyz123abc456def789ghi012jkl345mno678pqr901stu234vwx567yz"
        let content = "Check out nostr:\(npub) and nostr:\(note)"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.npub(npub)))
        XCTAssertTrue(result.entities.contains(.note(note)))
        XCTAssertEqual(result.normalizedContent, content) // Already normalized
    }

    func testParseNprofile() {
        // Given
        let nprofile = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let content = "Contact @\(nprofile)"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.nprofile(nprofile)))
        XCTAssertEqual(result.normalizedContent, "Contact nostr:\(nprofile)")
    }

    func testParseNevent() {
        // Given
        let nevent = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let content = "See this event: @\(nevent)"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.nevent(nevent)))
        XCTAssertEqual(result.normalizedContent, "See this event: nostr:\(nevent)")
    }

    func testParseNaddr() {
        // Given
        let naddr = "naddr1qqykjurnw4ksz9thwden5te0wfjkccte9ehx7um5wghx7un8qgs2d90kkcq3nk2jry62dyf50k0h36rhpdtd594my40w9pkal876jxgrqsqqqa28pccpzu"
        let content = "Read more at @\(naddr)"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.naddr(naddr)))
        XCTAssertEqual(result.normalizedContent, "Read more at nostr:\(naddr)")
    }

    // MARK: - Mixed Content Tests

    func testParseMixedContent() {
        // Given
        let npub = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let content = "Hey @\(npub), check out #bitcoin at https://bitcoin.org"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertEqual(result.entities.count, 6)
        XCTAssertTrue(result.entities.contains(.text("Hey ")))
        XCTAssertTrue(result.entities.contains(.npub(npub)))
        XCTAssertTrue(result.entities.contains(.text(", check out ")))
        XCTAssertTrue(result.entities.contains(.hashtag("bitcoin")))
        XCTAssertTrue(result.entities.contains(.text(" at ")))
        XCTAssertTrue(result.entities.containsURL("https://bitcoin.org"))
    }

    func testParseMultipleHashtags() {
        // Given
        let content = "#bitcoin #lightning #nostr #decentralized"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let hashtags = result.entities.hashtags
        XCTAssertEqual(hashtags, ["bitcoin", "lightning", "nostr", "decentralized"])
    }

    // MARK: - Tag Reference Tests (#[index])

    func testParseUserMentionReferences() {
        // Given
        let pubkey1 = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let pubkey2 = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let tags = [
            ["p", pubkey1],
            ["p", pubkey2],
            ["e", "someeventid"],
        ]
        let content = "Hey #[0] and #[1], what do you think?"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: nil)

        // Then
        XCTAssertTrue(result.entities.contains(.userMention(pubkey: pubkey1, npub: try! String.toNpub(pubkey1))))
        XCTAssertTrue(result.entities.contains(.userMention(pubkey: pubkey2, npub: try! String.toNpub(pubkey2))))
        XCTAssertTrue(result.normalizedContent.contains("@npub"))
    }

    func testParseEventMentionReferences() {
        // Given
        let eventId = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let tags = [
            ["e", eventId],
            ["p", "somepubkey"],
        ]
        let content = "In reply to #[0]"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: nil)

        // Then
        XCTAssertTrue(result.entities.contains(.eventMention(eventId)))
        XCTAssertTrue(result.normalizedContent.contains("note:32e18276..."))
    }

    func testParseMixedReferences() {
        // Given
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let eventId = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let tags = [
            ["p", pubkey],
            ["e", eventId],
        ]
        let content = "Hey #[0], check out #[1] #bitcoin"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: nil)

        // Then
        XCTAssertEqual(result.entities.count, 5) // user mention, text, event mention, text, hashtag
        XCTAssertTrue(result.entities.contains(.userMention(pubkey: pubkey, npub: try! String.toNpub(pubkey))))
        XCTAssertTrue(result.entities.contains(.eventMention(eventId)))
        XCTAssertTrue(result.entities.contains(.hashtag("bitcoin")))
    }

    func testParseInvalidReferences() {
        // Given
        let tags = [["p", "pubkey1"]]
        let content = "This references #[5] which doesn't exist"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: nil)

        // Then
        // Invalid reference should remain as text
        XCTAssertEqual(result.normalizedContent, content)
        XCTAssertFalse(result.entities.containsUserMention() || result.entities.containsEventMention())
    }

    // MARK: - Current User Mention Detection Tests

    func testDetectCurrentUserMentionByPubkey() {
        // Given
        let currentUserPubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let currentUser = NDKUser(pubkey: currentUserPubkey)
        let tags = [["p", currentUserPubkey]]
        let content = "Hey #[0], this is for you!"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: currentUser)

        // Then
        XCTAssertTrue(result.parsedContent.isMentioningCurrentUser)
    }

    func testDetectCurrentUserMentionByNpub() {
        // Given
        let currentUserPubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        let currentUser = NDKUser(pubkey: currentUserPubkey)
        let npub = try! String.toNpub(currentUserPubkey)
        let content = "Hey @\(npub), this is for you!"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: [], currentUser: currentUser)

        // Then
        XCTAssertTrue(result.parsedContent.isMentioningCurrentUser)
    }

    func testNoCurrentUserMention() {
        // Given
        let currentUser = NDKUser(pubkey: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")
        let otherPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let tags = [["p", otherPubkey]]
        let content = "Hey #[0], how are you?"

        // When
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: currentUser)

        // Then
        XCTAssertFalse(result.parsedContent.isMentioningCurrentUser)
    }

    // MARK: - Edge Cases

    func testParseEmptyContent() {
        // Given
        let content = ""

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.isEmpty)
        XCTAssertEqual(result.normalizedContent, "")
    }

    func testParseContentWithNewlines() {
        // Given
        let content = "Line 1\n#bitcoin\nLine 3"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.text("Line 1\n")))
        XCTAssertTrue(result.entities.contains(.hashtag("bitcoin")))
        XCTAssertTrue(result.entities.contains(.text("\nLine 3")))
    }

    func testParseOverlappingPatterns() {
        // Given
        // URL that contains what looks like a hashtag
        let content = "Check https://example.com/#section and #real"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let urls = result.entities.urls
        let hashtags = result.entities.hashtags

        XCTAssertEqual(urls, ["https://example.com/#section"])
        XCTAssertEqual(hashtags, ["real"]) // Only the standalone hashtag
    }

    func testParseConsecutiveEntities() {
        // Given
        let npub1 = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let npub2 = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let content = "@\(npub1)@\(npub2)#bitcoin#lightning"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        XCTAssertTrue(result.entities.contains(.npub(npub1)))
        XCTAssertTrue(result.entities.contains(.npub(npub2)))
        XCTAssertTrue(result.entities.contains(.hashtag("bitcoin")))
        XCTAssertTrue(result.entities.contains(.hashtag("lightning")))
    }

    func testParseInvalidURLs() {
        // Given
        let content = "Not a URL: http:// or https://"

        // When
        let result = ContentParser.parseContent(content)

        // Then
        let hasURL = result.entities.containsURL()
        XCTAssertFalse(hasURL)
    }

    // MARK: - Performance Test

    func testParsePerformanceWithComplexContent() {
        // Given
        let npub = "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
        let complexContent = """
        Hey @\(npub), check out these resources:

        #bitcoin whitepaper: https://bitcoin.org/bitcoin.pdf
        #lightning network: https://lightning.network
        #nostr protocol: https://github.com/nostr-protocol/nostr

        Follow @\(npub) and @\(npub) for more updates!

        #decentralized #privacy #freedom #opensource #protocol #development #community

        More links:
        - https://example1.com
        - https://example2.com
        - https://example3.com
        """

        // When/Then
        measure {
            _ = ContentParser.parseContent(complexContent)
        }
    }
}
