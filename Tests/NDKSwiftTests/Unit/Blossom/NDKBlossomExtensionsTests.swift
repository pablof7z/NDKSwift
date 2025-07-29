import XCTest
@testable import NDKSwift

final class NDKBlossomExtensionsTests: XCTestCase {
    var ndk: NDK!
    var mockSigner: MockSigner!
    
    override func setUp() {
        super.setUp()
        ndk = NDK()
        mockSigner = MockSigner()
    }
    
    override func tearDown() {
        ndk = nil
        mockSigner = nil
        super.tearDown()
    }
    
    // MARK: - BlossomConstants Tests
    
    func testDefaultServers() {
        XCTAssertFalse(BlossomConstants.defaultServers.isEmpty)
        XCTAssertTrue(BlossomConstants.defaultServers.contains("https://blossom.primal.net"))
        XCTAssertTrue(BlossomConstants.defaultServers.contains("https://media.nostr.band"))
        XCTAssertTrue(BlossomConstants.defaultServers.contains("https://nostr.build"))
    }
    
    // MARK: - NDK Blossom Extension Tests
    
    func testBlossomClientCreation() {
        // First access should create a new client
        let client1 = ndk.blossomClient
        XCTAssertNotNil(client1)
        
        // Second access should return the same client
        let client2 = ndk.blossomClient
        XCTAssertTrue(client1 === client2)
    }
    
    func testUploadToBlossomWithoutSigner() async {
        // Test that upload fails without a signer
        do {
            _ = try await ndk.uploadToBlossom(data: Data("test".utf8))
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testUploadToBlossomWithCustomServers() async throws {
        ndk.signer = mockSigner
        
        // Create a mock Blossom client that always fails
        let mockClient = MockBlossomClient()
        ndk.extensionData["blossomClient"] = mockClient
        
        let testData = Data("test content".utf8)
        let customServers = ["https://custom1.example.com", "https://custom2.example.com"]
        
        do {
            _ = try await ndk.uploadToBlossom(
                data: testData,
                mimeType: "text/plain",
                servers: customServers
            )
            XCTFail("Should have thrown an error since mock client always fails")
        } catch {
            // Expected to fail with mock client
            XCTAssertNotNil(error)
        }
        
        // Verify mock client was called with correct servers
        XCTAssertTrue(mockClient.uploadAttempts.contains { $0.server == "https://custom1.example.com" })
        XCTAssertTrue(mockClient.uploadAttempts.contains { $0.server == "https://custom2.example.com" })
    }
    
    // MARK: - NDKEvent Blossom Extension Tests
    
    func testCreateFileMetadataEvent() async throws {
        let blob = BlossomBlob(
            sha256: "abc123",
            url: "https://blossom.example.com/abc123",
            size: 1024,
            type: "image/jpeg",
            blurhash: "L6PZfSi_.AyE_3t7t7R**0o#DgR4",
            dimensions: (width: 800, height: 600)
        )
        
        let event = try await NDKEvent.createFileMetadata(
            blobs: [blob],
            description: "Test image",
            signer: mockSigner,
            ndk: ndk
        )
        
        XCTAssertEqual(event.kind, EventKind.fileMetadata)
        XCTAssertEqual(event.content, "Test image")
        
        // Check required tags
        XCTAssertTrue(event.tags.contains { $0[0] == "url" && $0[1] == blob.url })
        XCTAssertTrue(event.tags.contains { $0[0] == "x" && $0[1] == blob.sha256 })
        XCTAssertTrue(event.tags.contains { $0[0] == "size" && $0[1] == String(blob.size) })
        XCTAssertTrue(event.tags.contains { $0[0] == "m" && $0[1] == "image/jpeg" })
        XCTAssertTrue(event.tags.contains { $0[0] == "blurhash" && $0[1] == "L6PZfSi_.AyE_3t7t7R**0o#DgR4" })
        XCTAssertTrue(event.tags.contains { $0[0] == "dim" && $0[1] == "800x600" })
    }
    
    func testCreateFileMetadataWithMultipleBlobs() async throws {
        let blob1 = BlossomBlob(
            sha256: "abc123",
            url: "https://server1.com/abc123",
            size: 1024,
            type: "image/jpeg"
        )
        
        let blob2 = BlossomBlob(
            sha256: "abc123",
            url: "https://server2.com/abc123",
            size: 1024,
            type: "image/jpeg"
        )
        
        let event = try await NDKEvent.createFileMetadata(
            blobs: [blob1, blob2],
            signer: mockSigner,
            ndk: ndk
        )
        
        // Should have multiple URL tags
        let urlTags = event.tags.filter { $0[0] == "url" }
        XCTAssertEqual(urlTags.count, 2)
        XCTAssertTrue(urlTags.contains { $0[1] == blob1.url })
        XCTAssertTrue(urlTags.contains { $0[1] == blob2.url })
    }
}

// MARK: - Mock Blossom Client

class MockBlossomClient: BlossomClient {
    struct UploadAttempt {
        let data: Data
        let mimeType: String?
        let server: String
    }
    
    var uploadAttempts: [UploadAttempt] = []
    var shouldSucceed = false
    
    override func uploadWithAuth(
        data: Data,
        mimeType: String?,
        to server: String,
        signer: NDKSigner,
        ndk: NDK,
        expiration: Date?
    ) async throws -> BlossomBlob {
        uploadAttempts.append(UploadAttempt(data: data, mimeType: mimeType, server: server))
        
        if shouldSucceed {
            return BlossomBlob(
                sha256: "mocksha256",
                url: "\(server)/mocksha256",
                size: Int64(data.count),
                type: mimeType
            )
        } else {
            throw NDKError.uploadFailed(reason: "Mock failure")
        }
    }
}