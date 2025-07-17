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
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    
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
        if connectionContinuation != nil {
            NDKLogger.shared.log(.debug, category: .relay, "Connection already in progress for \(url)")
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuation = continuation
            }
            return
        }
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuation = continuation
                
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
            connectionContinuation?.resume()
            connectionContinuation = nil
            return
        }
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard webSocketTask == nil else {
                connectionContinuation?.resume()
                connectionContinuation = nil
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
            connectionContinuation?.resume()
            connectionContinuation = nil
            
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
        guard isConnected else {
            throw NDKError.connectionFailed(relay: url.absoluteString, message: "Not connected")
        }
        
        let eventId = event.id
        NDKLogger.shared.log(.debug, category: .relay, "publishEvent called for event \(eventId)")
        
        // Create a continuation holder that we can access from the actor context
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            // Add task to handle the OK response
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    // Store the continuation - this is now within the actor context
                    Task { [weak self] in
                        await self?.storePendingContinuation(eventId: eventId, continuation: continuation)
                    }
                }
            }
            
            // Add task to send the event and handle timeout
            group.addTask {
                // Give a tiny delay to ensure continuation is stored first
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                
                // Send the event
                let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                try await self.send(eventMessage)
                NDKLogger.shared.log(.debug, category: .relay, "Event sent, waiting for OK response...")
                
                // Wait for timeout
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // If we get here, we timed out
                await self.handleTimeout(eventId: eventId)
                throw NDKError.timeout(operation: "publishEvent", seconds: Int(timeout))
            }
            
            // Wait for first result (either OK response or timeout)
            for try await result in group {
                group.cancelAll()
                return result
            }
            
            // Should never reach here
            throw NDKError.internalError("Unexpected error in publishEvent")
        }
    }
    
    /// Store a pending continuation (actor-isolated)
    private func storePendingContinuation(eventId: EventID, continuation: CheckedContinuation<Bool, Error>) {
        pendingEvents[eventId] = continuation
        NDKLogger.shared.log(.trace, category: .relay, "Stored continuation for event \(eventId)")
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
            connectionContinuation?.resume(throwing: NDKError.connectionFailed(relay: url.absoluteString, message: "No WebSocket task"))
            connectionContinuation = nil
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
            connectionContinuation?.resume()
            connectionContinuation = nil
            return
        }
        
        isConnected = true
        isInitialConnection = false
        connectedAt = Date()
        retryPolicy.reset()
        
        NDKLogger.shared.log(.info, category: .relay, "Marked as connected: \(url)")
        
        // Resume the connection continuation if waiting
        connectionContinuation?.resume()
        connectionContinuation = nil
        
        // Notify delegate
        await notifyDelegate { delegate in
            delegate.relayConnectionDidConnect(self)
        }
    }
    
    private func resumeContinuationWithError(_ error: Error) async {
        connectionContinuation?.resume(throwing: error)
        connectionContinuation = nil
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