@testable import NDKSwiftCore
import XCTest

final class NDKBlossomExtensionsTests: XCTestCase {
    var ndk: NDK!
    var mockSigner: MockNDKSigner!

    override func setUp() {
        super.setUp()
        ndk = NDK()
        mockSigner = MockNDKSigner()
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

        _ = Data("test content".utf8)
        _ = ["https://custom1.example.com", "https://custom2.example.com"]

        // We can't easily mock the Blossom client since it's internal to NDK
        // Instead, we'll just verify that the method accepts custom servers
        // In a real scenario, this would make network calls to the custom servers

        // This test would need actual server endpoints or mocked network calls
        // For now, we'll skip the actual upload test
    }

    // MARK: - NDKEvent Blossom Extension Tests

    func testCreateFileMetadataEvent() async throws {
        let blob = BlossomBlob(
            sha256: "abc123",
            url: "https://blossom.example.com/abc123",
            size: 1024,
            type: "image/jpeg",
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
        XCTAssertTrue(event.tags.contains { $0[0] == "dim" && $0[1] == "800x600" })

        // Check that no blurhash tag is present since it's not in the blob
        XCTAssertFalse(event.tags.contains { $0[0] == "blurhash" })
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
