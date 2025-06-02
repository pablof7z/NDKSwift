import XCTest
@testable import NDKSwift

final class BlossomClientTests: XCTestCase {
    var client: BlossomClient!
    var mockSession: MockURLSession!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockURLSession()
        client = BlossomClient(urlSession: mockSession)
        signer = NDKPrivateKeySigner.generate()
    }
    
    override func tearDown() async throws {
        client = nil
        mockSession = nil
        signer = nil
        try await super.tearDown()
    }
    
    // MARK: - Server Discovery Tests
    
    func testServerDiscovery() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let descriptor = BlossomServerDescriptor(
            name: "Test Blossom Server",
            description: "A test server",
            icon: nil,
            acceptsMimeTypes: ["image/*", "video/*"],
            maxUploadSize: 100_000_000,
            uploadUrl: "/upload",
            listUrl: "/list",
            deleteUrl: nil,
            mirrorUrl: nil
        )
        
        let responseData = try JSONEncoder().encode(descriptor)
        mockSession.data = responseData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/.well-known/blossom")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await client.discoverServer(serverURL)
        
        // Then
        XCTAssertEqual(result.name, "Test Blossom Server")
        XCTAssertEqual(result.description, "A test server")
        XCTAssertEqual(result.acceptsMimeTypes, ["image/*", "video/*"])
        XCTAssertEqual(result.maxUploadSize, 100_000_000)
    }
    
    func testServerDiscoveryWithInvalidURL() async {
        // Given
        let invalidURL = "not a url"
        
        // When/Then
        do {
            _ = try await client.discoverServer(invalidURL)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is BlossomError)
            if case BlossomError.invalidURL = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Upload Tests
    
    func testUploadSuccess() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let testData = "Hello, Blossom!".data(using: .utf8)!
        let sha256 = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"
        
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: sha256,
            size: Int64(testData.count),
            mimeType: "text/plain",
            signer: signer
        )
        
        let uploadResponse = BlossomUploadDescriptor(
            url: "\(serverURL)/\(sha256)",
            sha256: sha256,
            size: Int64(testData.count),
            type: "text/plain",
            uploaded: Int64(Date().timeIntervalSince1970)
        )
        
        mockSession.data = try JSONEncoder().encode(uploadResponse)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/upload")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await client.upload(
            data: testData,
            mimeType: "text/plain",
            to: serverURL,
            auth: auth
        )
        
        // Then
        XCTAssertEqual(result.sha256, sha256)
        XCTAssertEqual(result.size, Int64(testData.count))
        XCTAssertEqual(result.type, "text/plain")
        XCTAssertEqual(result.url, "\(serverURL)/\(sha256)")
    }
    
    func testUploadUnauthorized() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let testData = "Test".data(using: .utf8)!
        
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: "invalid",
            size: Int64(testData.count),
            mimeType: "text/plain",
            signer: signer
        )
        
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/upload")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await client.upload(
                data: testData,
                mimeType: "text/plain",
                to: serverURL,
                auth: auth
            )
            XCTFail("Expected error")
        } catch {
            if case BlossomError.unauthorized = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - List Tests
    
    func testListSuccess() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        
        let auth = try await BlossomAuth.createListAuth(signer: signer)
        
        let listResponse = BlossomListResponse(
            blobs: [
                BlossomListResponse.BlossomListItem(
                    sha256: "abc123",
                    size: 1024,
                    type: "image/jpeg",
                    uploaded: Int64(Date().timeIntervalSince1970)
                ),
                BlossomListResponse.BlossomListItem(
                    sha256: "def456",
                    size: 2048,
                    type: "image/png",
                    uploaded: Int64(Date().timeIntervalSince1970)
                )
            ]
        )
        
        mockSession.data = try JSONEncoder().encode(listResponse)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/list")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await client.list(from: serverURL, auth: auth)
        
        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].sha256, "abc123")
        XCTAssertEqual(result[0].size, 1024)
        XCTAssertEqual(result[1].sha256, "def456")
        XCTAssertEqual(result[1].size, 2048)
    }
    
    // MARK: - Delete Tests
    
    func testDeleteSuccess() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let sha256 = "abc123"
        
        let auth = try await BlossomAuth.createDeleteAuth(
            sha256: sha256,
            signer: signer
        )
        
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/\(sha256)")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then - should not throw
        try await client.delete(sha256: sha256, from: serverURL, auth: auth)
    }
    
    func testDeleteNotFound() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let sha256 = "nonexistent"
        
        let auth = try await BlossomAuth.createDeleteAuth(
            sha256: sha256,
            signer: signer
        )
        
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/\(sha256)")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            try await client.delete(sha256: sha256, from: serverURL, auth: auth)
            XCTFail("Expected error")
        } catch {
            if case BlossomError.blobNotFound = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Download Tests
    
    func testDownloadSuccess() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let testData = "Hello, Blossom!".data(using: .utf8)!
        let sha256 = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"
        
        mockSession.data = testData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/\(sha256)")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await client.download(sha256: sha256, from: serverURL)
        
        // Then
        XCTAssertEqual(result, testData)
    }
    
    func testDownloadInvalidSHA256() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let wrongData = "Wrong data".data(using: .utf8)!
        let sha256 = "expectedhash"
        
        mockSession.data = wrongData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/\(sha256)")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await client.download(sha256: sha256, from: serverURL)
            XCTFail("Expected error")
        } catch {
            if case BlossomError.invalidSHA256 = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Convenience Method Tests
    
    func testUploadWithAuth() async throws {
        // Given
        let serverURL = "https://blossom.example.com"
        let testData = "Hello, Blossom!".data(using: .utf8)!
        let sha256 = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"
        
        let uploadResponse = BlossomUploadDescriptor(
            url: "\(serverURL)/\(sha256)",
            sha256: sha256,
            size: Int64(testData.count),
            type: "text/plain",
            uploaded: Int64(Date().timeIntervalSince1970)
        )
        
        mockSession.data = try JSONEncoder().encode(uploadResponse)
        mockSession.response = HTTPURLResponse(
            url: URL(string: "\(serverURL)/upload")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await client.uploadWithAuth(
            data: testData,
            mimeType: "text/plain",
            to: serverURL,
            signer: signer
        )
        
        // Then
        XCTAssertEqual(result.sha256, sha256)
        XCTAssertEqual(result.size, Int64(testData.count))
    }
}

// MARK: - Mock URLSession

class MockURLSession: URLSession {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    
    override func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }
        
        return (data ?? Data(), response ?? URLResponse())
    }
}