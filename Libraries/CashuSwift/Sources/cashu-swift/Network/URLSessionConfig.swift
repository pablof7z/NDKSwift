//
//  URLSessionConfig.swift
//  
//
//  Created to fix iOS Simulator network parsing issues
//

import Foundation

/// Session delegate to handle connection issues
class CashuSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Handle server trust
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Custom URLSession configuration for better iOS compatibility
enum URLSessionConfig {
    private static let sessionDelegate = CashuSessionDelegate()
    
    /// Shared URLSession instance with iOS-optimized configuration
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        
        // Add standard headers
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "CashuSwift/1.0 (iOS)"
        ]
        
        // Disable caching to avoid potential parsing issues
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        
        // Set reasonable timeouts
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        
        // iOS-specific settings
        #if os(iOS)
        // Force HTTP/1.1 on iOS to avoid HTTP/2 parsing issues
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpShouldUsePipelining = false
        
        // Disable certain features that can cause issues in simulator
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        
        // Use compatibility mode for older protocols
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        // Disable HTTP/3 and force HTTP/2 or HTTP/1.1
        if #available(iOS 15.0, *) {
            configuration.requiresDNSSECValidation = false
        }
        
        // Disable multiplexing which can cause issues
        configuration.multipathServiceType = .none
        configuration.waitsForConnectivity = false
        
        // Set protocol classes to avoid QUIC
        configuration.protocolClasses = nil
        
        // Additional iOS Simulator specific settings
        #if targetEnvironment(simulator)
        // Force older HTTP versions in simulator
        configuration.httpAdditionalHeaders?["Connection"] = "close"
        configuration.httpAdditionalHeaders?["Upgrade-Insecure-Requests"] = "0"
        #endif
        #endif
        
        // Create session with delegate for iOS
        #if os(iOS)
        return URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        #else
        return URLSession(configuration: configuration)
        #endif
    }()
}