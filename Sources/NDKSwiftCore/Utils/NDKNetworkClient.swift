import Foundation

/// Protocol for network data fetching
public protocol NDKNetworkFetching: Sendable {
    func data(from url: URL) async throws -> Data
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default URLSession conformance
extension URLSession: NDKNetworkFetching {
    public func data(from url: URL) async throws -> Data {
        let (data, _) = try await self.data(from: url)
        return data
    }
}

/// Centralized network client for NDKSwift
public struct NDKNetworkClient: Sendable {
    private let session: NDKNetworkFetching
    
    public init(session: NDKNetworkFetching = URLSession.shared) {
        self.session = session
    }
    
    /// Fetch data from a URL with standard NDK configuration
    public func fetchData(from url: URL, timeout: TimeInterval = NetworkConstants.timeoutRelayInfo) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(HTTPConstants.userAgentNDKSwift, forHTTPHeaderField: HTTPConstants.headerUserAgent)
        
        let (data, response) = try await session.data(for: request)
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NDKError.invalidResponse(from: "HTTP status code: \(httpResponse.statusCode)")
            }
        }
        
        return data
    }
    
    /// Fetch and decode JSON from a URL
    public func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL, timeout: TimeInterval = NetworkConstants.timeoutRelayInfo) async throws -> T {
        let data = try await fetchData(from: url, timeout: timeout)
        return try JSONCoding.decode(type, from: data)
    }
    
    /// Fetch data with custom request configuration
    public func fetchData(with request: URLRequest) async throws -> Data {
        var modifiedRequest = request
        
        // Ensure user agent is set
        if modifiedRequest.value(forHTTPHeaderField: HTTPConstants.headerUserAgent) == nil {
            modifiedRequest.setValue(HTTPConstants.userAgentNDKSwift, forHTTPHeaderField: HTTPConstants.headerUserAgent)
        }
        
        let (data, response) = try await session.data(for: modifiedRequest)
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NDKError.invalidResponse(from: "HTTP status code: \(httpResponse.statusCode)")
            }
        }
        
        return data
    }
    
    /// Fetch and validate HTTP response with detailed error handling
    public func fetchAndValidateData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var modifiedRequest = request
        
        // Ensure user agent is set
        if modifiedRequest.value(forHTTPHeaderField: HTTPConstants.headerUserAgent) == nil {
            modifiedRequest.setValue(HTTPConstants.userAgentNDKSwift, forHTTPHeaderField: HTTPConstants.headerUserAgent)
        }
        
        let (data, response) = try await session.data(for: modifiedRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NDKError.invalidResponse(from: "Non-HTTP response received")
        }
        
        try handleHTTPResponse(httpResponse, url: modifiedRequest.url)
        
        return (data, httpResponse)
    }
    
    /// Fetch and decode JSON with custom request configuration
    public func fetchAndDecode<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let (data, _) = try await fetchAndValidateData(for: request)
        return try JSONCoding.decode(type, from: data)
    }
    
    /// Handle HTTP response status codes with appropriate errors
    private func handleHTTPResponse(_ response: HTTPURLResponse, url: URL? = nil) throws {
        let urlString = url?.absoluteString ?? "unknown"
        
        switch response.statusCode {
        case 200...299:
            return // Success
        case 400:
            throw NDKError.invalidRequest("Bad request")
        case 401:
            throw NDKError.unauthorized(relay: urlString, message: "Authentication required")
        case 403:
            throw NDKError.invalidRequest("Access forbidden")
        case 404:
            throw NDKError.invalidRequest("Resource not found")
        case 408:
            throw NDKError.timeout(operation: "HTTP request", seconds: 408)
        case 429:
            throw NDKError.rateLimited(message: "Too many requests")
        case 500...599:
            throw NDKError.serverError(relay: urlString, code: response.statusCode, message: "Server error")
        default:
            throw NDKError.invalidResponse(from: "HTTP status code: \(response.statusCode)")
        }
    }
}