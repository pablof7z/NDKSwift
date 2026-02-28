@testable import NDKSwiftCore
import XCTest

final class BlossomClientMetadataTests: NDKTestCase {
    var mockURLSession: SimpleMockURLSession!
    var client: BlossomClient!
    var signer: NDKPrivateKeySigner!
    var ndk: NDK!

    override func setUp() async throws {
        try await super.setUp()
        mockURLSession = SimpleMockURLSession()
        client = BlossomClient(urlSession: mockURLSession)
        signer = try NDKPrivateKeySigner.generate()
        ndk = try await createTestNDK(signer: signer)
    }

    #if canImport(UIKit)
        func testUploadWithAuthExtractsImageMetadata() async throws {
            // Create a test image
            let size = CGSize(width: 200, height: 100)
            UIGraphicsBeginImageContext(size)
            let context = UIGraphicsGetCurrentContext()!
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()

            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                XCTFail("Failed to create JPEG data")
                return
            }

            let sha256 = Crypto.sha256(imageData).hexString

            // Mock successful upload response
            let uploadResponse = BlossomUploadDescriptor(
                url: "https://example.com/\(sha256).jpg",
                sha256: sha256,
                size: Int64(imageData.count),
                type: "image/jpeg",
                uploaded: Int64(Date().timeIntervalSince1970)
            )

            mockURLSession.data = try JSONCoding.encoder.encode(uploadResponse)
            mockURLSession.response = HTTPURLResponse(
                url: URL(string: "https://example.com/upload")!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )

            // Upload with automatic metadata extraction
            let blob = try await client.upload(
                data: imageData,
                mimeType: nil, // Let it auto-detect
                to: "https://example.com",
                ndk: ndk
            )

            // Verify metadata was extracted
            XCTAssertEqual(blob.sha256, sha256)
            XCTAssertEqual(blob.type, "image/jpeg")
            XCTAssertNil(blob.blurhash) // Blurhash no longer auto-generated
            XCTAssertNotNil(blob.dimensions)
            XCTAssertEqual(blob.dimensions?.width, 200)
            XCTAssertEqual(blob.dimensions?.height, 100)
            XCTAssertEqual(blob.dimensionsString, "200x100")
        }

        func testUploadWithAuthInfersMimeType() async throws {
            // Create JPEG data with proper header
            let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
            let imageData = jpegHeader + Data(repeating: 0xFF, count: 1000)

            let sha256 = Crypto.sha256(imageData).hexString

            // Mock successful upload response
            let uploadResponse = BlossomUploadDescriptor(
                url: "https://example.com/\(sha256).jpg",
                sha256: sha256,
                size: Int64(imageData.count),
                type: "image/jpeg",
                uploaded: Int64(Date().timeIntervalSince1970)
            )

            mockURLSession.data = try JSONCoding.encoder.encode(uploadResponse)
            mockURLSession.response = HTTPURLResponse(
                url: URL(string: "https://example.com/upload")!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )

            // Upload without specifying MIME type
            let blob = try await client.upload(
                data: imageData,
                mimeType: nil, // Should be inferred
                to: "https://example.com",
                ndk: ndk
            )

            // Verify MIME type was inferred
            XCTAssertEqual(blob.type, "image/jpeg")
        }
    #endif

    func testUploadWithAuthNonImageFile() async throws {
        // Create PDF-like data
        let pdfData = Data("%PDF-1.4".utf8) + Data(repeating: 0x00, count: 1000)

        let sha256 = Crypto.sha256(pdfData).hexString

        // Mock successful upload response
        let uploadResponse = BlossomUploadDescriptor(
            url: "https://example.com/\(sha256).pdf",
            sha256: sha256,
            size: Int64(pdfData.count),
            type: "application/pdf",
            uploaded: Int64(Date().timeIntervalSince1970)
        )

        mockURLSession.data = try JSONCoding.encoder.encode(uploadResponse)
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com/upload")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )

        // Upload PDF
        let blob = try await client.upload(
            data: pdfData,
            mimeType: "application/pdf",
            to: "https://example.com",
            ndk: ndk
        )

        // Verify no image metadata was extracted
        XCTAssertEqual(blob.sha256, sha256)
        XCTAssertEqual(blob.type, "application/pdf")
        XCTAssertNil(blob.dimensions)
    }

    func testUploadWithAuthExplicitMimeTypeOverride() async throws {
        // Create data that looks like JPEG but specify different MIME type
        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
        let data = jpegHeader + Data(repeating: 0xFF, count: 1000)

        let sha256 = Crypto.sha256(data).hexString

        // Mock successful upload response
        let uploadResponse = BlossomUploadDescriptor(
            url: "https://example.com/\(sha256).bin",
            sha256: sha256,
            size: Int64(data.count),
            type: "application/octet-stream",
            uploaded: Int64(Date().timeIntervalSince1970)
        )

        mockURLSession.data = try JSONCoding.encoder.encode(uploadResponse)
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com/upload")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )

        // Upload with explicit non-image MIME type
        let blob = try await client.upload(
            data: data,
            mimeType: "application/octet-stream", // Override auto-detection
            to: "https://example.com",
            ndk: ndk
        )

        // Verify no metadata extraction occurred due to MIME type
        XCTAssertEqual(blob.type, "application/octet-stream")
        XCTAssertNil(blob.dimensions)
    }

    #if canImport(UIKit)
        func testUploadWithAuthVariousImageFormats() async throws {
            // Test PNG format
            let size = CGSize(width: 150, height: 150)
            UIGraphicsBeginImageContext(size)
            let context = UIGraphicsGetCurrentContext()!
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()

            guard let pngData = image.pngData() else {
                XCTFail("Failed to create PNG data")
                return
            }

            let sha256 = Crypto.sha256(pngData).hexString

            // Mock successful upload response
            let uploadResponse = BlossomUploadDescriptor(
                url: "https://example.com/\(sha256).png",
                sha256: sha256,
                size: Int64(pngData.count),
                type: "image/png",
                uploaded: Int64(Date().timeIntervalSince1970)
            )

            mockURLSession.data = try JSONCoding.encoder.encode(uploadResponse)
            mockURLSession.response = HTTPURLResponse(
                url: URL(string: "https://example.com/upload")!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )

            // Upload PNG with automatic metadata extraction
            let blob = try await client.upload(
                data: pngData,
                mimeType: nil, // Auto-detect
                to: "https://example.com",
                ndk: ndk
            )

            // Verify metadata was extracted for PNG
            XCTAssertEqual(blob.type, "image/png")
            XCTAssertNil(blob.blurhash) // Blurhash no longer auto-generated
            XCTAssertNotNil(blob.dimensions)
            XCTAssertEqual(blob.dimensions?.width, 150)
            XCTAssertEqual(blob.dimensions?.height, 150)
        }
    #endif
}
