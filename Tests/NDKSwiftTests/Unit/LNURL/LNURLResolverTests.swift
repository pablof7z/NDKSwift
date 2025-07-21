import XCTest
@testable import NDKSwift

final class LNURLResolverTests: XCTestCase {
    
    func testLUD16Resolution() async throws {
        // Create mock data fetcher
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(dataFetcher: mockFetcher)
        
        // Mock response for LUD16 resolution
        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100000000,
            minSendable: 1000,
            metadata: """
            [["text/plain","Test Service"],["text/nostr+pubkey","d9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9"]]
            """,
            commentAllowed: 255,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: nil
        )
        
        let encoder = JSONEncoder()
        let mockData = try encoder.encode(mockResponse)
        
        mockFetcher.data = mockData
        mockFetcher.response = HTTPURLResponse(
            url: URL(string: "https://example.com/.well-known/lnurlp/alice")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Test resolution
        let result = try await resolver.resolve("alice@example.com")
        
        XCTAssertEqual(result.providerPubkey, "d9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9")
        XCTAssertEqual(result.payResponse.callback, "https://example.com/lnurl-pay/callback")
        XCTAssertTrue(result.payResponse.allowsNostr ?? false)
        XCTAssertEqual(result.metadata.count, 2)
        XCTAssertEqual(result.metadata[0].type, "text/plain")
        XCTAssertEqual(result.metadata[0].value, "Test Service")
    }
    
    func testNostrPubkeyField() async throws {
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(dataFetcher: mockFetcher)
        
        // Mock response with nostrPubkey field
        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100000000,
            minSendable: 1000,
            metadata: """
            [["text/plain","Test Service"]]
            """,
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        )
        
        let encoder = JSONEncoder()
        let mockData = try encoder.encode(mockResponse)
        
        mockFetcher.data = mockData
        mockFetcher.response = HTTPURLResponse(
            url: URL(string: "https://example.com/.well-known/lnurlp/bob")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // Test resolution
        let result = try await resolver.resolve("bob@example.com")
        
        // Should prefer nostrPubkey field over metadata
        XCTAssertEqual(result.providerPubkey, "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")
    }
    
    func testInvalidLUD16Format() async throws {
        let resolver = LNURLResolver()
        
        do {
            _ = try await resolver.resolve("notanemail")
            XCTFail("Should have thrown error for invalid format")
        } catch let error as LNURLError {
            switch error {
            case .invalidFormat:
                // Expected
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testNetworkError() async throws {
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(dataFetcher: mockFetcher)
        
        mockFetcher.error = URLError(.notConnectedToInternet)
        
        do {
            _ = try await resolver.resolve("alice@example.com")
            XCTFail("Should have thrown network error")
        } catch let error as LNURLError {
            switch error {
            case .networkError:
                // Expected
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testInvalidMetadataJSON() async throws {
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(dataFetcher: mockFetcher)
        
        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100000000,
            minSendable: 1000,
            metadata: "invalid json",
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: false,
            nostrPubkey: nil
        )
        
        let encoder = JSONEncoder()
        let mockData = try encoder.encode(mockResponse)
        
        mockFetcher.data = mockData
        mockFetcher.response = HTTPURLResponse(
            url: URL(string: "https://example.com/.well-known/lnurlp/alice")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        do {
            _ = try await resolver.resolve("alice@example.com")
            XCTFail("Should have thrown decoding error")
        } catch let error as LNURLError {
            switch error {
            case .decodingError:
                // Expected
                break
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}

// MARK: - Mock URL Data Fetcher

class MockURLDataFetcher: URLDataFetching {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }
        
        guard let data = data, let response = response else {
            throw URLError(.badServerResponse)
        }
        
        return (data, response)
    }
}