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
        print("[NDKRelayConnection] connect() async called for \(url)")
        
        guard !isConnected else {
            print("[NDKRelayConnection] Already connected to \(url)")
            return
        }
        
        // If there's already a connection attempt in progress, wait for it
        if connectionContinuation != nil {
            print("[NDKRelayConnection] Connection already in progress for \(url)")
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
            print("[NDKRelayConnection] connect() async completed for \(url)")
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
            
            print("[NDKRelayConnection] Connecting to \(url)")
            
            // Create WebSocket request
            var request = URLRequest(url: url)
            request.addValue("nostr", forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            // Create WebSocket task
            webSocketTask = Self.sharedURLSession.webSocketTask(with: request)
            webSocketTask?.resume()
            
            print("[NDKRelayConnection] WebSocket task created and resumed")
            
            // Start receiving messages
            Task {
                await receiveMessages()
            }
            
            // Send a ping to verify connection is established
            await sendPing()
        #else
            // Mock connection for Linux
            print("Mock WebSocket connection to \(url) (Linux doesn't support WebSockets)")
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
    
    /// Send raw JSON to relay
    public func send(_ json: String) async throws {
        guard isConnected else {
            throw NDKError.connectionFailed(relay: url.absoluteString, message: "Not connected")
        }
        
        #if DEBUG
        if json.hasPrefix("[\"REQ\"") {
            print("🔌 \(url): \(json)")
        }
        #endif
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                throw NDKError.connectionFailed(relay: url.absoluteString, message: "No WebSocket task")
            }
            
            let message = URLSessionWebSocketTask.Message.string(json)
            try await task.send(message)
        #else
            // Mock sending for Linux
            print("Mock send to \(url): \(json)")
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
        #if DEBUG
        print("📥 RECEIVED MESSAGE FROM RELAY \(url):")
        print("   JSON: \(json)")
        #endif
        
        do {
            let message = try NostrMessage.parse(from: json)
            
            #if DEBUG
            switch message {
            case .eose(let subscriptionId):
                print("🏁 RECEIVED EOSE from \(url) for subscription: \(subscriptionId)")
            case .event(let subscriptionId, _):
                print("📋 RECEIVED EVENT from \(url) for subscription: \(subscriptionId ?? "nil")")
            case .notice(let notice):
                print("📢 RECEIVED NOTICE from \(url): \(notice)")
            default:
                print("📝 RECEIVED \(type(of: message)) from \(url)")
            }
            #endif
            
            await notifyDelegate { delegate in
                delegate.relayConnection(self, didReceiveMessage: message)
            }
        } catch {
            // Log parsing error but continue
            print("❌ Failed to parse message from \(url): \(error)")
            print("   Raw JSON: \(json)")
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
                        print("[NDKRelayConnection] Ping failed for \(self.url): \(error)")
                        await self.resumeContinuationWithError(error)
                        await self.handleConnectionError(error)
                    } else {
                        print("[NDKRelayConnection] Ping successful for \(self.url)")
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
        
        print("[NDKRelayConnection] Marked as connected: \(url)")
        
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