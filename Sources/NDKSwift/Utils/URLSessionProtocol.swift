import Foundation

/// Protocol to abstract URLSession for testability
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func data(from url: URL) async throws -> (Data, URLResponse)
}

/// Extension to make URLSession conform to URLSessionProtocol
extension URLSession: URLSessionProtocol {}