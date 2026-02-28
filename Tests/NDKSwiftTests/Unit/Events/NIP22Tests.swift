@testable import NDKSwiftCore
import XCTest

final class NIP22Tests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!

    override func setUp() async throws {
        try await super.setUp()

        // Create a test signer
        signer = try NDKPrivateKeySigner.generate()

        // Initialize NDK with test configuration
        ndk = try await NDKTestFactory.createNDK(signer: signer)
    }

    override func tearDown() async throws {
        ndk = nil
        signer = nil
        try await super.tearDown()
    }

    // MARK: - Kind 1 Reply Tests

    func testReplyToKind1Event() async throws {
        // Create a root event
        let rootEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Hello world")
            .kind(EventKind.textNote)
            .build()

        // Create a reply
        let reply = await NDKEventBuilder.reply(to: rootEvent, ndk: ndk)

        // Should be kind 1
        XCTAssertEqual(reply.kind, EventKind.textNote)

        // Should have root marker
        XCTAssertTrue(reply.tags.contains { tag in
            tag.count >= 4 && tag[0] == "e" && tag[1] == rootEvent.id && tag[3] == "root"
        })

        // Should have p tag for author
        XCTAssertTrue(reply.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == rootEvent.pubkey
        })
    }

    func testReplyToKind1Reply() async throws {
        // Create a root event
        let rootEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Hello world")
            .kind(EventKind.textNote)
            .build()

        // Create first reply
        let reply1 = try await NDKEventBuilder.reply(to: rootEvent, ndk: ndk)
            .content("First reply")
            .build()

        // Create second reply
        let reply2 = await NDKEventBuilder.reply(to: reply1, ndk: ndk)

        // Should be kind 1
        XCTAssertEqual(reply2.kind, EventKind.textNote)

        // Should have root tag
        XCTAssertTrue(reply2.tags.contains { tag in
            tag.count >= 4 && tag[0] == "e" && tag[1] == rootEvent.id && tag[3] == "root"
        })

        // Should have reply marker for parent
        XCTAssertTrue(reply2.tags.contains { tag in
            tag.count >= 4 && tag[0] == "e" && tag[1] == reply1.id && tag[3] == "reply"
        })

        // Should have p tags for both authors
        XCTAssertTrue(reply2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == rootEvent.pubkey
        })
        XCTAssertTrue(reply2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == reply1.pubkey
        })
    }

    // MARK: - NIP-22 Generic Reply Tests

    func testReplyToArticle() async throws {
        // Create an article (kind 30023)
        let article = try await NDKEventBuilder(ndk: ndk)
            .content("Long article content...")
            .kind(EventKind.longFormContent)
            .tag(["d", "my-article"])
            .tag(["title", "My Article"])
            .build()

        // Create a comment
        let comment = await NDKEventBuilder.reply(to: article, ndk: ndk)

        // Should be kind 1111
        XCTAssertEqual(comment.kind, EventKind.genericReply)

        // Should have uppercase A tag for root
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "A" && tag[1] == article.tagAddress
        })

        // Should have lowercase a tag for parent (same as root for top-level)
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "a" && tag[1] == article.tagAddress
        })

        // Should have K tag for root kind
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "K" && tag[1] == String(article.kind)
        })

        // Should have k tag for parent kind
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "k" && tag[1] == String(article.kind)
        })

        // Should have P tag for root author
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "P" && tag[1] == article.pubkey
        })

        // Should have p tag for parent author
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == article.pubkey
        })
    }

    func testReplyToFileMetadata() async throws {
        // Create a file metadata event (kind 1063)
        let fileEvent = try await NDKEventBuilder(ndk: ndk)
            .content("File description")
            .kind(EventKind.fileMetadata)
            .tag(["url", "https://example.com/file.jpg"])
            .tag(["m", "image/jpeg"])
            .build()

        // Create a comment
        let comment = await NDKEventBuilder.reply(to: fileEvent, ndk: ndk)

        // Should be kind 1111
        XCTAssertEqual(comment.kind, EventKind.genericReply)

        // Should have uppercase E tag for root (non-replaceable event)
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "E" && tag[1] == fileEvent.id
        })

        // Should have lowercase e tag for parent
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "e" && tag[1] == fileEvent.id
        })
    }

    func testReplyToComment() async throws {
        // Create a blog post
        let blogPost = try await NDKEventBuilder(ndk: ndk)
            .content("Blog content")
            .kind(EventKind.longFormContent)
            .tag(["d", "blog-123"])
            .build()

        // Create first comment
        let comment1 = try await NDKEventBuilder.reply(to: blogPost, ndk: ndk)
            .content("First comment")
            .build()

        // Create reply to comment
        let comment2 = await NDKEventBuilder.reply(to: comment1, ndk: ndk)

        // Should be kind 1111
        XCTAssertEqual(comment2.kind, EventKind.genericReply)

        // Should carry over uppercase tags from parent comment
        // Check A tag
        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "A" && tag[1] == blogPost.tagAddress
        })

        // Check K tag
        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "K" && tag[1] == String(blogPost.kind)
        })

        // Check P tag
        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "P" && tag[1] == blogPost.pubkey
        })

        // Should have lowercase tags for the direct parent
        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "e" && tag[1] == comment1.id
        })

        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "k" && tag[1] == String(comment1.kind)
        })

        XCTAssertTrue(comment2.tags.contains { tag in
            tag.count >= 2 && tag[0] == "p" && tag[1] == comment1.pubkey
        })
    }

    // MARK: - Edge Cases

    func testReplyToReplaceableEvent() async throws {
        // Create a replaceable event (kind 0 - metadata)
        let metadata = try await NDKEventBuilder(ndk: ndk)
            .content("{\"name\": \"Test User\"}")
            .kind(EventKind.metadata)
            .build()

        // Create a comment
        let comment = await NDKEventBuilder.reply(to: metadata, ndk: ndk)

        // Should be kind 1111
        XCTAssertEqual(comment.kind, EventKind.genericReply)

        // Should have uppercase A tag for replaceable events
        XCTAssertTrue(comment.tags.contains { tag in
            tag.count >= 2 && tag[0] == "A" && tag[1] == metadata.tagAddress
        })
    }

    func testPTagPropagation() async throws {
        // Create a different signer for second user
        let signer2 = try NDKPrivateKeySigner.generate()
        let ndk2 = try await NDKTestFactory.createNDK(signer: signer2)

        // Create blog post by user 1
        let blogPost = try await NDKEventBuilder(ndk: ndk)
            .content("Blog content")
            .kind(EventKind.longFormContent)
            .tag(["d", "blog-456"])
            .build()

        // Create comment by user 2
        let comment1 = try await NDKEventBuilder.reply(to: blogPost, ndk: ndk2)
            .content("Comment from user 2")
            .build()

        // Create reply by user 1
        let comment2 = await NDKEventBuilder.reply(to: comment1, ndk: ndk)

        // Should have p tags for both users (but not duplicate self)
        let pTags = comment2.tags.filter { $0.first == "p" }
        let pubkeys = Set(pTags.compactMap { $0.count > 1 ? $0[1] : nil })

        // Should contain both pubkeys
        XCTAssertTrue(pubkeys.contains(blogPost.pubkey))
        XCTAssertTrue(pubkeys.contains(comment1.pubkey))

        // Should not have duplicate p tags
        XCTAssertEqual(pubkeys.count, 2)
    }
}
