import XCTest
@testable import NDKSwift

final class SimpleNIP92Test: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        ndk.signer = try NDKPrivateKeySigner.generate()
    }
    
    func testBasicImetaExtraction() async throws {
        // Test automatic extraction of a single media URL
        let event = try await ndk.event()
            .content("Check out this image: https://example.com/photo.jpg")
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)
        
        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://example.com/photo.jpg"))
    }
    
    func testDisableExtraction() async throws {
        // Test disabling automatic extraction
        let event = try await ndk.event()
            .content("This URL should not create imeta: https://example.com/image.png", extractImeta: false)
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 0)
    }
    
    func testManualImetaTag() async throws {
        // Test manual imeta tag
        let event = try await ndk.event()
            .content("My photo")
            .imetaTag(url: "https://example.com/sunset.jpg") { imeta in
                imeta.alt = "Beautiful sunset"
                imeta.dim = "1920x1080"
            }
            .build()
        
        let imetaTags = event.tags.filter { $0.first == "imeta" }
        XCTAssertEqual(imetaTags.count, 1)
        
        let imetaTag = imetaTags[0]
        XCTAssertTrue(imetaTag.contains("url https://example.com/sunset.jpg"))
        XCTAssertTrue(imetaTag.contains("alt Beautiful sunset"))
        XCTAssertTrue(imetaTag.contains("dim 1920x1080"))
    }
}