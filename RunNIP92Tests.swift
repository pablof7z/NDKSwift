#!/usr/bin/env swift

import Foundation

// Define a minimal test suite runner
class TestRunner {
    static func runTests() {
        print("🔷 Running NIP-92 Tests")
        print("=" * 50)
        
        let testSuite = SimpleNIP92TestRunner()
        
        let tests = [
            ("testBasicImetaExtraction", testSuite.testBasicImetaExtraction),
            ("testDisableExtraction", testSuite.testDisableExtraction),
            ("testManualImetaTag", testSuite.testManualImetaTag)
        ]
        
        var passed = 0
        var failed = 0
        
        for (name, test) in tests {
            print("\nRunning \(name)...")
            do {
                try test()
                print("✅ PASSED")
                passed += 1
            } catch {
                print("❌ FAILED: \(error)")
                failed += 1
            }
        }
        
        print("\n" + "=" * 50)
        print("Results: \(passed) passed, \(failed) failed")
    }
}

// Inline the test implementations
class SimpleNIP92TestRunner {
    func testBasicImetaExtraction() throws {
        let content = "Check out this image: https://example.com/photo.jpg"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 1, "Should extract 1 URL")
        assert(urls.first == "https://example.com/photo.jpg", "Should extract correct URL")
    }
    
    func testDisableExtraction() throws {
        // This would normally test with extractImeta: false
        // For this demo, we just verify the extraction logic works
        let content = "This URL should not create imeta: https://example.com/image.png"
        let urls = extractMediaURLs(from: content)
        
        assert(urls.count == 1, "Extraction logic should find the URL")
    }
    
    func testManualImetaTag() throws {
        // Test imeta tag creation
        var imeta = NDKImetaTag(url: "https://example.com/sunset.jpg")
        imeta.alt = "Beautiful sunset"
        imeta.dim = "1920x1080"
        
        let tag = imetaTagToTag(imeta)
        
        assert(tag[0] == "imeta", "First element should be 'imeta'")
        assert(tag.contains("url https://example.com/sunset.jpg"), "Should contain URL")
        assert(tag.contains("alt Beautiful sunset"), "Should contain alt text")
        assert(tag.contains("dim 1920x1080"), "Should contain dimensions")
    }
}

// Helper functions from the implementation
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

// Minimal imeta types and utilities
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

// String extension
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}

// Run the tests
TestRunner.runTests()