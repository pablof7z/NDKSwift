import Foundation

/// Handler for processing NWC response events (kind 23195)
public struct NWCResponseHandler {
    private let ndk: NDK
    private let signer: NDKSigner
    private let relayURLs: [String]
    
    public init(ndk: NDK, signer: NDKSigner, relayURLs: [String]) {
        self.ndk = ndk
        self.signer = signer
        self.relayURLs = relayURLs
    }
    
    /// Wait for a response to a specific request
    public func waitForResponse<T: Decodable>(
        requestId: String,
        responseType: T.Type,
        timeout: TimeInterval = 30
    ) async throws -> T {
        // Create filter for response events
        let filter = NDKFilter(
            kinds: [.nostrWalletConnectRes],
            tags: ["e": [requestId]],
            limit: 1
        )
        
        // Create task with timeout
        let responseTask = Task {
            // Fetch the response event
            let events = try await ndk.fetchEvents(filter, relayURLs: relayURLs)
            
            guard let responseEvent = events.first else {
                throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
            }
            
            // Decrypt the content
            try await responseEvent.decrypt(signer: signer)
            
            // Parse the response
            return try parseResponse(responseEvent.content, expectedType: responseType)
        }
        
        // Race between response and timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
        }
        
        // Wait for either response or timeout
        let result = await withTaskGroup(of: T?.self) { group in
            group.addTask {
                do {
                    return try await responseTask.value
                } catch {
                    return nil
                }
            }
            
            group.addTask {
                do {
                    try await timeoutTask.value
                    return nil
                } catch {
                    throw error
                }
            }
            
            // Return first non-nil result
            for await value in group {
                if let value = value {
                    group.cancelAll()
                    return value
                }
            }
            
            return nil
        }
        
        guard let result = result else {
            throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
        }
        
        return result
    }
    
    /// Subscribe to response events for a request with retry logic
    public func subscribeToResponse<T: Decodable>(
        requestId: String,
        responseType: T.Type,
        timeout: TimeInterval = 30,
        retryOnEose: Bool = true
    ) async throws -> T {
        let filter = NDKFilter(
            kinds: [.nostrWalletConnectRes],
            tags: ["e": [requestId]],
            limit: 1
        )
        
        let startTime = Date()
        var hasReceivedEose = false
        var retryCount = 0
        let maxRetries = 3
        
        // Create subscription
        let subscription = ndk.subscribe(filter, relayURLs: relayURLs)
        
        // Use AsyncStream to handle events
        for await event in subscription {
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                subscription.cancel()
                throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
            }
            
            switch event {
            case .event(let responseEvent):
                // Decrypt and parse response
                do {
                    try await responseEvent.decrypt(signer: signer)
                    let response = try parseResponse(responseEvent.content, expectedType: responseType)
                    subscription.cancel()
                    return response
                } catch {
                    subscription.cancel()
                    throw error
                }
                
            case .eose:
                hasReceivedEose = true
                
                // If we got EOSE without a response and retry is enabled
                if retryOnEose && retryCount < maxRetries {
                    retryCount += 1
                    // Small delay before retry
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    // The subscription continues, waiting for more events
                } else if retryCount >= maxRetries {
                    subscription.cancel()
                    throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
                }
                
            case .notice(let message):
                print("NWC Response Handler Notice: \(message)")
                
            case .closed:
                throw NWCError.connectionFailed(url: relayURLs.joined(separator: ", "))
            }
        }
        
        throw NWCError.timeout(method: "unknown", timeoutSeconds: Int(timeout))
    }
    
    /// Parse a response JSON string into the expected type
    private func parseResponse<T: Decodable>(_ jsonString: String, expectedType: T.Type) throws -> T {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NWCError.invalidResponse(reason: "Invalid UTF-8 string")
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // First decode the wrapper to check for errors
        let wrapper = try decoder.decode(NWCResponse<T>.self, from: jsonData)
        
        // Check for error
        if let error = wrapper.error {
            throw NWCError(responseError: error)
        }
        
        // Extract result
        guard let result = wrapper.result else {
            throw NWCError.invalidResponse(reason: "No result in response")
        }
        
        return result
    }
    
    /// Subscribe to notification events
    public func subscribeToNotifications() -> AsyncStream<NWCNotification<PaymentNotification>> {
        return AsyncStream { continuation in
            let filter = NDKFilter(kinds: [.nostrWalletConnectNotification])
            let subscription = ndk.subscribe(filter, relayURLs: relayURLs)
            
            Task {
                for await event in subscription {
                    switch event {
                    case .event(let notificationEvent):
                        do {
                            // Decrypt content
                            try await notificationEvent.decrypt(signer: signer)
                            
                            // Parse notification
                            guard let jsonData = notificationEvent.content.data(using: .utf8) else {
                                continue
                            }
                            
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            
                            let notification = try decoder.decode(
                                NWCNotification<PaymentNotification>.self,
                                from: jsonData
                            )
                            
                            continuation.yield(notification)
                        } catch {
                            print("Error processing NWC notification: \(error)")
                        }
                        
                    case .closed:
                        continuation.finish()
                        return
                        
                    default:
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Multi-Response Handler

extension NWCResponseHandler {
    /// Handle multiple responses for multi-payment methods
    public func waitForMultipleResponses<T: Decodable>(
        requestId: String,
        responseType: T.Type,
        expectedCount: Int,
        timeout: TimeInterval = 60
    ) async throws -> [String: Result<T, NWCError>] {
        var responses: [String: Result<T, NWCError>] = [:]
        let startTime = Date()
        
        let filter = NDKFilter(
            kinds: [.nostrWalletConnectRes],
            tags: ["e": [requestId]]
        )
        
        let subscription = ndk.subscribe(filter, relayURLs: relayURLs)
        
        for await event in subscription {
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                subscription.cancel()
                break
            }
            
            switch event {
            case .event(let responseEvent):
                do {
                    // Get the d-tag for correlation
                    guard let dTag = responseEvent.tags.first(where: { $0.count > 1 && $0[0] == "d" })?[1] else {
                        continue
                    }
                    
                    // Decrypt and parse
                    try await responseEvent.decrypt(signer: signer)
                    let response = try parseResponse(responseEvent.content, expectedType: responseType)
                    responses[dTag] = .success(response)
                    
                    // Check if we have all responses
                    if responses.count >= expectedCount {
                        subscription.cancel()
                        return responses
                    }
                } catch let error as NWCError {
                    if let dTag = responseEvent.tags.first(where: { $0.count > 1 && $0[0] == "d" })?[1] {
                        responses[dTag] = .failure(error)
                    }
                } catch {
                    if let dTag = responseEvent.tags.first(where: { $0.count > 1 && $0[0] == "d" })?[1] {
                        responses[dTag] = .failure(NWCError.invalidResponse(reason: error.localizedDescription))
                    }
                }
                
            default:
                break
            }
        }
        
        return responses
    }
}