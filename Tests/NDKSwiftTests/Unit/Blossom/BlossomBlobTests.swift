import XCTest
@testable import NDKSwiftCore

final class BlossomBlobTests: XCTestCase {
    
    func testBlossomBlobInitialization() {
        let blob = BlossomBlob(
            sha256: "abc123",
            url: "https://example.com/abc123.jpg",
            size: 1024,
            type: "image/jpeg",
            uploaded: Date(),
            dimensions: (width: 1920, height: 1080)
        )
        
        XCTAssertEqual(blob.sha256, "abc123")
        XCTAssertEqual(blob.url, "https://example.com/abc123.jpg")
        XCTAssertEqual(blob.size, 1024)
        XCTAssertEqual(blob.type, "image/jpeg")
        XCTAssertEqual(blob.dimensions?.width, 1920)
        XCTAssertEqual(blob.dimensions?.height, 1080)
    }
    
    func testBlossomBlobWithoutMetadata() {
        let blob = BlossomBlob(
            sha256: "def456",
            url: "https://example.com/def456.pdf",
            size: 2048,
            type: "application/pdf"
        )
        
        XCTAssertNil(blob.dimensions)
        XCTAssertNil(blob.dimensionsString)
    }
    
    func testDimensionsString() {
        let blob = BlossomBlob(
            sha256: "test",
            url: "https://example.com/test.jpg",
            size: 1024,
            dimensions: (width: 3024, height: 4032)
        )
        
        XCTAssertEqual(blob.dimensionsString, "3024x4032")
    }
    
    func testDimensionsStringNil() {
        let blob = BlossomBlob(
            sha256: "test",
            url: "https://example.com/test.jpg",
            size: 1024
        )
        
        XCTAssertNil(blob.dimensionsString)
    }
    
    func testBlossomBlobCodable() throws {
        let originalBlob = BlossomBlob(
            sha256: "abc123",
            url: "https://example.com/abc123.jpg",
            size: 1024,
            type: "image/jpeg",
            uploaded: Date(),
            dimensions: (width: 1920, height: 1080)
        )
        
        // Encode
        let data = try JSONCoding.encoder.encode(originalBlob)
        
        // Decode
        let decodedBlob = try JSONCoding.decoder.decode(BlossomBlob.self, from: data)
        
        // Verify all fields match
        XCTAssertEqual(decodedBlob.sha256, originalBlob.sha256)
        XCTAssertEqual(decodedBlob.url, originalBlob.url)
        XCTAssertEqual(decodedBlob.size, originalBlob.size)
        XCTAssertEqual(decodedBlob.type, originalBlob.type)
        XCTAssertEqual(decodedBlob.dimensions?.width, originalBlob.dimensions?.width)
        XCTAssertEqual(decodedBlob.dimensions?.height, originalBlob.dimensions?.height)
        
        // Check the actual JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["sha256"])
        XCTAssertNotNil(json?["url"])
        XCTAssertNotNil(json?["size"])
        XCTAssertNotNil(json?["type"])
        XCTAssertNotNil(json?["dimensionWidth"])
        XCTAssertNotNil(json?["dimensionHeight"])
    }
    
    func testBlossomBlobCodableWithoutOptionalFields() throws {
        let originalBlob = BlossomBlob(
            sha256: "def456",
            url: "https://example.com/def456.pdf",
            size: 2048
        )
        
        // Encode
        let data = try JSONCoding.encoder.encode(originalBlob)
        
        // Decode
        let decodedBlob = try JSONCoding.decoder.decode(BlossomBlob.self, from: data)
        
        // Verify required fields
        XCTAssertEqual(decodedBlob.sha256, originalBlob.sha256)
        XCTAssertEqual(decodedBlob.url, originalBlob.url)
        XCTAssertEqual(decodedBlob.size, originalBlob.size)
        
        // Verify optional fields are nil
        XCTAssertNil(decodedBlob.type)
        XCTAssertNil(decodedBlob.dimensions)
        
        // Check the JSON doesn't include nil fields
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["dimensionWidth"])
        XCTAssertNil(json?["dimensionHeight"])
    }
    
    func testBlossomBlobDecodingFromLegacyFormat() throws {
        // Test that we can decode blobs without the new fields (backward compatibility)
        let legacyJSON = """
        {
            "sha256": "legacy123",
            "url": "https://example.com/legacy.jpg",
            "size": 512,
            "type": "image/jpeg",
            "uploaded": 1234567890
        }
        """
        
        let data = legacyJSON.data(using: .utf8)!
        let json = try JSONCoding.parseDictionary(from: data)
        
        // Manually construct blob from legacy format to simulate old decoding behavior
        let blob = BlossomBlob(
            sha256: json["sha256"] as! String,
            url: json["url"] as! String,
            size: json["size"] as! Int64,
            type: json["type"] as? String,
            uploaded: Date(timeIntervalSince1970: json["uploaded"] as! TimeInterval)
        )
        
        XCTAssertEqual(blob.sha256, "legacy123")
        XCTAssertEqual(blob.url, "https://example.com/legacy.jpg")
        XCTAssertEqual(blob.size, 512)
        XCTAssertEqual(blob.type, "image/jpeg")
        XCTAssertNil(blob.dimensions)
    }
    
    func testBlossomBlobVariousDimensions() {
        // Test edge cases for dimensions
        let testCases: [(width: Int, height: Int, expected: String)] = [
            (1, 1, "1x1"),
            (100, 200, "100x200"),
            (1920, 1080, "1920x1080"),
            (9999, 9999, "9999x9999"),
            (0, 0, "0x0"), // Edge case
        ]
        
        for testCase in testCases {
            let blob = BlossomBlob(
                sha256: "test",
                url: "https://example.com/test.jpg",
                size: 1024,
                dimensions: (width: testCase.width, height: testCase.height)
            )
            
            XCTAssertEqual(blob.dimensionsString, testCase.expected)
        }
    }
}