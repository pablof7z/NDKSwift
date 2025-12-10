import XCTest
@testable import NDKSwiftCore

final class NDKNetworkClientTests: XCTestCase {
    
    func testFetchDataSuccess() async throws {
        // Arrange
        let expectedData = "Test response".data(using: .utf8)!
        let mockSession = MockNetworkSession()
        mockSession.data = expectedData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let client = NDKNetworkClient(session: mockSession)
        
        // Act
        let data = try await client.fetchData(from: URL(string: "https://example.com")!)
        
        // Assert
        XCTAssertEqual(data, expectedData)
        XCTAssertEqual(mockSession.lastRequest?.value(forHTTPHeaderField: HTTPConstants.headerUserAgent), HTTPConstants.userAgentNDKSwift)
    }
    
    func testFetchDataHTTPError() async throws {
        // Arrange
        let mockSession = MockNetworkSession()
        mockSession.data = Data()
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let client = NDKNetworkClient(session: mockSession)
        
        // Act & Assert
        do {
            _ = try await client.fetchData(from: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is NDKError)
            if case .invalidResponse(let message) = error as? NDKError {
                XCTAssertTrue(message.contains("404"))
            } else {
                XCTFail("Expected invalidResponse error")
            }
        }
    }
    
    func testFetchJSONSuccess() async throws {
        // Arrange
        struct TestResponse: Codable, Equatable {
            let message: String
            let value: Int
        }
        
        let testResponse = TestResponse(message: "Hello", value: 42)
        let jsonData = try JSONEncoder().encode(testResponse)
        
        let mockSession = MockNetworkSession()
        mockSession.data = jsonData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let client = NDKNetworkClient(session: mockSession)
        
        // Act
        let result = try await client.fetchJSON(TestResponse.self, from: URL(string: "https://example.com")!)
        
        // Assert
        XCTAssertEqual(result, testResponse)
    }
    
    func testFetchJSONInvalidData() async throws {
        // Arrange
        struct TestResponse: Codable {
            let message: String
        }
        
        let mockSession = MockNetworkSession()
        mockSession.data = "Invalid JSON".data(using: .utf8)!
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let client = NDKNetworkClient(session: mockSession)
        
        // Act & Assert
        do {
            _ = try await client.fetchJSON(TestResponse.self, from: URL(string: "https://example.com")!)
            XCTFail("Expected error")
        } catch {
            // Should throw decoding error
            XCTAssertTrue(error is DecodingError || (error as? NDKError) != nil)
        }
    }
    
    func testFetchDataWithCustomTimeout() async throws {
        // Arrange
        let expectedData = Data()
        let mockSession = MockNetworkSession()
        mockSession.data = expectedData
        mockSession.response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        let client = NDKNetworkClient(session: mockSession)
        let customTimeout: TimeInterval = 5.0
        
        // Act
        _ = try await client.fetchData(from: URL(string: "https://example.com")!, timeout: customTimeout)
        
        // Assert
        XCTAssertEqual(mockSession.lastRequest?.timeoutInterval, customTimeout)
    }
}

// MARK: - Mock Network Session

private class MockNetworkSession: NDKNetworkFetching {
    var data: Data = Data()
    var response: URLResponse?
    var error: Error?
    var lastRequest: URLRequest?
    
    func data(from url: URL) async throws -> Data {
        if let error = error {
            throw error
        }
        return data
    }
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.lastRequest = request
        
        if let error = error {
            throw error
        }
        
        let response = self.response ?? URLResponse(
            url: request.url!,
            mimeType: nil,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        
        return (data, response)
    }
}