import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Delegate for relay connection events
public protocol NDKRelayConnectionDelegate: AnyObject {
    func relayConnection(_ connection: NDKRelayConnection, didReceiveMessage message: NostrMessage)
    func relayConnectionDidConnect(_ connection: NDKRelayConnection)
    func relayConnectionDidDisconnect(_ connection: NDKRelayConnection, error: Error?)
}

/// WebSocket connection to a Nostr relay using actor for thread safety
public actor NDKRelayConnection {
    private let url: URL
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        private var webSocketTask: URLSessionWebSocketTask?
        // Shared URLSession for all connections (as per Gemini's suggestion)
        private static let sharedURLSession: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            config.httpAdditionalHeaders = [
                "User-Agent": "NDKSwift 1.0"
            ]
            return URLSession(configuration: config)
        }()
    #endif
    
    public weak var delegate: NDKRelayConnectionDelegate?
    
    /// Current connection state
    public private(set) var isConnected = false
    
    /// Connection statistics
    public private(set) var messagesSent = 0
    public private(set) var messagesReceived = 0
    public private(set) var connectedAt: Date?
    
    /// Retry policy for reconnection
    private let retryPolicy = RetryPolicy(configuration: .relayConnection)
    
    /// Connection completion handlers
    private var connectionContinuations: [CheckedContinuation<Void, Error>] = []
    
    /// Track if this is an initial connection attempt
    private var isInitialConnection = true
    
    /// Track pending EVENT messages waiting for OK responses
    private var pendingEvents: [EventID: CheckedContinuation<Bool, Error>] = [:]
    
    public init(url: URL) {
        self.url = url
    }
    
    /// Set the delegate (needed because delegate is actor-isolated)
    public func setDelegate(_ delegate: NDKRelayConnectionDelegate?) {
        self.delegate = delegate
    }
    
    deinit {
        Task { [weak self] in
            await self?.disconnect()
        }
    }
    
    // MARK: - Connection Management
    
    /// Connect to the relay (async version that properly waits)
    public func connect() async throws {
        NDKLogger.shared.log(.debug, category: .relay, "connect() async called for \(url)")
        
        guard !isConnected else {
            NDKLogger.shared.log(.debug, category: .relay, "Already connected to \(url)")
            return
        }
        
        // If there's already a connection attempt in progress, wait for it
        if !connectionContinuations.isEmpty {
            NDKLogger.shared.log(.debug, category: .relay, "Connection already in progress for \(url)")
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuations.append(continuation)
            }
            return
        }
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuations.append(continuation)
                
                Task {
                    await self._connect()
                }
            }
            NDKLogger.shared.log(.debug, category: .relay, "connect() async completed for \(url)")
        } catch {
            // For initial connection failures, don't auto-retry (as per Gemini's suggestion)
            if isInitialConnection {
                isInitialConnection = false
                throw error
            } else {
                // For subsequent failures, schedule reconnection
                await scheduleReconnection()
                throw error
            }
        }
    }
    
    private func _connect() async {
        guard !isConnected else {
            // Resume all waiting continuations
            for continuation in connectionContinuations {
                continuation.resume()
            }
            connectionContinuations.removeAll()
            return
        }
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard webSocketTask == nil else {
                // Resume all waiting continuations
                for continuation in connectionContinuations {
                    continuation.resume()
                }
                connectionContinuations.removeAll()
                return
            }
            
            NDKLogger.shared.log(.info, category: .relay, "Connecting to \(url)")
            
            // Create WebSocket request
            var request = URLRequest(url: url)
            request.addValue("nostr", forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            // Create WebSocket task
            webSocketTask = Self.sharedURLSession.webSocketTask(with: request)
            webSocketTask?.resume()
            
            NDKLogger.shared.log(.debug, category: .relay, "WebSocket task created and resumed")
            
            // Start receiving messages
            Task {
                await receiveMessages()
            }
            
            // Send a ping to verify connection is established
            await sendPing()
        #else
            // Mock connection for Linux
            NDKLogger.shared.log(.info, category: .relay, "Mock WebSocket connection to \(url) (Linux doesn't support WebSockets)")
            isConnected = true
            connectedAt = Date()
            // Resume all waiting continuations
            for continuation in connectionContinuations {
                continuation.resume()
            }
            connectionContinuations.removeAll()
            
            await notifyDelegate { delegate in
                delegate.relayConnectionDidConnect(self)
            }
        #endif
    }
    
    /// Disconnect from relay
    public func disconnect() async {
        retryPolicy.cancel()
        retryPolicy.reset()
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        #endif
        
        if isConnected {
            isConnected = false
            connectedAt = nil
            await notifyDelegate { delegate in
                delegate.relayConnectionDidDisconnect(self, error: nil)
            }
        }
    }
    
    // MARK: - Message Handling
    
    /// Send a message to the relay
    public func send(_ message: NostrMessage) async throws {
        let json = try message.serialize()
        try await send(json)
    }
    
    /// Publish an event and wait for OK response
    public func publishEvent(_ event: NDKEvent, timeout: TimeInterval = 10.0) async throws -> Bool {
        // Ensure we're connected first
        if !isConnected {
            try await connect()
        }
        
        let eventId = event.id
        NDKLogger.shared.log(.debug, category: .relay, "publishEvent called for event \(eventId)")
        
        // Store continuation and handle the async work within actor context
        return try await withCheckedThrowingContinuation { continuation in
            Task { [weak self] in
                await self?.performPublishEvent(eventId: eventId, event: event, continuation: continuation, timeout: timeout)
            }
        }
    }
    
    /// Perform the actual publish event work (actor-isolated)
    private func performPublishEvent(eventId: EventID, event: NDKEvent, continuation: CheckedContinuation<Bool, Error>, timeout: TimeInterval) async {
        // Store the continuation - now within actor context
        pendingEvents[eventId] = continuation
        
        await withThrowingTaskGroup(of: Void.self) { group in
            // Send event task
            group.addTask {
                let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                try await self.send(eventMessage)
                NDKLogger.shared.log(.debug, category: .relay, "Event sent, waiting for OK response...")
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.handleTimeout(eventId: eventId)
            }
            
            // Wait for any task to complete
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                // Remove continuation and resume with error
                if let storedContinuation = pendingEvents.removeValue(forKey: eventId) {
                    storedContinuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    /// Handle timeout for a pending event (actor-isolated)
    private func handleTimeout(eventId: EventID) {
        if let continuation = pendingEvents.removeValue(forKey: eventId) {
            continuation.resume(throwing: NDKError.timeout(operation: "publishEvent", seconds: 10))
        }
    }
    
    /// Send raw JSON to relay
    public func send(_ json: String) async throws {
        guard isConnected else {
            throw NDKError.connectionFailed(relay: url.absoluteString, message: "Not connected")
        }
        
        // Log network traffic
        let parsed = try? NostrMessage.parse(from: json)
        NDKLogger.shared.logNetworkSend(to: url, message: json, parsed: parsed)
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                throw NDKError.connectionFailed(relay: url.absoluteString, message: "No WebSocket task")
            }
            
            let message = URLSessionWebSocketTask.Message.string(json)
            try await task.send(message)
        #else
            // Mock sending for Linux
            NDKLogger.shared.log(.debug, category: .relay, "Mock send to \(url): \(json)")
        #endif
        
        messagesSent += 1
    }
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func receiveMessages() async {
        guard let task = webSocketTask else { return }
        
        do {
            while true {
                let message = try await task.receive()
                messagesReceived += 1
                
                switch message {
                case let .string(json):
                    await handleReceivedMessage(json)
                case let .data(data):
                    if let json = String(data: data, encoding: .utf8) {
                        await handleReceivedMessage(json)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            // Connection closed or error occurred
            await handleConnectionError(error)
        }
    }
    #endif
    
    private func handleReceivedMessage(_ json: String) async {
        do {
            let message = try NostrMessage.parse(from: json)
            
            // Log received message
            NDKLogger.shared.logNetworkReceive(from: url, message: json, parsed: message)
            
            // Handle OK messages for pending events
            if case let .ok(eventId, accepted, errorMessage) = message {
                if let continuation = pendingEvents.removeValue(forKey: eventId) {
                    if accepted {
                        continuation.resume(returning: true)
                    } else {
                        let error = NDKError.publishFailed(
                            relay: url.absoluteString,
                            message: errorMessage ?? "Event rejected by relay"
                        )
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await notifyDelegate { delegate in
                delegate.relayConnection(self, didReceiveMessage: message)
            }
        } catch {
            // Log parsing error
            NDKLogger.shared.logNetworkParseError(from: url, message: json, error: error)
        }
    }
    
    // MARK: - Connection Verification
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func sendPing() async {
        guard let task = webSocketTask else {
            // Resume all waiting continuations with error
            for continuation in connectionContinuations {
                continuation.resume(throwing: NDKError.connectionFailed(relay: url.absoluteString, message: "No WebSocket task"))
            }
            connectionContinuations.removeAll()
            return
        }
        
        await withCheckedContinuation { continuation in
            task.sendPing { [weak self] error in
                Task { [weak self] in
                    guard let self = self else { 
                        continuation.resume()
                        return 
                    }
                    
                    if let error = error {
                        NDKLogger.shared.log(.error, category: .relay, "Ping failed for \(self.url): \(error)")
                        await self.resumeContinuationWithError(error)
                        await self.handleConnectionError(error)
                    } else {
                        NDKLogger.shared.log(.debug, category: .relay, "Ping successful for \(self.url)")
                        await self.markAsConnected()
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func markAsConnected() async {
        guard !isConnected else {
            // Resume all waiting continuations
            for continuation in connectionContinuations {
                continuation.resume()
            }
            connectionContinuations.removeAll()
            return
        }
        
        isConnected = true
        isInitialConnection = false
        connectedAt = Date()
        retryPolicy.reset()
        
        NDKLogger.shared.log(.info, category: .relay, "Marked as connected: \(url)")
        
        // Resume all waiting continuations
        for continuation in connectionContinuations {
            continuation.resume()
        }
        connectionContinuations.removeAll()
        
        // Notify delegate
        await notifyDelegate { delegate in
            delegate.relayConnectionDidConnect(self)
        }
    }
    
    private func resumeContinuationWithError(_ error: Error) async {
        // Resume all waiting continuations with error
        for continuation in connectionContinuations {
            continuation.resume(throwing: error)
        }
        connectionContinuations.removeAll()
    }
    #endif
    
    private func handleConnectionError(_ error: Error) async {
        isConnected = false
        connectedAt = nil
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            webSocketTask = nil
        #endif
        
        await notifyDelegate { delegate in
            delegate.relayConnectionDidDisconnect(self, error: error)
        }
        
        // Only schedule reconnection if this wasn't an initial connection attempt
        if !isInitialConnection {
            await scheduleReconnection()
        }
    }
    
    private func scheduleReconnection() async {
        await withCheckedContinuation { continuation in
            retryPolicy.scheduleRetry { [weak self] in
                Task { [weak self] in
                    try? await self?.connect()
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Delegate Notification Helper
    
    private func notifyDelegate(_ block: @escaping (NDKRelayConnectionDelegate) -> Void) async {
        if let delegate = delegate {
            await MainActor.run {
                block(delegate)
            }
        }
    }
}