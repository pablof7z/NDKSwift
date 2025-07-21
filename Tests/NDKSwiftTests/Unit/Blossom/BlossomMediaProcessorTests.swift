import XCTest
@testable import NDKSwift

final class BlossomMediaProcessorTests: XCTestCase {
    
    // MARK: - MIME Type Inference Tests
    
    func testInferMimeTypeJPEG() {
        // JPEG magic bytes: FF D8 FF
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: jpegData)
        XCTAssertEqual(mimeType, "image/jpeg")
    }
    
    func testInferMimeTypePNG() {
        // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: pngData)
        XCTAssertEqual(mimeType, "image/png")
    }
    
    func testInferMimeTypeGIF() {
        // GIF magic bytes: 47 49 46 38 (GIF8)
        let gifData = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: gifData)
        XCTAssertEqual(mimeType, "image/gif")
    }
    
    func testInferMimeTypeWebP() {
        // WebP: RIFF header + WEBP at offset 8
        let webpData = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: webpData)
        XCTAssertEqual(mimeType, "image/webp")
    }
    
    func testInferMimeTypeHEIC() {
        // HEIC: ftyp box with 'heic' brand
        let heicData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: heicData)
        XCTAssertEqual(mimeType, "image/heic")
    }
    
    func testInferMimeTypeUnknown() {
        // Random data that doesn't match any known format
        let unknownData = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: unknownData)
        XCTAssertNil(mimeType)
    }
    
    func testInferMimeTypeShortData() {
        // Data too short to identify
        let shortData = Data([0xFF, 0xD8])
        let mimeType = BlossomMediaProcessor.inferMimeType(from: shortData)
        XCTAssertNil(mimeType)
    }
    
    // MARK: - Processable Image Type Tests
    
    func testIsProcessableImageType() {
        // Valid image types
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/jpeg"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/jpg"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/png"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/webp"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/heic"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("image/heif"))
        
        // Case insensitive
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("IMAGE/JPEG"))
        XCTAssertTrue(BlossomMediaProcessor.isProcessableImageType("Image/Png"))
        
        // Invalid types
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType("image/gif"))
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType("image/bmp"))
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType("video/mp4"))
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType("application/pdf"))
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType("text/plain"))
        
        // Nil type
        XCTAssertFalse(BlossomMediaProcessor.isProcessableImageType(nil))
    }
    
    // MARK: - Image Processing Tests
    
    #if canImport(UIKit)
    func testProcessImageWithValidJPEG() {
        // Create a small test image
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.blue.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create JPEG data")
            return
        }
        
        let result = BlossomMediaProcessor.processImage(jpegData)
        XCTAssertNotNil(result)
        
        if let result = result {
            // Check blurhash
            XCTAssertFalse(result.blurhash.isEmpty)
            XCTAssertTrue(result.blurhash.hasPrefix("L")) // Blurhash typically starts with L
            
            // Check dimensions
            XCTAssertEqual(result.dimensions.width, 100)
            XCTAssertEqual(result.dimensions.height, 100)
        }
    }
    
    func testProcessImageWithValidPNG() {
        // Create a small test image
        let size = CGSize(width: 200, height: 150)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        guard let pngData = image.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        
        let result = BlossomMediaProcessor.processImage(pngData)
        XCTAssertNotNil(result)
        
        if let result = result {
            // Check blurhash
            XCTAssertFalse(result.blurhash.isEmpty)
            
            // Check dimensions
            XCTAssertEqual(result.dimensions.width, 200)
            XCTAssertEqual(result.dimensions.height, 150)
        }
    }
    
    func testProcessImageWithHighResolution() {
        // Create a larger test image to test component calculation
        let size = CGSize(width: 1920, height: 1080)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        
        // Create a gradient for more interesting blurhash
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor.blue.cgColor, UIColor.green.cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil)!
        context.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: size.width, y: size.height), options: [])
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create JPEG data")
            return
        }
        
        let result = BlossomMediaProcessor.processImage(jpegData)
        XCTAssertNotNil(result)
        
        if let result = result {
            // Check dimensions
            XCTAssertEqual(result.dimensions.width, 1920)
            XCTAssertEqual(result.dimensions.height, 1080)
            
            // Blurhash should have reasonable length (components capped at 9x9)
            XCTAssertTrue(result.blurhash.count < 200)
        }
    }
    
    func testProcessImageWithInvalidData() {
        // Test with random data that isn't an image
        let invalidData = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
        let result = BlossomMediaProcessor.processImage(invalidData)
        XCTAssertNil(result)
    }
    
    func testProcessImageWithEmptyData() {
        let emptyData = Data()
        let result = BlossomMediaProcessor.processImage(emptyData)
        XCTAssertNil(result)
    }
    
    func testProcessImageWithRetinaImage() {
        // Test with a @2x scale image
        let size = CGSize(width: 100, height: 100)
        let scale: CGFloat = 2.0
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.yellow.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        guard let pngData = image.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        
        let result = BlossomMediaProcessor.processImage(pngData)
        XCTAssertNotNil(result)
        
        if let result = result {
            // Should report pixel dimensions, not logical dimensions
            XCTAssertEqual(result.dimensions.width, 200) // 100 * 2
            XCTAssertEqual(result.dimensions.height, 200) // 100 * 2
        }
    }
    #endif
    
    // MARK: - Component Calculation Tests
    
    func testBlurhashComponentCalculation() {
        // Test the component calculation logic indirectly through different image sizes
        #if canImport(UIKit)
        let testCases: [(width: Int, height: Int)] = [
            (50, 50),      // Very small - should use minimum components
            (400, 400),    // Medium - should use 4 components
            (1000, 1000),  // Large - should use more components
            (2000, 2000),  // Very large - should cap at 9 components
        ]
        
        for testCase in testCases {
            let size = CGSize(width: CGFloat(testCase.width), height: CGFloat(testCase.height))
            UIGraphicsBeginImageContext(size)
            let context = UIGraphicsGetCurrentContext()!
            context.setFillColor(UIColor.orange.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            
            guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
                XCTFail("Failed to create JPEG data for size \(testCase)")
                continue
            }
            
            let result = BlossomMediaProcessor.processImage(jpegData)
            XCTAssertNotNil(result, "Failed to process image of size \(testCase)")
            
            if let result = result {
                // Verify dimensions are correct
                XCTAssertEqual(result.dimensions.width, testCase.width)
                XCTAssertEqual(result.dimensions.height, testCase.height)
                
                // Verify blurhash exists and is reasonable
                XCTAssertFalse(result.blurhash.isEmpty)
                
                // Smaller images should have shorter blurhashes (fewer components)
                // Larger images should have longer blurhashes (more components)
                // This is a rough heuristic check
                if testCase.width <= 100 {
                    XCTAssertLessThan(result.blurhash.count, 30)
                } else if testCase.width >= 1000 {
                    XCTAssertGreaterThan(result.blurhash.count, 30)
                }
            }
        }
        #endif
    }
}