@testable import NDKSwiftCore
import XCTest

final class NDKEventBuilderComprehensiveTests: NDKUnitTestCase {
    private var builder: NDKEventBuilder!

    override func setUp() async throws {
        try await super.setUp()
        builder = NDKEventBuilder(ndk: ndk)
    }

    // MARK: - Client Tag Configuration Tests

    func testClientTagConfiguration() async throws {
        // Create NDK with client tag config
        let clientConfig = NDKClientTagConfig(
            name: "TestClient",
            address: "31990:pubkey123:test-client",
            relay: "wss://relay.test",
            autoTag: true,
            excludedKinds: [EventKind.metadata]
        )

        let customNDK = NDK(
            relayURLs: ["wss://relay.test"],
            signer: signer,
            cache: cache
            // Updated setup without clientTagConfig
        )

        let customBuilder = NDKEventBuilder(ndk: customNDK)

        // Build event that should get auto-tagged
        let event = try await customBuilder
            .kind(EventKind.textNote)
            .content("Test message")
            .build(signer: signer)

        // Verify client tag was automatically added
        let clientTags = event.tags.filter { $0.first == "client" }
        XCTAssertEqual(clientTags.count, 1)
        XCTAssertEqual(clientTags[0], ["client", "TestClient", "31990:pubkey123:test-client", "wss://relay.test"])

        // Build event with excluded kind
        let metadataEvent = try await customBuilder
            .kind(EventKind.metadata)
            .content("{}")
            .build(signer: signer)

        // Verify client tag was NOT added
        let metadataClientTags = metadataEvent.tags.filter { $0.first == "client" }
        XCTAssertEqual(metadataClientTags.count, 0)
    }

    // MARK: - Reply Builder Tests

    func testReplyToKind1Event() async throws {
        let parentEvent = TestFixtures.Events.textNote

        let reply = try await NDKEventBuilder.reply(to: parentEvent, ndk: ndk)
            .content("This is a reply")
            .build(signer: signer)

        // Should be kind 1 for kind 1 replies
        XCTAssertEqual(reply.kind, EventKind.textNote)

        // Should have e and p tags
        let eTags = reply.tags.filter { $0.first == "e" }
        let pTags = reply.tags.filter { $0.first == "p" }

        XCTAssertGreaterThan(eTags.count, 0)
        XCTAssertGreaterThan(pTags.count, 0)

        // Should reference the parent event
        XCTAssertTrue(eTags.contains { $0.value == parentEvent.id })
        XCTAssertTrue(pTags.contains { $0.value == parentEvent.pubkey })
    }

    func testReplyToNonKind1Event() async throws {
        let articleEvent = NDKEvent(
            id: "article123",
            pubkey: "author123",
            createdAt: Timestamp.now,
            kind: EventKind.genericReply,
            tags: [["d", "my-article"]],
            content: "Article content",
            sig: "sig123"
        )

        let comment = try await NDKEventBuilder.reply(to: articleEvent, ndk: ndk)
            .content("Great article!")
            .build(signer: signer)

        // Should be kind 1111 for non-kind-1 replies
        XCTAssertEqual(comment.kind, EventKind.genericReply)

        // Should have uppercase tags for root
        let uppercaseTags = comment.tags.filter { ["A", "K", "P"].contains($0.first) }
        XCTAssertGreaterThan(uppercaseTags.count, 0)

        // Should have lowercase tags for direct parent
        let lowercaseTags = comment.tags.filter { ["a", "k", "p"].contains($0.first) }
        XCTAssertGreaterThan(lowercaseTags.count, 0)
    }

    func testReplyToComment() async throws {
        // Create a comment (which has uppercase tags)
        let comment = NDKEvent(
            id: "comment123",
            pubkey: "commenter123",
            createdAt: Timestamp.now,
            kind: EventKind.genericReply,
            tags: [
                ["A", "30023:author123:article"],
                ["K", "30023"],
                ["P", "author123"],
                ["a", "30023:author123:article"],
                ["k", "30023"],
                ["p", "author123"],
            ],
            content: "First comment",
            sig: "sig123"
        )

        let reply = try await NDKEventBuilder.reply(to: comment, ndk: ndk)
            .content("Reply to comment")
            .build(signer: signer)

        // Should propagate uppercase tags from parent comment
        let uppercaseTags = reply.tags.filter { ["A", "K", "P"].contains($0.first) }
        XCTAssertEqual(uppercaseTags.count, 3)

        // Should add lowercase tags for the direct parent
        let aTags = reply.tags.filter { $0.first == "a" }
        XCTAssertTrue(aTags.contains { tag in
            tag.value?.hasPrefix("\(comment.kind):\(comment.pubkey):") ?? false
        })
    }

    // MARK: - Tag Builder Method Tests

    func testTagUserWithRelayHintFromOutbox() async throws {
        // Mock outbox data
        await ndk.outbox.track(
            pubkey: "user123",
            readRelays: ["wss://user.relay"],
            writeRelays: [],
            source: .nip65
        )

        let event = try await builder
            .tagUser("user123", marker: "mention")
            .content("Mentioning someone")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let pTags = event.tags.filter { $0.first == "p" && $0.value == "user123" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags[0][2], "wss://user.relay") // Relay hint from outbox
        XCTAssertEqual(pTags[0][3], "mention") // Marker
    }

    func testTagAddressableEvent() async throws {
        let replaceableEvent = NDKEvent(
            id: "event123",
            pubkey: "author123",
            createdAt: Timestamp.now,
            kind: 30000,
            tags: [["d", "identifier"]],
            content: "Replaceable content",
            sig: "sig123"
        )

        let event = try await builder
            .tagAddressableEvent(replaceableEvent, preferredRelay: "wss://preferred.relay")
            .content("Referencing replaceable event")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let aTags = event.tags.filter { $0.first == "a" }
        XCTAssertEqual(aTags.count, 1)
        XCTAssertEqual(aTags[0][1], "30000:author123:identifier")
        XCTAssertEqual(aTags[0][2], "wss://preferred.relay")
    }

    func testQuoteEventWithRelayFromTracker() async throws {
        // Set up event tracker with relay info
        // Mock tracking of event with relay
        // Assuming this should mock relay tracking

        let quotedEvent = NDKEvent(
            id: "quoted123",
            pubkey: "author123",
            createdAt: Timestamp.now,
            kind: EventKind.textNote,
            tags: [],
            content: "Original content",
            sig: "sig123"
        )

        let event = try await builder
            .quoteEvent(quotedEvent)
            .content("Quoting: nostr:nevent1...")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let qTags = event.tags.filter { $0.first == "q" }
        XCTAssertEqual(qTags.count, 1)
        XCTAssertEqual(qTags[0], ["q", "quoted123", "wss://origin.relay", "author123"])
    }

    func testImetaTagCreation() async throws {
        let event = try await builder
            .content("Check out this image")
            .imetaTag(url: "https://example.com/image.jpg") { imeta in
                imeta.blurhash = "L6PZfSi_.AyE"
                imeta.dim = "800x600"
                imeta.m = "image/jpeg"
                imeta.size = "102400"
                imeta.alt = "Test image"
            }
            .kind(EventKind.textNote)
            .build(signer: signer)

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://example.com/image.jpg"))
        XCTAssertTrue(imetaTag.contains("blurhash L6PZfSi_.AyE"))
        XCTAssertTrue(imetaTag.contains("dim 800x600"))
        XCTAssertTrue(imetaTag.contains("m image/jpeg"))
        XCTAssertTrue(imetaTag.contains("size 102400"))
        XCTAssertTrue(imetaTag.contains("alt Test image"))
    }

    func testImetaTagFromBlossomBlob() async throws {
        let blob = BlossomBlob(
            sha256: "abc123def456",
            url: "https://blossom.example.com/abc123",
            size: 1024,
            type: "image/jpeg",
            uploaded: Date(),
            // blurhash not used in this context
            dimensions: (width: 800, height: 600)
        )

        let event = try await builder
            .content("Blossom upload")
            .imetaTag(from: blob)
            .kind(EventKind.textNote)
            .build(signer: signer)

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://blossom.example.com/abc123"))
        XCTAssertTrue(imetaTag.contains("x abc123def456"))
        XCTAssertTrue(imetaTag.contains("m image/jpeg"))
        XCTAssertTrue(imetaTag.contains("dim 800x600"))
        XCTAssertTrue(imetaTag.contains("size 1024"))
    }

    // MARK: - Bech32 Tag Tests

    func testTagBech32Npub() async throws {
        let npub = "npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak5dx6pw4xrjt8xct8dxs8r5qfz"

        let event = try await builder
            .tagBech32(npub)
            .content("Tagging user")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let pTags = event.tags.filter { $0.first == "p" }
        XCTAssertEqual(pTags.count, 1)
        // Verify it decoded the npub correctly
        XCTAssertEqual(pTags[0][1].count, 64) // Hex pubkey
    }

    func testTagBech32Nevent() async throws {
        // This is a simplified test - real nevent would have valid TLV data
        let noteId = "test_event_id_32_bytes_long_____"
        let note = try Bech32.note(from: Data(noteId.utf8).hexString) // Adjusted the argument label

        let event = try await builder
            .tagBech32(note)
            .content("Referencing event")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let eTags = event.tags.filter { $0.first == "e" }
        XCTAssertEqual(eTags.count, 1)
    }

    // MARK: - Content Tag Generation Tests

    func testGenerateContentTags() async throws {
        let content = """
        Hello @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak5dx6pw4xrjt8xct8dxs8r5qfz!
        Check out #nostr and #bitcoin.
        Reply to nostr:note1g0x88z48geckmthwmpqd4lhymn7hyhv393288s4qw09c54hrgfqj9y5tf
        """

        let event = try await builder
            .content(content)
            .generateContentTags()
            .kind(EventKind.textNote)
            .build(signer: signer, generateContentTags: false) // Already generated

        // Check hashtags
        let tTags = event.tags.filter { $0.first == "t" }
        XCTAssertTrue(tTags.contains(["t", "nostr"]))
        XCTAssertTrue(tTags.contains(["t", "bitcoin"]))

        // Check user mention
        let pTags = event.tags.filter { $0.first == "p" }
        XCTAssertGreaterThan(pTags.count, 0)

        // Check event mention
        let eTags = event.tags.filter { $0.first == "e" }
        XCTAssertGreaterThan(eTags.count, 0)

        // Content should be normalized to nostr: URIs
        XCTAssertTrue(event.content.contains("nostr:"))
    }

    func testContentWithAutomaticImetaExtraction() async throws {
        let content = """
        Check out these files:
        https://example.com/image.jpg
        https://example.com/video.mp4
        https://example.com/document.pdf
        """

        let event = try await builder
            .content(content, extractImeta: true)
            .kind(EventKind.textNote)
            .build(signer: signer)

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 3)

        // Verify each media URL got an imeta tag
        for url in ["https://example.com/image.jpg", "https://example.com/video.mp4", "https://example.com/document.pdf"] {
            XCTAssertTrue(imetaTags.contains { tag in
                tag.contains { component in
                    component == "url \(url)"
                }
            })
        }
    }

    // MARK: - Encryption Tests

    func testEncryptToRecipient() async throws {
        let recipientPubkey = "recipient_pubkey_64_chars_hex_abcdef1234567890abcdef1234567890abcd"

        let event = try await builder
            .kind(EventKind.encryptedDirectMessage)
            .content("Secret message")
            .encrypt(recipientPubkey: recipientPubkey, signer: signer, scheme: .nip44)

        XCTAssertEqual(event.kind, EventKind.encryptedDirectMessage)
        XCTAssertNotEqual(event.content, "Secret message") // Should be encrypted
        XCTAssertTrue(event.content.contains("?iv=")) // NIP-44 format
    }

    func testEncryptToSelf() async throws {
        let event = try await builder
            .kind(EventKind.applicationSpecificData)
            .content("Private note to self")
            .encrypt(signer: signer) // No recipient = encrypt to self

        XCTAssertNotEqual(event.content, "Private note to self") // Should be encrypted
        XCTAssertTrue(event.content.contains("?iv=")) // NIP-44 format
    }

    // MARK: - Build Validation Tests

    func testBuildWithoutSigner() async throws {
        // Create builder without NDK (no default signer)
        let standaloneBuilder = NDKEventBuilder(ndk: try await NDKTestFactory.createNDK())

        do {
            _ = try await standaloneBuilder
                .content("Test")
                .kind(EventKind.textNote)
                .build() // No signer provided

            XCTFail("Should throw error without signer")
        } catch {
            XCTAssertTrue(error is NDKError)
        }
    }

    func testBuildWithInvalidPubkey() async throws {
        let builder = NDKEventBuilder(ndk: ndk)

        _ = builder
            .pubkey("invalid_pubkey") // Too short
            .content("Test")
            .kind(EventKind.textNote)

        // Should still build but with signer's pubkey (invalid one ignored)
        let event = try await builder.build(signer: signer)
        XCTAssertNotEqual(event.pubkey, "invalid_pubkey")
        let signerPubkey = try await signer.pubkey
        XCTAssertEqual(event.pubkey, signerPubkey)
    }

    func testBuildWithEmptyTag() async throws {
        _ = builder
            .tag([]) // Empty tag - should be ignored
            .content("Test")
            .kind(EventKind.textNote)

        let event = try await builder.build(signer: signer)
        XCTAssertEqual(event.tags.count, 0) // Empty tag not added
    }

    // MARK: - Complex Scenario Tests

    func testBuildComplexEvent() async throws {
        // Set up some context
        await ndk.outbox.track(
            pubkey: "user123",
            readRelays: ["wss://user.relay"],
            writeRelays: ["wss://user-write.relay"],
            source: .nip65
        )

        // Mock tracking of event with relay (updated API would be needed)
        // await ndk.eventTracker.track(eventId: "referenced123", relay: "wss://origin.relay")

        let referencedEvent = NDKEvent(
            id: "referenced123",
            pubkey: "author123",
            createdAt: Timestamp.now,
            kind: EventKind.textNote,
            tags: [],
            content: "Referenced content",
            sig: "sig123"
        )

        let event = try await builder
            .content("Complex event with #nostr mentions @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak5dx6pw4xrjt8xct8dxs8r5qfz and media: https://example.com/image.jpg")
            .kind(EventKind.textNote)
            .tagUser("user123", marker: "mention")
            .tagEvent(referencedEvent, marker: "root")
            .quoteEvent(referencedEvent)
            .tagHashtag("bitcoin")
            .dTag("unique-id")
            .clientTag(name: "TestClient", address: "31990:abc:test")
            .imetaTag(url: "https://example.com/extra.mp4") { imeta in
                imeta.m = "video/mp4"
                imeta.size = "10485760"
            }
            .createdAt(Date(timeIntervalSince1970: 1_700_000_000))
            .build(signer: signer)

        // Verify all components
        XCTAssertEqual(event.kind, EventKind.textNote)
        XCTAssertEqual(event.createdAt, 1_700_000_000)
        XCTAssertTrue(event.content.contains("nostr:")) // Content normalized

        // Verify tags
        XCTAssertTrue(event.tags.contains { $0.first == "p" && $0.value == "user123" })
        XCTAssertTrue(event.tags.contains { $0.first == "e" && $0.value == "referenced123" })
        XCTAssertTrue(event.tags.contains { $0.first == "q" && $0.value == "referenced123" })
        XCTAssertTrue(event.tags.contains { $0.first == "t" && $0.value == "nostr" })
        XCTAssertTrue(event.tags.contains { $0.first == "t" && $0.value == "bitcoin" })
        XCTAssertTrue(event.tags.contains { $0.first == "d" && $0.value == "unique-id" })
        XCTAssertTrue(event.tags.contains { $0.first == "client" && $0.value == "TestClient" })

        // Verify imeta tags
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2) // One auto-extracted, one manual
    }

    // MARK: - Build Unsigned Tests

    func testBuildUnsigned() async throws {
        let eventId = "predefined_event_id_for_testing_purposes_must_be_64_chars_long___"
        let signature = "predefined_signature_for_testing_purposes_must_be_128_chars_long_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd"

        let event = try await builder
            .content("Unsigned event")
            .kind(EventKind.textNote)
            .pubkey(await signer.pubkey)
            .buildUnsigned(eventId: eventId, signature: signature)

        XCTAssertEqual(event.id, eventId)
        XCTAssertEqual(event.sig, signature)
        XCTAssertEqual(event.content, "Unsigned event")
    }

    // MARK: - Edge Case Tests

    func testTagEventWithRegularEventUsingATag() async throws {
        // Try to use tagAddressableEvent on a regular event
        let regularEvent = NDKEvent(
            id: "regular123",
            pubkey: "author123",
            createdAt: Timestamp.now,
            kind: EventKind.textNote, // Not replaceable
            tags: [],
            content: "Regular content",
            sig: "sig123"
        )

        let event = try await builder
            .tagAddressableEvent(regularEvent) // Should fall back to e tag
            .content("Test")
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Should have e tag, not a tag
        let eTags = event.tags.filter { $0.first == "e" }
        let aTags = event.tags.filter { $0.first == "a" }

        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(aTags.count, 0)
    }

    func testMultipleImetaTagsForSameURL() async throws {
        let url = "https://example.com/image.jpg"

        let event = try await builder
            .content("Image: \(url)")
            .imetaTag(url: url) { imeta in
                imeta.alt = "First description"
            }
            .imetaTag(url: url) { imeta in
                imeta.alt = "Second description"
            }
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Should have multiple imeta tags even for same URL
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertGreaterThanOrEqual(imetaTags.count, 2)
    }

    func testCreatedAtWithDate() async throws {
        let specificDate = Date(timeIntervalSince1970: 1_234_567_890)

        let event = try await builder
            .createdAt(specificDate)
            .content("Test")
            .kind(EventKind.textNote)
            .build(signer: signer)

        XCTAssertEqual(event.createdAt, 1_234_567_890)
    }
}
