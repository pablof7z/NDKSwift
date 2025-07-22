//
//  SimulatorWorkaround.swift
//  
//
//  Workaround for iOS Simulator QUIC/HTTP3 issues
//

import Foundation
import OSLog

fileprivate let logger = Logger(subsystem: "cashu-swift", category: "SimulatorWorkaround")

/// Workaround for iOS Simulator networking issues with certain mints
public enum SimulatorWorkaround {
    
    /// List of hosts known to have issues in iOS Simulator
    private static let problematicHosts = [
        "testnut.cashu.space",
        "mint.minibits.cash",
        "mint.coinos.io",
        "cashu.space"  // Add base domain too
    ]
    
    /// Check if a URL needs the simulator workaround
    public static func needsWorkaround(for url: URL) -> Bool {
        #if targetEnvironment(simulator)
        guard let host = url.host?.lowercased() else { return false }
        return problematicHosts.contains { host.contains($0) }
        #else
        return false
        #endif
    }
    
    /// Perform a request with simulator workaround if needed
    public static func performRequest<T: Decodable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        expected: T.Type,
        timeout: Double = 30
    ) async throws -> T {
        #if targetEnvironment(simulator)
        if needsWorkaround(for: url) {
            logger.debug("Using simulator workaround for: \(url.absoluteString)")
            
            // Try with a fresh URLSession to avoid connection reuse
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "CashuSwift/1.0 (iOS Simulator)",
                "Connection": "close"
            ]
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.httpMaximumConnectionsPerHost = 1
            config.httpShouldUsePipelining = false
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            
            // Disable features that might cause issues
            config.allowsCellularAccess = true
            config.allowsExpensiveNetworkAccess = true
            config.allowsConstrainedNetworkAccess = true
            config.waitsForConnectivity = false
            
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }
            
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("CashuSwift/1.0 (iOS Simulator)", forHTTPHeaderField: "User-Agent")
            request.setValue("close", forHTTPHeaderField: "Connection")
            
            if method == "POST", body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            
            do {
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    logger.debug("\(method) \(url.absoluteString) - Status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode >= 400 {
                        logger.error("Server error - Status: \(httpResponse.statusCode)")
                        throw CashuError.networkError
                    }
                }
                
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                logger.error("Simulator workaround failed for \(url.absoluteString): \(error)")
                throw error
            }
        }
        #endif
        
        // Fall back to normal request
        if method == "POST", let body = body {
            return try await Network.post(url: url, body: body, expected: T.self, timeout: timeout)
        } else {
            return try await Network.get(url: url, expected: T.self, timeout: timeout)
        }
    }
}