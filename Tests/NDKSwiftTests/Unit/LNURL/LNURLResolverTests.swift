@testable import NDKSwiftCore
import XCTest

final class LNURLResolverTests: XCTestCase {
    func testLUD16Resolution() async throws {
        // Create mock data fetcher
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(session: mockFetcher)

        // Mock response for LUD16 resolution
        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100_000_000,
            minSendable: 1000,
            metadata: """
            [["text/plain","Test Service"],["text/nostr+pubkey","d9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9e9f9c9"]]
            """,
            commentAllowed: 255,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: nil
        )

        let mockData = try JSONCoding.encoder.encode(mockResponse)

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
        let resolver = LNURLResolver(session: mockFetcher)

        // Mock response with nostrPubkey field
        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100_000_000,
            minSendable: 1000,
            metadata: """
            [["text/plain","Test Service"]]
            """,
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        )

        let mockData = try JSONCoding.encoder.encode(mockResponse)

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
        let resolver = LNURLResolver(session: mockFetcher)

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
        let resolver = LNURLResolver(session: mockFetcher)

        let mockResponse = LNURLPayResponse(
            callback: "https://example.com/lnurl-pay/callback",
            maxSendable: 100_000_000,
            minSendable: 1000,
            metadata: "invalid json",
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: false,
            nostrPubkey: nil
        )

        let mockData = try JSONCoding.encoder.encode(mockResponse)

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

    func testBech32LNURLDecoding() async throws {
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(session: mockFetcher)

        // Create a test URL
        let testURL = "https://service.com/api/v1/lnurl"
        let testURLData = testURL.data(using: .utf8)!

        // Convert to 5-bit groups for Bech32 encoding
        let encodedData = try Bech32.convertBits(data: Array(testURLData), fromBits: 8, toBits: 5, pad: true)

        // Encode as bech32 LNURL
        let bech32LNURL = try Bech32.encode(hrp: "lnurl", data: encodedData)

        // Mock response
        let mockResponse = LNURLPayResponse(
            callback: "https://service.com/lnurl-pay/callback",
            maxSendable: 100_000_000,
            minSendable: 1000,
            metadata: """
            [["text/plain","Test Service"]]
            """,
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: "testpubkey"
        )

        let mockData = try JSONCoding.encoder.encode(mockResponse)

        mockFetcher.data = mockData
        mockFetcher.response = HTTPURLResponse(
            url: URL(string: testURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        // Test resolution
        let result = try await resolver.resolve(bech32LNURL)

        XCTAssertEqual(result.providerPubkey, "testpubkey")
        XCTAssertEqual(result.payResponse.callback, "https://service.com/lnurl-pay/callback")
    }

    func testInvalidBech32HRP() async throws {
        let resolver = LNURLResolver()

        // Create a bech32 string with wrong HRP
        let testURL = "https://service.com/api/v1/lnurl"
        let testURLData = testURL.data(using: .utf8)!
        let encodedData = try Bech32.convertBits(data: Array(testURLData), fromBits: 8, toBits: 5, pad: true)
        let wrongHRPBech32 = try Bech32.encode(hrp: "wronghrp", data: encodedData)

        do {
            _ = try await resolver.resolve(wrongHRPBech32)
            XCTFail("Should have thrown error for wrong HRP")
        } catch let error as LNURLError {
            switch error {
            case let .invalidFormat(message):
                XCTAssertTrue(message.contains("Invalid HRP") || message.contains("neither LUD16 nor valid LNURL"))
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRealWorldLNURL() async throws {
        let mockFetcher = MockURLDataFetcher()
        let resolver = LNURLResolver(session: mockFetcher)

        // Create a real LNURL by encoding a valid URL
        let testURL = "https://lnurl.fiatjaf.com/lnurl-pay"
        let testURLData = testURL.data(using: .utf8)!
        let encodedData = try Bech32.convertBits(data: Array(testURLData), fromBits: 8, toBits: 5, pad: true)
        let realLNURL = try Bech32.encode(hrp: "lnurl", data: encodedData)

        // Mock response
        let mockResponse = LNURLPayResponse(
            callback: "https://lnurl.fiatjaf.com/lnurl-pay/callback",
            maxSendable: 100_000_000,
            minSendable: 1000,
            metadata: """
            [["text/plain","LNURL Test Service"]]
            """,
            commentAllowed: nil,
            tag: "payRequest",
            allowsNostr: true,
            nostrPubkey: nil
        )

        let mockData = try JSONCoding.encoder.encode(mockResponse)

        mockFetcher.data = mockData
        mockFetcher.response = HTTPURLResponse(
            url: URL(string: testURL)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        // Test resolution
        let result = try await resolver.resolve(realLNURL)

        XCTAssertEqual(result.payResponse.callback, "https://lnurl.fiatjaf.com/lnurl-pay/callback")
        XCTAssertEqual(result.metadata.first?.value, "LNURL Test Service")
    }

    func testNonHTTPLNURL() async throws {
        let resolver = LNURLResolver()

        // Create an LNURL that decodes to a non-HTTP URL
        let testURL = "ftp://service.com/api/v1/lnurl"
        let testURLData = testURL.data(using: .utf8)!
        let encodedData = try Bech32.convertBits(data: Array(testURLData), fromBits: 8, toBits: 5, pad: true)
        let bech32LNURL = try Bech32.encode(hrp: "lnurl", data: encodedData)

        do {
            _ = try await resolver.resolve(bech32LNURL)
            XCTFail("Should have thrown error for non-HTTP URL")
        } catch let error as LNURLError {
            switch error {
            case let .invalidFormat(message):
                XCTAssertTrue(message.contains("HTTP or HTTPS"))
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}

// MARK: - Mock URL Data Fetcher

class MockURLDataFetcher: NDKNetworkFetching {
    var data: Data?
    var response: URLResponse?
    var error: Error?

    func data(from _: URL) async throws -> Data {
        if let error = error {
            throw error
        }

        guard let data = data else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    func data(for _: URLRequest) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }

        guard let data = data, let response = response else {
            throw URLError(.badServerResponse)
        }

        return (data, response)
    }
}
