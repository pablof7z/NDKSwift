import XCTest
@testable import NDKSwiftCore

final class BlossomTypesTests: XCTestCase {
    
    // MARK: - BlossomServer Tests
    
    func testBlossomServerInitialization() {
        let server = BlossomServer(
            url: "https://blossom.example.com",
            name: "Example Server",
            description: "A test server",
            supportedMimeTypes: ["image/jpeg", "image/png"],
            maxFileSize: 10 * 1024 * 1024 // 10MB
        )
        
        XCTAssertEqual(server.url, "https://blossom.example.com")
        XCTAssertEqual(server.name, "Example Server")
        XCTAssertEqual(server.description, "A test server")
        XCTAssertEqual(server.supportedMimeTypes, ["image/jpeg", "image/png"])
        XCTAssertEqual(server.maxFileSize, 10 * 1024 * 1024)
    }
    
    func testBlossomServerCodable() throws {
        let server = BlossomServer(
            url: "https://blossom.example.com",
            name: "Test Server",
            description: "Description",
            supportedMimeTypes: ["image/jpeg"],
            maxFileSize: 5 * 1024 * 1024
        )
        
        let encoded = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(BlossomServer.self, from: encoded)
        
        XCTAssertEqual(decoded.url, server.url)
        XCTAssertEqual(decoded.name, server.name)
        XCTAssertEqual(decoded.description, server.description)
        XCTAssertEqual(decoded.supportedMimeTypes, server.supportedMimeTypes)
        XCTAssertEqual(decoded.maxFileSize, server.maxFileSize)
    }
    
    // MARK: - BlossomUploadDescriptor Tests
    
    func testBlossomUploadDescriptorCodable() throws {
        let descriptor = BlossomUploadDescriptor(
            url: "https://blossom.example.com/sha256hash",
            sha256: "abcdef1234567890",
            size: 1024,
            type: "image/jpeg",
            uploaded: 1234567890
        )
        
        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(BlossomUploadDescriptor.self, from: encoded)
        
        XCTAssertEqual(decoded.url, descriptor.url)
        XCTAssertEqual(decoded.sha256, descriptor.sha256)
        XCTAssertEqual(decoded.size, descriptor.size)
        XCTAssertEqual(decoded.type, descriptor.type)
        XCTAssertEqual(decoded.uploaded, descriptor.uploaded)
    }
    
    // MARK: - BlossomListResponse Tests
    
    func testBlossomListResponseCodable() throws {
        let listItem = BlossomListResponse.BlossomListItem(
            sha256: "hash123",
            size: 2048,
            type: "image/png",
            uploaded: 1234567890
        )
        
        let response = BlossomListResponse(blobs: [listItem])
        
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(BlossomListResponse.self, from: encoded)
        
        XCTAssertEqual(decoded.blobs.count, 1)
        XCTAssertEqual(decoded.blobs[0].sha256, listItem.sha256)
        XCTAssertEqual(decoded.blobs[0].size, listItem.size)
        XCTAssertEqual(decoded.blobs[0].type, listItem.type)
        XCTAssertEqual(decoded.blobs[0].uploaded, listItem.uploaded)
    }
    
    // MARK: - BlossomAuth Tests
    
    func testBlossomAuthCreation() async throws {
        let ndk = NDK()
        let signer = MockNDKSigner()
        
        // Test upload auth
        let uploadAuth = try await BlossomAuth.createUploadAuth(
            sha256: "testhash",
            size: 1024,
            mimeType: "image/jpeg",
            signer: signer,
            ndk: ndk,
            expiration: Date().addingTimeInterval(3600)
        )
        
        XCTAssertEqual(uploadAuth.event.kind, EventKind.blossomAuth)
        XCTAssertTrue(uploadAuth.event.tags.contains { $0[0] == "t" && $0[1] == "upload" })
        XCTAssertTrue(uploadAuth.event.tags.contains { $0[0] == "x" && $0[1] == "testhash" })
        XCTAssertTrue(uploadAuth.event.tags.contains { $0[0] == "size" && $0[1] == "1024" })
        XCTAssertTrue(uploadAuth.event.tags.contains { $0[0] == "type" && $0[1] == "image/jpeg" })
        XCTAssertTrue(uploadAuth.event.tags.contains { $0[0] == "expiration" })
    }
    
    func testBlossomAuthDeleteCreation() async throws {
        let ndk = NDK()
        let signer = MockNDKSigner()
        
        let deleteAuth = try await BlossomAuth.createDeleteAuth(
            sha256: "deletehash",
            signer: signer,
            ndk: ndk,
            reason: "Test deletion"
        )
        
        XCTAssertEqual(deleteAuth.event.kind, EventKind.blossomAuth)
        XCTAssertEqual(deleteAuth.event.content, "Test deletion")
        XCTAssertTrue(deleteAuth.event.tags.contains { $0[0] == "t" && $0[1] == "delete" })
        XCTAssertTrue(deleteAuth.event.tags.contains { $0[0] == "x" && $0[1] == "deletehash" })
    }
    
    func testBlossomAuthListCreation() async throws {
        let ndk = NDK()
        let signer = MockNDKSigner()
        
        let since = Date().addingTimeInterval(-3600)
        let until = Date()
        
        let listAuth = try await BlossomAuth.createListAuth(
            signer: signer,
            ndk: ndk,
            since: since,
            until: until
        )
        
        XCTAssertEqual(listAuth.event.kind, EventKind.blossomAuth)
        XCTAssertTrue(listAuth.event.tags.contains { $0[0] == "t" && $0[1] == "list" })
        XCTAssertTrue(listAuth.event.tags.contains { $0[0] == "since" })
        XCTAssertTrue(listAuth.event.tags.contains { $0[0] == "until" })
    }
    
    func testBlossomAuthHeaderValue() async throws {
        let ndk = NDK()
        let signer = MockNDKSigner()
        
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: "testhash",
            size: 1024,
            signer: signer,
            ndk: ndk
        )
        
        let headerValue = try auth.authorizationHeaderValue()
        
        XCTAssertTrue(headerValue.hasPrefix("Nostr "))
        
        // Verify base64 can be decoded
        let base64Part = String(headerValue.dropFirst(6))
        let decodedData = Data(base64Encoded: base64Part)
        XCTAssertNotNil(decodedData)
        
        // Verify decoded data is valid JSON
        if let decodedData = decodedData {
            let json = try JSONSerialization.jsonObject(with: decodedData)
            XCTAssertNotNil(json)
        }
    }
    
    // MARK: - BlossomServerDescriptor Tests
    
    func testBlossomServerDescriptorCodable() throws {
        let descriptor = BlossomServerDescriptor(
            name: "Test Server",
            description: "A test Blossom server",
            icon: "https://example.com/icon.png",
            acceptsMimeTypes: ["image/jpeg", "image/png", "image/gif"],
            maxUploadSize: 50 * 1024 * 1024, // 50MB
            uploadUrl: "/upload",
            listUrl: "/list",
            deleteUrl: "/delete",
            mirrorUrl: "/mirror"
        )
        
        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(BlossomServerDescriptor.self, from: encoded)
        
        XCTAssertEqual(decoded.name, descriptor.name)
        XCTAssertEqual(decoded.description, descriptor.description)
        XCTAssertEqual(decoded.icon, descriptor.icon)
        XCTAssertEqual(decoded.acceptsMimeTypes, descriptor.acceptsMimeTypes)
        XCTAssertEqual(decoded.maxUploadSize, descriptor.maxUploadSize)
        XCTAssertEqual(decoded.uploadUrl, descriptor.uploadUrl)
        XCTAssertEqual(decoded.listUrl, descriptor.listUrl)
        XCTAssertEqual(decoded.deleteUrl, descriptor.deleteUrl)
        XCTAssertEqual(decoded.mirrorUrl, descriptor.mirrorUrl)
    }
    
    func testBlossomServerDescriptorWithNilValues() throws {
        let descriptor = BlossomServerDescriptor(
            name: nil,
            description: nil,
            icon: nil,
            acceptsMimeTypes: nil,
            maxUploadSize: nil,
            uploadUrl: nil,
            listUrl: nil,
            deleteUrl: nil,
            mirrorUrl: nil
        )
        
        let encoded = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(BlossomServerDescriptor.self, from: encoded)
        
        XCTAssertNil(decoded.name)
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.icon)
        XCTAssertNil(decoded.acceptsMimeTypes)
        XCTAssertNil(decoded.maxUploadSize)
        XCTAssertNil(decoded.uploadUrl)
        XCTAssertNil(decoded.listUrl)
        XCTAssertNil(decoded.deleteUrl)
        XCTAssertNil(decoded.mirrorUrl)
    }
    
    func testBlossomServerDescriptorJSONMapping() throws {
        let json = """
        {
            "name": "Test Server",
            "description": "Description",
            "icon": "https://example.com/icon.png",
            "accepts_mime_types": ["image/jpeg"],
            "max_upload_size": 1024,
            "upload_url": "/upload",
            "list_url": "/list",
            "delete_url": "/delete",
            "mirror_url": "/mirror"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BlossomServerDescriptor.self, from: data)
        
        XCTAssertEqual(decoded.name, "Test Server")
        XCTAssertEqual(decoded.acceptsMimeTypes, ["image/jpeg"])
        XCTAssertEqual(decoded.maxUploadSize, 1024)
    }
}