@testable import NDKSwiftCore
import XCTest

final class NIP92Tests: XCTestCase {
    var ndk: NDK!

    override func setUp() async throws {
        try await super.setUp()
        ndk = try await NDKTestFactory.createNDK()
        ndk.signer = try NDKPrivateKeySigner.generate()
    }

    func testAutomaticImetaExtraction() async throws {
        // Test automatic extraction of multiple media URLs
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Check out these files: https://example.com/photo.jpg and https://example.com/video.mp4")
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)

        // Verify first imeta tag
        let firstImeta = imetaTags[0]
        XCTAssertTrue(firstImeta.contains("url https://example.com/photo.jpg"))

        // Verify second imeta tag
        let secondImeta = imetaTags[1]
        XCTAssertTrue(secondImeta.contains("url https://example.com/video.mp4"))
    }

    func testDisableAutomaticExtraction() async throws {
        // Test disabling automatic extraction
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("This URL should not create imeta: https://example.com/image.png", extractImeta: false)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }

    func testManualImetaTag() async throws {
        // Test manual imeta tag with metadata
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("My photo: https://example.com/sunset.jpg", extractImeta: false)
            .imetaTag(url: "https://example.com/sunset.jpg") { imeta in
                imeta.alt = "Beautiful sunset"
                imeta.dim = "1920x1080"
                imeta.m = "image/jpeg"
                imeta.blurhash = "L6R:YnM{9Zt7~qj[j[ay9}of-;WB"
            }
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://example.com/sunset.jpg"))
        XCTAssertTrue(imetaTag.contains("alt Beautiful sunset"))
        XCTAssertTrue(imetaTag.contains("dim 1920x1080"))
        XCTAssertTrue(imetaTag.contains("m image/jpeg"))
        XCTAssertTrue(imetaTag.contains("blurhash L6R:YnM{9Zt7~qj[j[ay9}of-;WB"))
    }

    func testBlossomIntegration() async throws {
        // Test Blossom upload integration with automatic metadata
        let blossomBlob = BlossomBlob(
            sha256: "abc123def456",
            url: "https://blossom.example.com/abc123def456.jpg",
            size: 1024 * 250, // 250KB
            type: "image/jpeg",
            uploaded: Date(),
            dimensions: (width: 1920, height: 1080) // Automatically extracted
        )

        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Uploaded photo: \(blossomBlob.url)", extractImeta: false)
            .imetaTag(from: blossomBlob)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://blossom.example.com/abc123def456.jpg"))
        XCTAssertTrue(imetaTag.contains("x abc123def456"))
        XCTAssertTrue(imetaTag.contains("size 256000"))
        XCTAssertTrue(imetaTag.contains("m image/jpeg"))
        XCTAssertTrue(imetaTag.contains("dim 1920x1080"))
    }

    func testNoDuplicateImetaTags() async throws {
        // Test that manual imeta doesn't create duplicates
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Photo: https://example.com/photo.jpg", extractImeta: false)
            .imetaTag(url: "https://example.com/photo.jpg") { imeta in
                imeta.alt = "Custom description"
            }
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1, "Should not create duplicate imeta tags")
    }

    func testMediaURLExtraction() async throws {
        // Test various media file extensions
        let content = """
        Images: https://example.com/photo.jpg https://example.com/photo.JPEG https://example.com/photo.png
        Videos: https://example.com/video.mp4 https://example.com/video.webm
        Audio: https://example.com/audio.mp3 https://example.com/audio.wav
        Docs: https://example.com/doc.pdf
        With query: https://example.com/image.jpg?size=large&quality=100
        """

        let event = try await NDKEventBuilder(ndk: ndk)
            .content(content)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 9)

        // Verify case-insensitive matching
        let urls = imetaTags.compactMap { tag -> String? in
            guard let urlElement = tag.first(where: { $0.hasPrefix("url ") }) else { return nil }
            return String(urlElement.dropFirst(4))
        }
        XCTAssertTrue(urls.contains("https://example.com/photo.JPEG"))
        XCTAssertTrue(urls.contains("https://example.com/image.jpg?size=large&quality=100"))
    }

    func testPreConfiguredImetaTag() async throws {
        // Test adding a pre-configured imeta tag
        var imeta = NDKImetaTag()
        imeta.url = "https://example.com/custom.png"
        imeta.alt = "Custom image"
        imeta.dim = "800x600"
        imeta.fallback = ["https://backup1.com/custom.png", "https://backup2.com/custom.png"]

        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Image: https://example.com/custom.png", extractImeta: false)
            .imetaTag(imeta)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://example.com/custom.png"))
        XCTAssertTrue(imetaTag.contains("alt Custom image"))
        XCTAssertTrue(imetaTag.contains("dim 800x600"))
        XCTAssertTrue(imetaTag.contains("fallback https://backup1.com/custom.png"))
        XCTAssertTrue(imetaTag.contains("fallback https://backup2.com/custom.png"))
    }

    func testNoImetaForNonMediaURLs() async throws {
        // Test that non-media URLs don't get imeta tags
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Check out https://github.com/repo and https://example.com/page.html")
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }

    func testImetaTagParsing() throws {
        // Test ImetaUtils parsing
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "alt Test image",
            "dim 1920x1080",
            "m image/jpeg",
            "blurhash L6R:YnM{9Zt7~qj[j[ay9}of-;WB",
            "x abc123",
            "size 256000",
            "fallback https://backup.com/image.jpg",
        ]

        guard let imeta = ImetaUtils.mapImetaTag(tag) else {
            XCTFail("Failed to parse imeta tag")
            return
        }

        XCTAssertEqual(imeta.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta.alt, "Test image")
        XCTAssertEqual(imeta.dim, "1920x1080")
        XCTAssertEqual(imeta.m, "image/jpeg")
        XCTAssertEqual(imeta.blurhash, "L6R:YnM{9Zt7~qj[j[ay9}of-;WB")
        XCTAssertEqual(imeta.x, "abc123")
        XCTAssertEqual(imeta.size, "256000")
        XCTAssertEqual(imeta.fallback?.first, "https://backup.com/image.jpg")
    }

    func testImetaTagSerialization() throws {
        // Test ImetaUtils serialization
        var imeta = NDKImetaTag()
        imeta.url = "https://example.com/test.jpg"
        imeta.alt = "Test description"
        imeta.dim = "640x480"
        imeta.m = "image/jpeg"
        imeta.fallback = ["https://backup1.com/test.jpg", "https://backup2.com/test.jpg"]

        let tag = ImetaUtils.imetaTagToTag(imeta)

        XCTAssertEqual(tag[0], "imeta")
        XCTAssertTrue(tag.contains("url https://example.com/test.jpg"))
        XCTAssertTrue(tag.contains("alt Test description"))
        XCTAssertTrue(tag.contains("dim 640x480"))
        XCTAssertTrue(tag.contains("m image/jpeg"))
        XCTAssertTrue(tag.contains("fallback https://backup1.com/test.jpg"))
        XCTAssertTrue(tag.contains("fallback https://backup2.com/test.jpg"))
    }

    func testBlossomIntegrationWithoutMetadata() async throws {
        // Test Blossom upload without blurhash/dimensions (e.g., non-image file)
        let blossomBlob = BlossomBlob(
            sha256: "pdf123",
            url: "https://blossom.example.com/pdf123.pdf",
            size: 1024 * 500,
            type: "application/pdf"
            // No blurhash or dimensions for PDFs
        )

        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Document: \(blossomBlob.url)", extractImeta: false)
            .imetaTag(from: blossomBlob)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://blossom.example.com/pdf123.pdf"))
        XCTAssertTrue(imetaTag.contains("x pdf123"))
        XCTAssertTrue(imetaTag.contains("size 512000"))
        XCTAssertTrue(imetaTag.contains("m application/pdf"))

        // Should not contain blurhash or dimensions
        XCTAssertFalse(imetaTag.contains(where: { $0.hasPrefix("blurhash ") }))
        XCTAssertFalse(imetaTag.contains(where: { $0.hasPrefix("dim ") }))
    }

    func testMediaURLExtractionWithQueryParameters() async throws {
        // Test that URLs with query parameters are properly extracted
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Images: https://example.com/photo.jpg?size=large&quality=100 and https://cdn.example.com/image.png?cache=bust")
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)

        // Check that full URLs with query parameters are preserved
        let urls = imetaTags.compactMap { tag -> String? in
            guard let urlElement = tag.first(where: { $0.hasPrefix("url ") }) else { return nil }
            return String(urlElement.dropFirst(4))
        }
        XCTAssertTrue(urls.contains("https://example.com/photo.jpg?size=large&quality=100"))
        XCTAssertTrue(urls.contains("https://cdn.example.com/image.png?cache=bust"))
    }

    func testMediaURLExtractionCaseInsensitive() async throws {
        // Test that file extensions are matched case-insensitively
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Mixed case: https://example.com/photo.JPG and https://example.com/image.PNG and https://example.com/video.MP4")
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 3)
    }

    func testBlossomUploadWithPartialMetadata() async throws {
        // Test when only dimensions are available
        let blossomBlob = BlossomBlob(
            sha256: "partial123",
            url: "https://blossom.example.com/partial123.jpg",
            size: 1024 * 100,
            type: "image/jpeg",
            uploaded: Date()
            // No dimensions provided
        )

        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Photo: \(blossomBlob.url)", extractImeta: false)
            .imetaTag(from: blossomBlob)
            .build()

        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)

        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://blossom.example.com/partial123.jpg"))
        XCTAssertTrue(imetaTag.contains("x partial123"))
        XCTAssertTrue(imetaTag.contains("size 102400"))
        XCTAssertTrue(imetaTag.contains("m image/jpeg"))
        XCTAssertFalse(imetaTag.contains(where: { $0.hasPrefix("dim ") }))
    }
}
