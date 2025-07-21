#!/usr/bin/env swift

import Foundation

// Comprehensive NIP-92 Test Suite
class NIP92TestSuite {
    private var passed = 0
    private var failed = 0
    
    func runAllTests() {
        print("🔷 Comprehensive NIP-92 Media Attachments Tests")
        print("=" * 60)
        
        // URL Extraction Tests
        runTest("Extract single URL", testExtractSingleURL)
        runTest("Extract multiple URLs", testExtractMultipleURLs)
        runTest("Extract URLs with query parameters", testExtractURLsWithQueryParams)
        runTest("Case insensitive extensions", testCaseInsensitiveExtensions)
        runTest("Ignore non-media URLs", testIgnoreNonMediaURLs)
        runTest("Extract all supported media types", testAllSupportedMediaTypes)
        
        // Imeta Tag Tests
        runTest("Create basic imeta tag", testBasicImetaTag)
        runTest("Create imeta with full metadata", testFullMetadataImetaTag)
        runTest("Create imeta with fallback URLs", testImetaWithFallbacks)
        runTest("Blossom integration", testBlossomIntegration)
        
        // Edge Cases
        runTest("URLs at beginning and end", testURLsAtBoundaries)
        runTest("URLs with special characters", testURLsWithSpecialChars)
        runTest("Performance with many URLs", testPerformance)
        
        print("\n" + "=" * 60)
        print("Final Results: \(passed) passed, \(failed) failed")
        print(failed == 0 ? "✅ All tests passed!" : "❌ Some tests failed")
    }
    
    private func runTest(_ name: String, _ test: () throws -> Void) {
        print("\n▶️  \(name)")
        do {
            try test()
            print("   ✅ PASSED")
            passed += 1
        } catch {
            print("   ❌ FAILED: \(error)")
            failed += 1
        }
    }
    
    // MARK: - Test Cases
    
    func testExtractSingleURL() throws {
        let content = "Check out this photo: https://example.com/sunset.jpg"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 1, "Should extract exactly 1 URL")
        assert(urls[0] == "https://example.com/sunset.jpg", "URL should match")
    }
    
    func testExtractMultipleURLs() throws {
        let content = """
        Here are my photos:
        https://example.com/photo1.jpg
        https://example.com/photo2.png
        And a video: https://example.com/video.mp4
        """
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 3, "Should extract 3 URLs, got \(urls.count)")
        assert(urls.contains("https://example.com/photo1.jpg"), "Should contain photo1")
        assert(urls.contains("https://example.com/photo2.png"), "Should contain photo2")
        assert(urls.contains("https://example.com/video.mp4"), "Should contain video")
    }
    
    func testExtractURLsWithQueryParams() throws {
        let content = "Image: https://cdn.example.com/image.jpg?size=large&quality=100&cache=bust"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 1, "Should extract 1 URL")
        assert(urls[0] == "https://cdn.example.com/image.jpg?size=large&quality=100&cache=bust", 
               "Should preserve query parameters")
    }
    
    func testCaseInsensitiveExtensions() throws {
        let content = "Files: https://example.com/photo.JPG https://example.com/image.PNG https://example.com/video.MP4"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 3, "Should extract all 3 URLs with uppercase extensions")
    }
    
    func testIgnoreNonMediaURLs() throws {
        let content = """
        https://example.com/page.html
        https://example.com/script.js
        https://example.com/style.css
        https://github.com/repo
        """
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 0, "Should not extract non-media URLs")
    }
    
    func testAllSupportedMediaTypes() throws {
        let types = [
            // Images
            "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg",
            // Videos
            "mp4", "webm", "mov", "avi", "mkv", "flv", "wmv", "m4v",
            // Audio
            "mp3", "m4a", "ogg", "wav", "flac", "aac", "opus",
            // Documents
            "pdf"
        ]
        
        let content = types.map { "https://example.com/file.\($0)" }.joined(separator: " ")
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == types.count, "Should extract all \(types.count) media types, got \(urls.count)")
    }
    
    func testBasicImetaTag() throws {
        let imeta = NDKImetaTag(url: "https://example.com/photo.jpg")
        let tag = imetaTagToTag(imeta)
        
        assert(tag.count >= 2, "Tag should have at least 2 elements")
        assert(tag[0] == "imeta", "First element should be 'imeta'")
        assert(tag[1] == "url https://example.com/photo.jpg", "Second element should be URL")
    }
    
    func testFullMetadataImetaTag() throws {
        var imeta = NDKImetaTag(url: "https://example.com/photo.jpg")
        imeta.alt = "Beautiful sunset over mountains"
        imeta.dim = "1920x1080"
        imeta.m = "image/jpeg"
        imeta.blurhash = "L6R:YnM{9Zt7~qj[j[ay9}of-;WB"
        imeta.x = "abc123def456"
        imeta.size = "256000"
        
        let tag = imetaTagToTag(imeta)
        
        assert(tag.contains("imeta"), "Should contain imeta")
        assert(tag.contains("url https://example.com/photo.jpg"), "Should contain URL")
        assert(tag.contains("alt Beautiful sunset over mountains"), "Should contain alt text")
        assert(tag.contains("dim 1920x1080"), "Should contain dimensions")
        assert(tag.contains("m image/jpeg"), "Should contain MIME type")
        assert(tag.contains("blurhash L6R:YnM{9Zt7~qj[j[ay9}of-;WB"), "Should contain blurhash")
        assert(tag.contains("x abc123def456"), "Should contain hash")
        assert(tag.contains("size 256000"), "Should contain size")
    }
    
    func testImetaWithFallbacks() throws {
        var imeta = NDKImetaTag(url: "https://primary.com/photo.jpg")
        imeta.fallback = [
            "https://backup1.com/photo.jpg",
            "https://backup2.com/photo.jpg"
        ]
        
        let tag = imetaTagToTag(imeta)
        
        assert(tag.contains("fallback https://backup1.com/photo.jpg"), "Should contain first fallback")
        assert(tag.contains("fallback https://backup2.com/photo.jpg"), "Should contain second fallback")
    }
    
    func testBlossomIntegration() throws {
        let blob = BlossomBlob(
            sha256: "abc123def456",
            url: "https://blossom.example.com/abc123def456.jpg",
            size: 256000,
            type: "image/jpeg",
            blurhash: "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.",
            dimensions: (width: 1920, height: 1080)
        )
        
        var imeta = NDKImetaTag(url: blob.url)
        imeta.x = blob.sha256
        imeta.size = String(blob.size)
        if let type = blob.type { imeta.m = type }
        if let blurhash = blob.blurhash { imeta.blurhash = blurhash }
        if let dim = blob.dimensionsString { imeta.dim = dim }
        
        let tag = imetaTagToTag(imeta)
        
        assert(tag.contains("url https://blossom.example.com/abc123def456.jpg"), "Should contain URL")
        assert(tag.contains("x abc123def456"), "Should contain SHA256")
        assert(tag.contains("size 256000"), "Should contain size")
        assert(tag.contains("m image/jpeg"), "Should contain MIME type")
        assert(tag.contains("blurhash LGF5]+Yk^6#M@-5c,1J5@[or[Q6."), "Should contain blurhash")
        assert(tag.contains("dim 1920x1080"), "Should contain dimensions")
    }
    
    func testURLsAtBoundaries() throws {
        let content = "https://example.com/start.jpg here's text https://example.com/end.png"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 2, "Should extract URLs at start and end")
        assert(urls[0] == "https://example.com/start.jpg", "Should extract URL at start")
        assert(urls[1] == "https://example.com/end.png", "Should extract URL at end")
    }
    
    func testURLsWithSpecialChars() throws {
        let content = "Files: https://example.com/image-with-dash.jpg https://example.com/photo_underscore.png"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 2, "Should extract URLs with special characters")
    }
    
    func testPerformance() throws {
        let urls = (1...100).map { "https://example.com/image\($0).jpg" }
        let content = urls.joined(separator: " ")
        
        let start = Date()
        let extracted = extractMediaURLs(from: content)
        let elapsed = Date().timeIntervalSince(start)
        
        assert(extracted.count == 100, "Should extract all 100 URLs")
        assert(elapsed < 0.1, "Should complete in under 100ms, took \(elapsed)s")
        print("   ⏱️  Extracted 100 URLs in \(String(format: "%.3f", elapsed))s")
    }
}

// MARK: - Helper Types and Functions

struct NDKImetaTag {
    var url: String?
    var blurhash: String?
    var dim: String?
    var alt: String?
    var m: String?
    var x: String?
    var size: String?
    var fallback: [String]?
    
    init(url: String? = nil) {
        self.url = url
    }
}

struct BlossomBlob {
    let sha256: String
    let url: String
    let size: Int64
    let type: String?
    let blurhash: String?
    let dimensions: (width: Int, height: Int)?
    
    var dimensionsString: String? {
        guard let dimensions = dimensions else { return nil }
        return "\(dimensions.width)x\(dimensions.height)"
    }
}

func extractMediaURLs(from content: String) -> [String] {
    let pattern = #"https?://[^\s<>"{}|\\^\[\]`]+\.(?:jpg|jpeg|png|gif|webp|bmp|svg|mp4|webm|mov|avi|mkv|flv|wmv|m4v|mp3|m4a|ogg|wav|flac|aac|opus|pdf)(?:\?[^\s<>"{}|\\^\[\]`]*)?"#
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = regex.matches(in: content, options: [], range: range)
    
    return matches.compactMap { match in
        guard let range = Range(match.range, in: content) else { return nil }
        return String(content[range])
    }
}

func imetaTagToTag(_ imeta: NDKImetaTag) -> [String] {
    var parts = ["imeta"]
    
    if let url = imeta.url { parts.append("url \(url)") }
    if let blurhash = imeta.blurhash { parts.append("blurhash \(blurhash)") }
    if let dim = imeta.dim { parts.append("dim \(dim)") }
    if let alt = imeta.alt { parts.append("alt \(alt)") }
    if let m = imeta.m { parts.append("m \(m)") }
    if let x = imeta.x { parts.append("x \(x)") }
    if let size = imeta.size { parts.append("size \(size)") }
    if let fallback = imeta.fallback {
        for url in fallback {
            parts.append("fallback \(url)")
        }
    }
    
    return parts
}

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// Run the test suite
let suite = NIP92TestSuite()
suite.runAllTests()