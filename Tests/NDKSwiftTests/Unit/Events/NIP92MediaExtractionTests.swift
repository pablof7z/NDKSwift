import XCTest
@testable import NDKSwift

final class NIP92MediaExtractionTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        ndk.signer = try NDKPrivateKeySigner.generate()
    }
    
    // MARK: - URL Extraction Edge Cases
    
    func testExtractsURLsAtBeginningAndEnd() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("https://example.com/start.jpg here's some text and ends with https://example.com/end.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
        
        let urls = imetaTags.compactMap { tag -> String? in
            guard let urlElement = tag.first(where: { $0.hasPrefix("url ") }) else { return nil }
            return String(urlElement.dropFirst(4))
        }
        XCTAssertTrue(urls.contains("https://example.com/start.jpg"))
        XCTAssertTrue(urls.contains("https://example.com/end.png"))
    }
    
    func testExtractsURLsWithVariousProtocols() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("HTTP: http://example.com/image.jpg and HTTPS: https://secure.com/photo.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testIgnoresInvalidURLs() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Invalid: htp://example.com/image.jpg and ftp://example.com/photo.png and example.com/image.jpg")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }
    
    func testExtractsURLsWithComplexQueryParameters() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Complex: https://cdn.example.com/image.jpg?size=large&quality=100&cache=bust&format=webp")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)
        
        let url = imetaTags[0].first { $0.hasPrefix("url ") }?.dropFirst(4)
        XCTAssertEqual(url, "https://cdn.example.com/image.jpg?size=large&quality=100&cache=bust&format=webp")
    }
    
    func testExtractsURLsWithAnchors() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("With anchor: https://example.com/image.png#section and https://example.com/photo.jpg#top")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testIgnoresNonMediaExtensions() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Non-media: https://example.com/page.html and https://example.com/script.js and https://example.com/style.css")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }
    
    func testExtractsAllSupportedMediaTypes() async throws {
        let supportedTypes = [
            // Images
            "https://example.com/image.jpg",
            "https://example.com/image.jpeg",
            "https://example.com/image.png",
            "https://example.com/image.gif",
            "https://example.com/image.webp",
            "https://example.com/image.bmp",
            "https://example.com/image.svg",
            // Videos
            "https://example.com/video.mp4",
            "https://example.com/video.webm",
            "https://example.com/video.mov",
            "https://example.com/video.avi",
            "https://example.com/video.mkv",
            "https://example.com/video.flv",
            "https://example.com/video.wmv",
            "https://example.com/video.m4v",
            // Audio
            "https://example.com/audio.mp3",
            "https://example.com/audio.m4a",
            "https://example.com/audio.ogg",
            "https://example.com/audio.wav",
            "https://example.com/audio.flac",
            "https://example.com/audio.aac",
            "https://example.com/audio.opus",
            // Documents
            "https://example.com/document.pdf"
        ]
        
        let content = supportedTypes.joined(separator: " ")
        let event = try await NDKEventBuilder(ndk: ndk)
            .content(content)
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, supportedTypes.count)
    }
    
    func testExtractsURLsWithSpecialCharacters() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Special: https://example.com/image-with-dash.jpg and https://example.com/photo_with_underscore.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testExtractsURLsWithPortNumbers() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("With ports: https://example.com:8080/image.jpg and http://localhost:3000/photo.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testExtractsURLsWithSubdomains() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Subdomains: https://cdn.example.com/image.jpg and https://static.files.example.co.uk/photo.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testExtractsURLsWithPaths() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Paths: https://example.com/path/to/image.jpg and https://example.com/deep/nested/path/photo.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testDoesNotExtractPartialURLs() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Partial: example.com/image.jpg and /path/to/image.png and image.jpg")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }
    
    func testExtractsURLsInMarkdown() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Markdown: ![alt text](https://example.com/image.jpg) and [link](https://example.com/photo.png)")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
    }
    
    func testExtractsURLsNextToEachOther() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Adjacent: https://example.com/1.jpg https://example.com/2.png https://example.com/3.gif")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 3)
    }
    
    func testPerformanceWithLongContent() async throws {
        // Create content with many URLs
        var urls: [String] = []
        for i in 1...100 {
            urls.append("https://example.com/image\(i).jpg")
        }
        let content = urls.joined(separator: " ")
        
        let startTime = Date()
        let event = try await NDKEventBuilder(ndk: ndk)
            .content(content)
            .build()
        let elapsed = Date().timeIntervalSince(startTime)
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 100)
        
        // Should complete reasonably fast even with 100 URLs
        XCTAssertLessThan(elapsed, 1.0, "URL extraction took too long: \(elapsed) seconds")
    }
    
    func testExtractsURLsWithEncodedCharacters() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Encoded: https://example.com/image%20with%20spaces.jpg and https://example.com/photo%2Bplus.png")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 2)
        
        // URLs should be preserved as-is with encoding
        let urls = imetaTags.compactMap { tag -> String? in
            guard let urlElement = tag.first(where: { $0.hasPrefix("url ") }) else { return nil }
            return String(urlElement.dropFirst(4))
        }
        XCTAssertTrue(urls.contains("https://example.com/image%20with%20spaces.jpg"))
        XCTAssertTrue(urls.contains("https://example.com/photo%2Bplus.png"))
    }
}