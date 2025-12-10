import XCTest
@testable import NDKSwiftCore

final class ImetaUtilsTests: XCTestCase {
    
    func testMapImetaTag_SingleValueFormat() {
        let tag: Tag = ["imeta", "url https://example.com/image.jpg alt This is an image"]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta?.alt, "This is an image")
    }
    
    func testMapImetaTag_MultiValueFormat() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "alt This is an image",
            "blurhash LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
            "dim 1024x768"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta?.alt, "This is an image")
        XCTAssertEqual(imeta?.blurhash, "LKO2?U%2Tw=w]~RBVZRi};RPxuwH")
        XCTAssertEqual(imeta?.dim, "1024x768")
    }
    
    func testMapImetaTag_WithFallback() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "fallback https://mirror1.com/image.jpg",
            "fallback https://mirror2.com/image.jpg"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.url, "https://example.com/image.jpg")
        XCTAssertEqual(imeta?.fallback?.count, 2)
        XCTAssertEqual(imeta?.fallback?[0], "https://mirror1.com/image.jpg")
        XCTAssertEqual(imeta?.fallback?[1], "https://mirror2.com/image.jpg")
    }
    
    func testMapImetaTag_WithUserAnnotation() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "annotate-user pubkey123:100:200",
            "annotate-user pubkey456:300:400"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.userAnnotations?.count, 2)
        XCTAssertEqual(imeta?.userAnnotations?[0].pubkey, "pubkey123")
        XCTAssertEqual(imeta?.userAnnotations?[0].x, 100)
        XCTAssertEqual(imeta?.userAnnotations?[0].y, 200)
        XCTAssertEqual(imeta?.userAnnotations?[1].pubkey, "pubkey456")
        XCTAssertEqual(imeta?.userAnnotations?[1].x, 300)
        XCTAssertEqual(imeta?.userAnnotations?[1].y, 400)
    }
    
    func testMapImetaTag_WithAdditionalFields() {
        let tag: Tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "custom-field custom-value"
        ]
        
        let imeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(imeta)
        XCTAssertEqual(imeta?.additionalFields["custom-field"], "custom-value")
    }
    
    func testMapImetaTag_InvalidTag() {
        let invalidTags: [Tag] = [
            ["not-imeta", "url https://example.com"],
            ["imeta"], // Too short
            [], // Empty
            ["imeta", "invalid format without space"]
        ]
        
        for tag in invalidTags {
            let imeta = ImetaUtils.mapImetaTag(tag)
            XCTAssertNil(imeta, "Tag \(tag) should not be mapped")
        }
    }
    
    func testImetaTagToTag_BasicFields() {
        let imeta = NDKImetaTag(
            url: "https://example.com/image.jpg",
            blurhash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
            dim: "1024x768",
            alt: "Test image"
        )
        
        let tag = ImetaUtils.imetaTagToTag(imeta)
        
        XCTAssertEqual(tag[0], "imeta")
        XCTAssertTrue(tag.contains("url https://example.com/image.jpg"))
        XCTAssertTrue(tag.contains("blurhash LKO2?U%2Tw=w]~RBVZRi};RPxuwH"))
        XCTAssertTrue(tag.contains("dim 1024x768"))
        XCTAssertTrue(tag.contains("alt Test image"))
    }
    
    func testImetaTagToTag_AllFields() {
        let imeta = NDKImetaTag(
            url: "https://example.com/image.jpg",
            blurhash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
            dim: "1024x768",
            alt: "Test image",
            m: "image/jpeg",
            x: "sha256hash",
            size: "102400",
            fallback: ["https://mirror1.com/image.jpg", "https://mirror2.com/image.jpg"],
            userAnnotations: [
                UserAnnotation(pubkey: "pubkey123", x: 100, y: 200),
                UserAnnotation(pubkey: "pubkey456", x: 300, y: 400)
            ],
            additionalFields: ["custom": "value"]
        )
        
        let tag = ImetaUtils.imetaTagToTag(imeta)
        
        XCTAssertEqual(tag[0], "imeta")
        XCTAssertTrue(tag.contains("url https://example.com/image.jpg"))
        XCTAssertTrue(tag.contains("blurhash LKO2?U%2Tw=w]~RBVZRi};RPxuwH"))
        XCTAssertTrue(tag.contains("dim 1024x768"))
        XCTAssertTrue(tag.contains("alt Test image"))
        XCTAssertTrue(tag.contains("m image/jpeg"))
        XCTAssertTrue(tag.contains("x sha256hash"))
        XCTAssertTrue(tag.contains("size 102400"))
        XCTAssertTrue(tag.contains("fallback https://mirror1.com/image.jpg"))
        XCTAssertTrue(tag.contains("fallback https://mirror2.com/image.jpg"))
        XCTAssertTrue(tag.contains("annotate-user pubkey123:100:200"))
        XCTAssertTrue(tag.contains("annotate-user pubkey456:300:400"))
        XCTAssertTrue(tag.contains("custom value"))
    }
    
    func testImetaTagToTag_EmptyImeta() {
        let imeta = NDKImetaTag()
        let tag = ImetaUtils.imetaTagToTag(imeta)
        
        XCTAssertEqual(tag.count, 1)
        XCTAssertEqual(tag[0], "imeta")
    }
    
    func testRoundTrip() {
        let originalImeta = NDKImetaTag(
            url: "https://example.com/image.jpg",
            blurhash: "LKO2?U%2Tw=w]~RBVZRi};RPxuwH",
            dim: "1024x768",
            alt: "Test image"
        )
        
        let tag = ImetaUtils.imetaTagToTag(originalImeta)
        let reconstructedImeta = ImetaUtils.mapImetaTag(tag)
        
        XCTAssertNotNil(reconstructedImeta)
        XCTAssertEqual(reconstructedImeta?.url, originalImeta.url)
        XCTAssertEqual(reconstructedImeta?.blurhash, originalImeta.blurhash)
        XCTAssertEqual(reconstructedImeta?.dim, originalImeta.dim)
        XCTAssertEqual(reconstructedImeta?.alt, originalImeta.alt)
    }
}