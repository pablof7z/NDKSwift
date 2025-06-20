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

    /// Retry policy for reconnection
    private let retryPolicy = RetryPolicy(configuration: .relayConnection)

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
        retryPolicy.cancel()
        retryPolicy.reset()

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
            throw NDKError.network("connection_failed", "Not connected")
        }

        #if DEBUG
        if json.hasPrefix("[\"REQ\"") {
            print("🔌 \(url): \(json)")
        }
        #endif

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                throw NDKError.network("connection_failed", "No WebSocket task")
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
                case let .success(message):
                    self.messagesReceived += 1

                    switch message {
                    case let .string(json):
                        self.handleReceivedMessage(json)
                    case let .data(data):
                        if let json = String(data: data, encoding: .utf8) {
                            self.handleReceivedMessage(json)
                        }
                    @unknown default:
                        break
                    }

                    // Continue receiving
                    self.receiveMessage()

                case let .failure(error):
                    self.handleConnectionError(error)
                }
            }
        }
    #endif

    private func handleReceivedMessage(_ json: String) {
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
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.relayConnection(self, didReceiveMessage: message)
            }
        } catch {
            // Log parsing error but continue
            print("❌ Failed to parse message from \(url): \(error)")
            print("   Raw JSON: \(json)")
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
                    retryPolicy.reset() // Reset on successful connection

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
        retryPolicy.scheduleRetry { [weak self] in
            self?.connect()
        }
    }
}
