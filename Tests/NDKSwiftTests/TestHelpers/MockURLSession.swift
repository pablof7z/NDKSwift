import Foundation
@testable import NDKSwiftCore

/// Mock URLSession for testing network requests
class MockURLSession: URLProtocol {
    static var data: Data?
    static var response: URLResponse?
    static var error: Error?
    
    static func createSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLSession.self]
        return URLSession(configuration: config)
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let error = MockURLSession.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            let data = MockURLSession.data ?? Data()
            let response = MockURLSession.response ?? HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {
        // Nothing to do
    }
}

/// Simple mock for testing
final class SimpleMockURLSession: NDKNetworkFetching, @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = error {
            throw error
        }
        
        let data = self.data ?? Data()
        let response = self.response ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (data, response)
    }
    
    // URLSessionProtocol conformance
    func data(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request)
    }
    
    // NDKNetworkFetching conformance - different signature
    func data(from url: URL) async throws -> Data {
        let (data, _) = try await data(for: URLRequest(url: url))
        return data
    }
    
    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        return try await data(for: request)
    }
}