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
    
    // MARK: - OUTBOX_DEBUG_HOOK
    /// Hook for monitoring relay activity (for debugging tools)
    public typealias RelayActivityHook = (URL, RelayActivityEvent) async -> Void
    public enum RelayActivityEvent {
        case connected
        case disconnected(Error?)
        case messageSent(String)
        case messageReceived(String)
        case eventPublished(EventID, Bool, String?)
    }
    private static var activityHook: RelayActivityHook?
    
    public static func setActivityHook(_ hook: RelayActivityHook?) {
        activityHook = hook
    }

    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        private var webSocketTask: URLSessionWebSocketTask?
        // Shared URLSession for all connections (as per Gemini's suggestion)
        private static let sharedURLSession: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = NetworkConstants.timeoutStandardRequest
            config.timeoutIntervalForResource = NetworkConstants.timeoutResource
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

    /// Track if connection is in progress
    private var isConnecting = false

    /// Track if this is an initial connection attempt
    private var isInitialConnection = true

    /// Track pending EVENT messages waiting for OK responses
    private var pendingEvents: [EventID: CheckedContinuation<Bool, Error>] = [:]

    public init(url: URL) {
        self.url = url
        NDKLogger.log(.debug, category: .connection, "🆕 NDKRelayConnection initialized for \(url)")
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
        guard !isConnected else {
            NDKLogger.log(.trace, category: .connection, "✔️ Already connected to \(url)")
            return
        }

        // If there's already a connection attempt in progress, wait for it
        if isConnecting {
            NDKLogger.log(.debug, category: .connection, "🔃 Connection already in progress for \(url) - waiting...")
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuations.append(continuation)
            }
            return
        }

        // Mark that we're connecting
        isConnecting = true

        do {
            try await withCheckedThrowingContinuation { continuation in
                self.connectionContinuations.append(continuation)

                Task {
                    await self._connect()
                }
            }
            NDKLogger.log(.info, category: .connection, "✅ Successfully connected to \(url)")
        } catch {
            isConnecting = false
            NDKLogger.log(.error, category: .connection, "❌ Connection failed to \(url): \(error)")
            // For initial connection failures, don't auto-retry (as per Gemini's suggestion)
            if isInitialConnection {
                isInitialConnection = false
                NDKLogger.log(.debug, category: .connection, "🛑 Initial connection failure - not auto-retrying")
                throw error
            } else {
                // For subsequent failures, schedule reconnection
                NDKLogger.log(.debug, category: .connection, "🔄 Scheduling reconnection for \(url)")
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
            isConnecting = false
            return
        }

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard webSocketTask == nil else {
                // Resume all waiting continuations
                for continuation in connectionContinuations {
                    continuation.resume()
                }
                connectionContinuations.removeAll()
                isConnecting = false
                return
            }


            // Create WebSocket request
            var request = URLRequest(url: url)
            request.addValue(HTTPConstants.webSocketProtocolNostr, forHTTPHeaderField: HTTPConstants.headerSecWebSocketProtocol)
            NDKLogger.log(.trace, category: .connection, "📦 Request headers: Sec-WebSocket-Protocol: \(HTTPConstants.webSocketProtocolNostr)")

            // Create WebSocket task
            webSocketTask = Self.sharedURLSession.webSocketTask(with: request)
            webSocketTask?.resume()


            // Start receiving messages in a detached task so it doesn't block
            Task.detached { [weak self] in
                await self?.receiveMessages()
            }

            // Send a ping to verify connection is established
            await sendPing()
        #else
            // Mock connection for Linux
            NDKLogger.log(.info, category: .relay, "Mock WebSocket connection to \(url) (Linux doesn't support WebSockets)")
            isConnected = true
            connectedAt = Date()
            // Resume all waiting continuations
            for continuation in connectionContinuations {
                continuation.resume()
            }
            connectionContinuations.removeAll()
            isConnecting = false

            await notifyDelegate { delegate in
                delegate.relayConnectionDidConnect(self)
            }
        #endif
    }

    /// Disconnect from relay
    public func disconnect() async {
        NDKLogger.log(.info, category: .connection, "🔌 Disconnecting from \(url)")
        retryPolicy.cancel()
        retryPolicy.reset()

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            if let task = webSocketTask {
                NDKLogger.log(.debug, category: .connection, "🚪 Closing WebSocket connection")
                task.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
            }
        #endif

        if isConnected {
            isConnected = false
            connectedAt = nil

            // Clean up any pending event continuations to prevent leaks
            for (eventId, continuation) in pendingEvents {
                NDKLogger.log(.warning, category: .relay, "⚠️ Cancelling pending event \(eventId) due to disconnect")
                continuation.resume(throwing: NDKError.connectionLost(relay: url.absoluteString, message: "Connection closed"))
            }
            pendingEvents.removeAll()

            NDKLogger.log(.info, category: .connection, "✅ Disconnected from \(url)")
            await notifyDelegate { delegate in
                delegate.relayConnectionDidDisconnect(self, error: nil)
            }
        } else {
            NDKLogger.log(.trace, category: .connection, "📡 Already disconnected from \(url)")
        }
    }

    // MARK: - Message Handling

    /// Send a message to the relay
    public func send(_ message: NostrMessage) async throws {
        let json = try message.serialize()
        try await send(json)
    }

    /// Publish an event and wait for OK response
    public func publishEvent(_ event: NDKEvent, timeout: TimeInterval = NetworkConstants.timeoutRelayConnection) async throws -> Bool {
        // Ensure we're connected first
        if !isConnected {
            try await connect()
        }

        let eventId = event.id
        NDKLogger.log(.debug, category: .relay, "publishEvent called for event \(eventId)")

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
                NDKLogger.log(.debug, category: .relay, "Event sent, waiting for OK response...")
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
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
            continuation.resume(throwing: NDKError.timeout(operation: "publishEvent", seconds: Int(NetworkConstants.timeoutRelayConnection)))
        }
    }

    /// Send raw JSON to relay
    public func send(_ json: String) async throws {
        guard isConnected else {
            throw NDKError.connectionLost(relay: url.absoluteString, message: ErrorMessageConstants.Messages.notConnected)
        }

        // Log network traffic
        let parsed = try? NostrMessage.parse(from: json)
        NDKNetworkLogger.logNetworkSend(to: url, message: json, parsed: parsed)

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                throw NDKError.connectionLost(relay: url.absoluteString, message: "No WebSocket task")
            }

            let message = URLSessionWebSocketTask.Message.string(json)
            try await task.send(message)
        #else
            // Mock sending for Linux
            NDKLogger.log(.debug, category: .relay, "Mock send to \(url): \(json)")
        #endif

        messagesSent += 1
        
        // MARK: - OUTBOX_DEBUG_HOOK
        if let hook = Self.activityHook {
            await hook(url, .messageSent(json))
        }
    }

    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func receiveMessages() async {
        guard let task = webSocketTask else {
            NDKLogger.log(.error, category: .connection, "❌ \(ErrorMessageConstants.Messages.notConnected) - WebSocket task not available for receiving messages")
            return
        }


        do {
            while true {
                let message = try await task.receive()
                messagesReceived += 1
                NDKLogger.log(.trace, category: .connection, "📥 Received message #\(messagesReceived) from \(url)")

                switch message {
                case let .string(json):
                    await handleReceivedMessage(json)
                case let .data(data):
                    if let json = String(data: data, encoding: .utf8) {
                        NDKLogger.log(.trace, category: .connection, "🔄 Converted data message to string")
                        await handleReceivedMessage(json)
                    } else {
                        NDKLogger.log(.warning, category: .connection, "⚠️ Failed to convert data message to UTF-8 string")
                    }
                @unknown default:
                    NDKLogger.log(.warning, category: .connection, "❓ Received unknown message type")
                    break
                }
            }
        } catch {
            // Connection closed or error occurred
            NDKLogger.log(.error, category: .connection, "🔴 Receive loop ended with error: \(error)")
            await handleConnectionError(error)
        }
    }
    #endif

    private func handleReceivedMessage(_ json: String) async {
        // MARK: - OUTBOX_DEBUG_HOOK
        if let hook = Self.activityHook {
            await hook(url, .messageReceived(json))
        }
        
        // Validate input
        guard !json.isEmpty else {
            NDKLogger.log(.warning, category: .relay, "Received empty message from relay \(url)")
            return
        }

        do {
            let message = try NostrMessage.parse(from: json)

            // Log received message
            NDKNetworkLogger.logNetworkReceive(from: url, message: json, parsed: message)

            // Handle OK messages for pending events
            if case let .ok(eventId, accepted, errorMessage) = message {
                // MARK: - OUTBOX_DEBUG_HOOK
                if let hook = Self.activityHook {
                    await hook(url, .eventPublished(eventId, accepted, errorMessage))
                }
                
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
            NDKNetworkLogger.logNetworkParseError(from: url, message: json, error: error)
        }
    }

    // MARK: - Connection Verification

    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func sendPing() async {
        guard let task = webSocketTask else {
            NDKLogger.log(.error, category: .connection, "❌ No WebSocket task for \(url) - cannot send ping")
            // Resume all waiting continuations with error
            for continuation in connectionContinuations {
                continuation.resume(throwing: NDKError.connectionLost(relay: url.absoluteString, message: "No WebSocket task"))
            }
            connectionContinuations.removeAll()
            isConnecting = false
            return
        }


        // Use a single task with timeout built-in
        let pingCompleted = await withCheckedContinuation { continuation in
            var pingHandled = false

            // Set up timeout
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(NetworkConstants.timeoutPing * Double(TimeConstants.nanosecondsPerSecond)))
                if !pingHandled {
                    pingHandled = true
                    NDKLogger.log(.error, category: .connection, "⏰ Ping timeout for \(url) after \(Int(NetworkConstants.timeoutPing)) seconds")
                    continuation.resume(returning: false)
                }
            }

            task.sendPing { [weak self] error in
                guard !pingHandled else { return } // Ignore if timeout already fired
                pingHandled = true
                timeoutTask.cancel()

                Task { [weak self] in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }

                    if let error = error {
                        NDKLogger.log(.error, category: .connection, "❌ Ping failed for \(self.url): \(error)")
                        await self.resumeContinuationWithError(error)
                        await self.handleConnectionError(error)
                        continuation.resume(returning: false)
                    } else {
                        await self.markAsConnected()
                        continuation.resume(returning: true)
                    }
                }
            }
        }

        if !pingCompleted {
            let timeoutError = NDKError.timeout(operation: "ping", seconds: Int(NetworkConstants.timeoutPing))
            await resumeContinuationWithError(timeoutError)
            await handleConnectionError(timeoutError)
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


        // Resume all waiting continuations
        for continuation in connectionContinuations {
            continuation.resume()
        }
        connectionContinuations.removeAll()
        isConnecting = false

        // Notify delegate
        await notifyDelegate { delegate in
            delegate.relayConnectionDidConnect(self)
        }
        
        // MARK: - OUTBOX_DEBUG_HOOK
        if let hook = Self.activityHook {
            await hook(url, .connected)
        }
    }

    private func resumeContinuationWithError(_ error: Error) async {
        // Resume all waiting continuations with error
        for continuation in connectionContinuations {
            continuation.resume(throwing: error)
        }
        connectionContinuations.removeAll()
        isConnecting = false
    }
    #endif

    private func handleConnectionError(_ error: Error) async {
        NDKLogger.log(.error, category: .connection, "🔴 Connection error for \(url): \(error)")
        isConnected = false
        connectedAt = nil

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            webSocketTask = nil
        #endif

        // Clean up any pending event continuations to prevent leaks
        for (eventId, continuation) in pendingEvents {
            NDKLogger.log(.warning, category: .relay, "⚠️ Failing pending event \(eventId) due to connection error")
            continuation.resume(throwing: NDKError.networkError(for: url.absoluteString, operation: "send event", error: error))
        }
        pendingEvents.removeAll()

        await notifyDelegate { delegate in
            delegate.relayConnectionDidDisconnect(self, error: error)
        }
        
        // MARK: - OUTBOX_DEBUG_HOOK
        if let hook = Self.activityHook {
            await hook(url, .disconnected(error))
        }

        // Only schedule reconnection if this wasn't an initial connection attempt
        if !isInitialConnection {
            NDKLogger.log(.debug, category: .connection, "🔁 Will attempt reconnection (not initial connection)")
            await scheduleReconnection()
        } else {
            NDKLogger.log(.debug, category: .connection, "🚫 Not scheduling reconnection (initial connection failed)")
        }
    }

    private func scheduleReconnection() async {
        NDKLogger.log(.debug, category: .connection, "🕒 Scheduling reconnection for \(url) with retry policy")
        // Use a detached task to avoid blocking on retry scheduling
        // This prevents continuation leaks when disconnect cancels the retry
        retryPolicy.scheduleRetry { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                NDKLogger.log(.info, category: .connection, "🔄 Attempting reconnection to \(self.url)")
                try? await self.connect()
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