import XCTest
@testable import NDKSwift

final class NDKEventBuilderTests: XCTestCase {
    private var ndk: NDK!
    private var signer: NDKPrivateKeySigner!
    private var builder: NDKEventBuilder!
    
    override func setUp() async throws {
        try await super.setUp()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDKTestFactory.createNDK(signer: signer)
        builder = NDKEventBuilder(ndk: ndk)
    }
    
    func testPubkeyAssignment() async throws {
        let pubkey = try await signer.pubkey
        let event = try await builder
            .pubkey(pubkey)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.pubkey, pubkey)
    }
    
    func testCreatedAtCustomTimestamp() async throws {
        let timestamp: Timestamp = 1609459200 // 2021-01-01 00:00:00 UTC
        let event = try await builder
            .createdAt(timestamp)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.createdAt, timestamp)
    }
    
    func testTagAddition() async throws {
        let event = try await builder
            .tag(["p", "pubkey123"])
            .tag(["e", "eventid456"])
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.tags[0], ["p", "pubkey123"])
        XCTAssertEqual(event.tags[1], ["e", "eventid456"])
    }
    
    func testTagsArrayAddition() async throws {
        let tags = [
            ["p", "pubkey1"],
            ["p", "pubkey2"],
            ["t", "nostr"]
        ]
        
        let event = try await builder
            .tags(tags)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags, tags)
    }
    
    func testSetTagsReplacement() async throws {
        let event = try await builder
            .tag(["p", "old"])
            .setTags([["p", "new"], ["e", "event"]])
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.tags[0], ["p", "new"])
        XCTAssertEqual(event.tags[1], ["e", "event"])
    }
    
    func testTagUserBasic() async throws {
        let userPubkey = "pubkey123"
        let event = try await builder
            .tagUser(userPubkey)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["p", userPubkey])
    }
    
    func testTagUserWithMarkerAndRelay() async throws {
        let userPubkey = "pubkey123"
        let marker = "reply"
        let relay = "wss://relay.example.com"
        
        let event = try await builder
            .tagUser(userPubkey, marker: marker, relay: relay)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["p", userPubkey, relay, marker])
    }
    
    func testTagEventRegular() async throws {
        let eventId = "eventid123"
        let eventPubkey = "pubkey456"
        let relay = "wss://relay.example.com"
        let marker = "root"
        
        let taggedEvent = NDKEvent(
            id: eventId,
            pubkey: eventPubkey,
            createdAt: 1609459200,
            kind: 1,
            tags: [],
            content: "original",
            sig: "sig123"
        )
        
        let event = try await builder
            .tagEvent(taggedEvent, marker: marker, preferredRelay: relay)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["e", eventId, relay, marker, eventPubkey])
    }
    
    func testTagEventReplaceableKind() async throws {
        let replaceableEvent = NDKEvent(
            id: "eventid123",
            pubkey: "pubkey456",
            createdAt: 1609459200,
            kind: 30000,
            tags: [["d", "identifier"]],
            content: "replaceable",
            sig: "sig123"
        )
        
        let event = try await builder
            .tagEvent(replaceableEvent)
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0][0], "a")
        XCTAssertTrue(event.tags[0][1].hasPrefix("30000:pubkey456:"))
    }
    
    func testQuoteEvent() async throws {
        let quotedEvent = NDKEvent(
            id: "quotedid123",
            pubkey: "quotedpubkey",
            createdAt: 1609459200,
            kind: 1,
            tags: [],
            content: "quoted content",
            sig: "sig123"
        )
        
        let event = try await builder
            .quoteEvent(quotedEvent, preferredRelay: "wss://relay.example.com")
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["q", "quotedid123", "wss://relay.example.com", "quotedpubkey"])
    }
    
    func testTagHashtag() async throws {
        let event = try await builder
            .tagHashtag("nostr")
            .tagHashtag("bitcoin")
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.tags[0], ["t", "nostr"])
        XCTAssertEqual(event.tags[1], ["t", "bitcoin"])
    }
    
    func testDTag() async throws {
        let event = try await builder
            .dTag("unique-identifier")
            .content("test")
            .kind(30000)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["d", "unique-identifier"])
    }
    
    func testClientTag() async throws {
        let event = try await builder
            .clientTag(name: "NDKSwift")
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["client", "NDKSwift"])
    }
    
    func testContentSetting() async throws {
        let content = "Hello, Nostr!"
        let event = try await builder
            .content(content)
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.content, content)
    }
    
    func testContentWithImetaExtraction() async throws {
        let content = "Check out this image: https://example.com/image.jpg"
        let event = try await builder
            .content(content, extractImeta: true)
            .kind(1)
            .build(signer: signer)
        
        // Verify content is unchanged
        XCTAssertEqual(event.content, content)
        
        // Check if imeta tag was added
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1, "Should have extracted one imeta tag")
        if let imetaTag = imetaTags.first {
            XCTAssertTrue(imetaTag.contains("url https://example.com/image.jpg"), "imeta tag should contain the URL")
        }
    }
    
    // TODO: Implement addMedia method in NDKEventBuilder
    /*
    func testAddMediaFromBlossomBlob() async throws {
        let blob = BlossomBlob(
            sha256: "abc123def456",
            url: "https://blossom.example.com/abc123",
            size: 1024,
            type: "image/jpeg",
            uploaded: Date(timeIntervalSince1970: 1609459200),
            blurhash: "L6PZfSi_.AyE",
            dimensions: (width: 800, height: 600)
        )
        
        let event = try await builder
            .addMedia(from: blob, alt: "Test image")
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)
        
        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url=https://blossom.example.com/abc123"))
        XCTAssertTrue(imetaTag.contains("x=abc123def456"))
        XCTAssertTrue(imetaTag.contains("size=1024"))
        XCTAssertTrue(imetaTag.contains("m=image/jpeg"))
        XCTAssertTrue(imetaTag.contains("blurhash=L6PZfSi_.AyE"))
        XCTAssertTrue(imetaTag.contains("dim=800x600"))
        XCTAssertTrue(imetaTag.contains("alt=Test image"))
    }
    */
    
    // TODO: Implement addMedia method in NDKEventBuilder
    /*
    func testAddMediaWithCustomParameters() async throws {
        let event = try await builder
            .addMedia(
                url: "https://example.com/video.mp4",
                mimeType: "video/mp4",
                blurhash: "L6PZfSi_.AyE",
                dimensions: (width: 1920, height: 1080),
                alt: "Test video",
                sha256: "videohash123",
                size: "5242880",
                fallback: ["https://backup.com/video.mp4"]
            )
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)
        
        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url=https://example.com/video.mp4"))
        XCTAssertTrue(imetaTag.contains("m=video/mp4"))
        XCTAssertTrue(imetaTag.contains("blurhash=L6PZfSi_.AyE"))
        XCTAssertTrue(imetaTag.contains("dim=1920x1080"))
        XCTAssertTrue(imetaTag.contains("alt=Test video"))
        XCTAssertTrue(imetaTag.contains("x=videohash123"))
        XCTAssertTrue(imetaTag.contains("size=5242880"))
        XCTAssertTrue(imetaTag.contains("fallback=https://backup.com/video.mp4"))
    }
    
    func testBuildEventIDCalculation() async throws {
        let event = try await builder
            .content("test")
            .kind(1)
            .build(signer: signer)
        
        // Verify event ID is not empty
        XCTAssertFalse(event.id.isEmpty)
        
        // Verify event ID is lowercase hex
        XCTAssertEqual(event.id, event.id.lowercased())
        XCTAssertTrue(event.id.allSatisfy { $0.isHexDigit })
        
        // Verify signature is not empty
        XCTAssertFalse(event.sig.isEmpty)
    }
    
    func testBuildWithEmptyContent() async throws {
        let event = try await builder
            .content("")
            .kind(1)
            .build(signer: signer)
        
        XCTAssertEqual(event.content, "")
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertFalse(event.sig.isEmpty)
    }
    
    func testBuildWithComplexTags() async throws {
        let event = try await builder
            .tag(["p", "pubkey1", "wss://relay1.com", "mention"])
            .tag(["e", "eventid1", "wss://relay2.com", "root"])
            .tag(["e", "eventid2", "wss://relay3.com", "reply"])
            .tag(["t", "nostr"])
            .tag(["client", "NDKSwift"])
            .tag(["d", "identifier"])
            .content("Complex event")
            .kind(30000)
            .build(signer: signer)
        
        XCTAssertEqual(event.tags.count, 6)
        XCTAssertEqual(event.kind, 30000)
        XCTAssertTrue(event.tags.contains(["d", "identifier"]))
    }
    */
}