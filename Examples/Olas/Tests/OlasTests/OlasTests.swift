import XCTest
@testable import Olas

final class OlasTests: XCTestCase {
    func testImageMetadataInitialization() throws {
        let url = URL(string: "https://example.com/image.jpg")!
        let metadata = ImageMetadata(
            url: url,
            width: 1024,
            height: 768,
            blurhash: "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
            alt: "Test image"
        )
        
        XCTAssertEqual(metadata.url, url)
        XCTAssertEqual(metadata.width, 1024)
        XCTAssertEqual(metadata.height, 768)
        XCTAssertNotNil(metadata.blurhash)
        XCTAssertEqual(metadata.alt, "Test image")
    }
}