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

/// WebSocket connection to a Nostr relay
public final class NDKRelayConnection {
    private let url: URL
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    #endif
    
    private let queue = DispatchQueue(label: "com.ndkswift.relay", qos: .utility)
    
    public weak var delegate: NDKRelayConnectionDelegate?
    
    /// Current connection state
    public private(set) var isConnected = false
    
    /// Connection statistics
    public private(set) var messagesSent = 0
    public private(set) var messagesReceived = 0
    public private(set) var connectedAt: Date?
    
    /// Reconnection configuration
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 300.0
    private var reconnectTimer: Timer?
    
    public init(url: URL) {
        self.url = url
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        #endif
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection Management
    
    /// Connect to the relay
    public func connect() {
        queue.async { [weak self] in
            self?._connect()
        }
    }
    
    private func _connect() {
        guard !isConnected else { return }
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        guard webSocketTask == nil else { return }
        
        // Create WebSocket request
        var request = URLRequest(url: url)
        request.addValue("nostr", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        
        // Create WebSocket task
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Monitor connection state
        monitorConnection()
        #else
        // Mock connection for Linux
        print("Mock WebSocket connection to \(url) (Linux doesn't support WebSockets)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            self.connectedAt = Date()
            self.delegate?.relayConnectionDidConnect(self)
        }
        #endif
    }
    
    /// Disconnect from relay
    public func disconnect() {
        queue.async { [weak self] in
            self?._disconnect()
        }
    }
    
    private func _disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        #endif
        
        if isConnected {
            isConnected = false
            connectedAt = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.relayConnectionDidDisconnect(self, error: nil)
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
            throw NDKError.relayConnectionFailed("Not connected")
        }
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        guard let task = webSocketTask else {
            throw NDKError.relayConnectionFailed("No WebSocket task")
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
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.messagesReceived += 1
                
                switch message {
                case .string(let json):
                    self.handleReceivedMessage(json)
                case .data(let data):
                    if let json = String(data: data, encoding: .utf8) {
                        self.handleReceivedMessage(json)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                self.receiveMessage()
                
            case .failure(let error):
                self.handleConnectionError(error)
            }
        }
    }
    #endif
    
    private func handleReceivedMessage(_ json: String) {
        do {
            let message = try NostrMessage.parse(from: json)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.relayConnection(self, didReceiveMessage: message)
            }
        } catch {
            // Log parsing error but continue
            print("Failed to parse message: \(error)")
        }
    }
    
    // MARK: - Connection Monitoring
    
    private func monitorConnection() {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        // Use a simple ping to check connection status
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkConnectionState()
        }
        #endif
    }
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func checkConnectionState() {
        guard let task = webSocketTask else { return }
        
        switch task.state {
        case .running:
            if !isConnected {
                isConnected = true
                connectedAt = Date()
                reconnectDelay = 1.0 // Reset on successful connection
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.relayConnectionDidConnect(self)
                }
            }
        case .canceling, .completed:
            if isConnected {
                isConnected = false
                connectedAt = nil
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.relayConnectionDidDisconnect(self, error: nil)
                }
            }
        case .suspended:
            // Handle suspended state
            break
        @unknown default:
            break
        }
    }
    #endif
    
    private func handleConnectionError(_ error: Error) {
        isConnected = false
        connectedAt = nil
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        webSocketTask = nil
        #endif
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.relayConnectionDidDisconnect(self, error: error)
        }
        
        // Schedule reconnection
        scheduleReconnection()
    }
    
    private func scheduleReconnection() {
        let delay = min(reconnectDelay, maxReconnectDelay)
        reconnectDelay *= 2
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}