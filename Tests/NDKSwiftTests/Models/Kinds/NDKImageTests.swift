import XCTest
@testable import NDKSwift

final class NDKImageTests: XCTestCase {
    
    var ndk: NDK!
    
    override func setUp() {
        super.setUp()
        ndk = NDK()
    }
    
    override func tearDown() {
        ndk = nil
        super.tearDown()
    }
    
    func testInitialization() {
        let image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        XCTAssertEqual(image.kind, EventKind.image)
        XCTAssertEqual(image.pubkey, "test-pubkey")
        XCTAssertTrue(image.tags.isEmpty)
        XCTAssertEqual(image.content, "")
        XCTAssertTrue(image.imetas.isEmpty)
    }
    
    func testStaticProperties() {
        XCTAssertEqual(NDKImage.kind, EventKind.image)
        XCTAssertEqual(NDKImage.kinds, [EventKind.image])
    }
    
    func testFromEvent() {
        // Create a regular event with image data
        let event = NDKEvent(
            pubkey: "test-pubkey",
            createdAt: 1234567890,
            kind: EventKind.image,
            tags: [
                ["imeta", "url https://example.com/image.jpg", "alt Test image"]
            ],
            content: "Check out this image!"
        )
        event.id = "test-event-id"
        event.sig = "test-signature"
        event.ndk = ndk
        
        let image = NDKImage.from(event: event)
        
        XCTAssertEqual(image.id, event.id)
        XCTAssertEqual(image.pubkey, event.pubkey)
        XCTAssertEqual(image.createdAt, event.createdAt)
        XCTAssertEqual(image.kind, event.kind)
        XCTAssertEqual(image.content, event.content)
        XCTAssertEqual(image.sig, event.sig)
        XCTAssertEqual(image.tags, event.tags)
        XCTAssertEqual(image.imetas.count, 1)
        XCTAssertEqual(image.imetas.first?.url, "https://example.com/image.jpg")
        XCTAssertEqual(image.imetas.first?.alt, "Test image")
    }
    
    func testIsValid() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // Initially invalid (no imeta tags)
        XCTAssertFalse(image.isValid)
        
        // Add imeta without URL - still invalid
        image.tags.append(["imeta", "alt Just alt text"])
        XCTAssertFalse(image.isValid)
        
        // Add valid imeta with URL
        image.addImeta(NDKImetaTag(url: "https://example.com/image.jpg"))
        XCTAssertTrue(image.isValid)
    }
    
    func testImetas() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // Add multiple imeta tags
        image.tags = [
            ["imeta", "url https://example1.com/image.jpg", "alt First image"],
            ["imeta", "url https://example2.com/image.jpg", "alt Second image", "dim 800x600"],
            ["not-imeta", "url https://example3.com/image.jpg"], // Should be ignored
            ["imeta", "alt No URL tag"] // Should be filtered out (no URL)
        ]
        
        let imetas = image.imetas
        
        XCTAssertEqual(imetas.count, 2)
        XCTAssertEqual(imetas[0].url, "https://example1.com/image.jpg")
        XCTAssertEqual(imetas[0].alt, "First image")
        XCTAssertEqual(imetas[1].url, "https://example2.com/image.jpg")
        XCTAssertEqual(imetas[1].alt, "Second image")
        XCTAssertEqual(imetas[1].dim, "800x600")
    }
    
    func testSetImetas() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // Add some non-imeta tags
        image.tags = [
            ["p", "some-pubkey"],
            ["imeta", "url https://old.com/image.jpg"],
            ["t", "photography"]
        ]
        
        // Set new imetas
        let newImetas = [
            NDKImetaTag(url: "https://new1.com/image.jpg", alt: "New image 1"),
            NDKImetaTag(url: "https://new2.com/image.jpg", blurhash: "LKO2?V%2Tw=w]~RBVZRi};RPxuwH")
        ]
        
        image.setImetas(newImetas)
        
        // Check that old imeta tags are removed but other tags remain
        XCTAssertEqual(image.tags.filter { $0[0] == "p" }.count, 1)
        XCTAssertEqual(image.tags.filter { $0[0] == "t" }.count, 1)
        XCTAssertEqual(image.tags.filter { $0[0] == "imeta" }.count, 2)
        
        // Verify the new imetas
        XCTAssertEqual(image.imetas.count, 2)
        XCTAssertEqual(image.imetas[0].url, "https://new1.com/image.jpg")
        XCTAssertEqual(image.imetas[0].alt, "New image 1")
        XCTAssertEqual(image.imetas[1].url, "https://new2.com/image.jpg")
        XCTAssertEqual(image.imetas[1].blurhash, "LKO2?V%2Tw=w]~RBVZRi};RPxuwH")
    }
    
    func testAddImeta() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // Add first imeta
        image.addImeta(NDKImetaTag(url: "https://example1.com/image.jpg"))
        XCTAssertEqual(image.imetas.count, 1)
        
        // Add second imeta
        image.addImeta(NDKImetaTag(url: "https://example2.com/image.jpg", alt: "Second image"))
        XCTAssertEqual(image.imetas.count, 2)
        XCTAssertEqual(image.imetas[1].alt, "Second image")
    }
    
    func testPrimaryImageURL() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // No imetas
        XCTAssertNil(image.primaryImageURL)
        
        // Add imetas
        image.setImetas([
            NDKImetaTag(url: "https://primary.com/image.jpg"),
            NDKImetaTag(url: "https://secondary.com/image.jpg")
        ])
        
        XCTAssertEqual(image.primaryImageURL, "https://primary.com/image.jpg")
    }
    
    func testImageURLs() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        image.setImetas([
            NDKImetaTag(url: "https://example1.com/image.jpg"),
            NDKImetaTag(alt: "No URL"), // Should be filtered out
            NDKImetaTag(url: "https://example2.com/image.jpg"),
            NDKImetaTag(url: "https://example3.com/image.jpg")
        ])
        
        let urls = image.imageURLs
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls[0], "https://example1.com/image.jpg")
        XCTAssertEqual(urls[1], "https://example2.com/image.jpg")
        XCTAssertEqual(urls[2], "https://example3.com/image.jpg")
    }
    
    func testPrimaryImageDimensions() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // No imetas
        XCTAssertNil(image.primaryImageDimensions)
        
        // Add imeta without dimensions
        image.addImeta(NDKImetaTag(url: "https://example.com/image.jpg"))
        XCTAssertNil(image.primaryImageDimensions)
        
        // Set imeta with valid dimensions
        image.setImetas([
            NDKImetaTag(url: "https://example.com/image.jpg", dim: "1920x1080")
        ])
        
        let dimensions = image.primaryImageDimensions
        XCTAssertNotNil(dimensions)
        XCTAssertEqual(dimensions?.width, 1920)
        XCTAssertEqual(dimensions?.height, 1080)
        
        // Test invalid dimension formats
        let invalidDimensions = [
            "invalid",
            "1920",
            "x1080",
            "1920x",
            "widthxheight"
        ]
        
        for dimString in invalidDimensions {
            image.setImetas([
                NDKImetaTag(url: "https://example.com/image.jpg", dim: dimString)
            ])
            XCTAssertNil(image.primaryImageDimensions, "Dimension string '\(dimString)' should not parse")
        }
    }
    
    func testDirectTagModification() {
        var image = NDKImage(ndk: ndk, pubkey: "test-pubkey")
        
        // Add imeta tags
        image.tags = [
            ["imeta", "url https://example.com/image.jpg", "alt Test image"]
        ]
        
        // First access
        let imetas1 = image.imetas
        XCTAssertEqual(imetas1.count, 1)
        
        // Modify tags directly
        image.tags.append(["imeta", "url https://another.com/image.jpg"])
        
        // Should reflect the new tags immediately (no caching)
        let imetas2 = image.imetas
        XCTAssertEqual(imetas2.count, 2)
        
        // Using setImetas replaces all imeta tags
        image.setImetas([
            NDKImetaTag(url: "https://new.com/image.jpg")
        ])
        
        let imetas3 = image.imetas
        XCTAssertEqual(imetas3.count, 1)
        XCTAssertEqual(imetas3.first?.url, "https://new.com/image.jpg")
    }
}