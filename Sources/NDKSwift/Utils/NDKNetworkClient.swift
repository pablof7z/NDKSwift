import Foundation

/// Protocol for network data fetching
public protocol NDKNetworkFetching {
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
public struct NDKNetworkClient {
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
}