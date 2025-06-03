import XCTest
@testable import NDKSwift

final class ImetaUtilsTests: XCTestCase {
    
    func testMapImetaTag_SingleValueFormat() {
        let tag: Tag = ["imeta", "url https://example.com/image.jpg"]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertNil(imeta?.alt)
        XCTAssertNil(imeta?.blurhash)
    }
    
    func testMapImetaTag_MultiValueFormat() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "alt Beautiful sunset",
            "blurhash LKO2?V%2Tw=w]~RBVZRi};RPxuwH",
            "dim 1920x1080",
            "m image/jpeg",
            "x 1234567890abcdef",
            "size 1048576"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta?.alt, "Beautiful sunset")
        XCTAssertEqual(imeta?.blurhash, "LKO2?V%2Tw=w]~RBVZRi};RPxuwH")
        XCTAssertEqual(imeta?.dim, "1920x1080")
        XCTAssertEqual(imeta?.m, "image/jpeg")
        XCTAssertEqual(imeta?.x, "1234567890abcdef")
        XCTAssertEqual(imeta?.size, "1048576")
    }
    
    func testMapImetaTag_WithFallback() {
        let tag: Tag = [
            "imeta",
            "url https://primary.com/image.jpg",
            "fallback https://fallback1.com/image.jpg",
            "fallback https://fallback2.com/image.jpg"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://primary.com/image.jpg")
        XCTAssertEqual(imeta?.fallback?.count, 2)
        XCTAssertEqual(imeta?.fallback?[0], "https://fallback1.com/image.jpg")
        XCTAssertEqual(imeta?.fallback?[1], "https://fallback2.com/image.jpg")
    }
    
    func testMapImetaTag_WithAdditionalFields() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "custom-field custom-value",
            "another-field another-value"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta?.additionalFields["custom-field"], "custom-value")
        XCTAssertEqual(imeta?.additionalFields["another-field"], "another-value")
    }
    
    func testMapImetaTag_InvalidTag() {
        let invalidTags: [Tag] = [
            ["not-imeta", "url https://example.com"],
            ["imeta"], // Too short
            [] // Empty
        ]
        
        for tag in invalidTags {
            let imeta = ImetaUtils.mapImetaTag(tag)
            XCTAssertNil(imeta, "Tag \(tag) should not produce valid imeta")
        }
    }
    
    func testImetaTagToTag_AllFields() {
        let imeta = NDKImetaTag(
            url: "https://example.com/image.jpg",
            blurhash: "LKO2?V%2Tw=w]~RBVZRi};RPxuwH",
            dim: "1920x1080",
            alt: "Beautiful sunset",
            m: "image/jpeg",
            x: "1234567890abcdef",
            size: "1048576",
            fallback: ["https://fallback1.com", "https://fallback2.com"],
            additionalFields: ["custom": "value"]
        )
        
        let tag = ImetaUtils.imetaTagToTag(imeta)
        
        XCTAssertEqual(tag[0], "imeta")
        XCTAssertTrue(tag.contains("url https://example.com/image.jpg"))
        XCTAssertTrue(tag.contains("blurhash LKO2?V%2Tw=w]~RBVZRi};RPxuwH"))
        XCTAssertTrue(tag.contains("dim 1920x1080"))
        XCTAssertTrue(tag.contains("alt Beautiful sunset"))
        XCTAssertTrue(tag.contains("m image/jpeg"))
        XCTAssertTrue(tag.contains("x 1234567890abcdef"))
        XCTAssertTrue(tag.contains("size 1048576"))
        XCTAssertTrue(tag.contains("fallback https://fallback1.com"))
        XCTAssertTrue(tag.contains("fallback https://fallback2.com"))
        XCTAssertTrue(tag.contains("custom value"))
    }
    
    func testImetaTagToTag_MinimalFields() {
        let imeta = NDKImetaTag(url: "https://example.com/image.jpg")
        
        let tag = ImetaUtils.imetaTagToTag(imeta)
        
        XCTAssertEqual(tag.count, 2)
        XCTAssertEqual(tag[0], "imeta")
        XCTAssertEqual(tag[1], "url https://example.com/image.jpg")
    }
    
    func testRoundTrip() {
        let originalImeta = NDKImetaTag(
            url: "https://example.com/image.jpg",
            blurhash: "LKO2?V%2Tw=w]~RBVZRi};RPxuwH",
            dim: "1920x1080",
            alt: "Test image",
            fallback: ["https://fallback.com/image.jpg"]
        )
        
        let tag = ImetaUtils.imetaTagToTag(originalImeta)
        let parsedImeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(parsedImeta)
        XCTAssertEqual(parsedImeta?.url, originalImeta.url)
        XCTAssertEqual(parsedImeta?.blurhash, originalImeta.blurhash)
        XCTAssertEqual(parsedImeta?.dim, originalImeta.dim)
        XCTAssertEqual(parsedImeta?.alt, originalImeta.alt)
        XCTAssertEqual(parsedImeta?.fallback?.count, originalImeta.fallback?.count)
        XCTAssertEqual(parsedImeta?.fallback?.first, originalImeta.fallback?.first)
    }
}