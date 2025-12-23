import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Delegate for relay connection events
public protocol NDKRelayConnectionDelegate: AnyObject, Sendable {
    func relayConnection(_ connection: NDKRelayConnection, didReceiveMessage message: NostrMessage)
    func relayConnectionDidConnect(_ connection: NDKRelayConnection)
    func relayConnectionDidDisconnect(_ connection: NDKRelayConnection, error: Error?)
}

/// WebSocket connection to a Nostr relay using actor for thread safety.
///
/// `NDKRelayConnection` manages a WebSocket connection to a single Nostr relay,
/// handling connection lifecycle, message sending/receiving, and automatic
/// reconnection with exponential backoff.
///
/// Example usage:
/// ```swift
/// let connection = NDKRelayConnection(url: URL(string: "wss://relay.example.com")!)
/// connection.delegate = self
/// try await connection.connect()
/// try await connection.send(message: .event(event))
/// ```
public actor NDKRelayConnection {
    private nonisolated let url: URL
    private nonisolated let config: NDKConnectionConfig

    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        private var webSocketTask: URLSessionWebSocketTask?
        // Shared URLSession for all connections (as per Gemini's suggestion)
        private static let sharedURLSession: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = NetworkConstants.timeoutStandardRequest
            config.timeoutIntervalForResource = NetworkConstants.timeoutResource
            config.httpAdditionalHeaders = [
                "User-Agent": "NDKSwift 1.0",
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

    /// Track timeout tasks for pending events
    private var eventTimeoutTasks: [EventID: Task<Void, Never>] = [:]

    /// Health check timer task
    private var healthCheckTask: Task<Void, Never>?

    /// Last successful health check timestamp
    private var lastHealthCheckAt: Date?

    /// WebSocket state monitoring task
    private var stateMonitorTask: Task<Void, Never>?

    public init(url: URL, config: NDKConnectionConfig = .default) {
        self.url = url
        self.config = config
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

    /// Connect to the relay.
    ///
    /// Establishes a WebSocket connection to the relay. If already connected,
    /// this method returns immediately. If a connection attempt is already in
    /// progress, this method waits for that attempt to complete.
    ///
    /// - Throws: `NDKError.connectionFailed` if the connection cannot be established
    ///
    /// - Note: Initial connection failures do not trigger automatic reconnection.
    ///   Only subsequent connection losses will schedule reconnection attempts
    ///   according to the retry policy.
    ///
    /// Example:
    /// ```swift
    /// let connection = NDKRelayConnection(url: relayURL)
    /// do {
    ///     try await connection.connect()
    ///     print("Connected to relay")
    /// } catch {
    ///     print("Connection failed: \(error)")
    /// }
    /// ```
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
        NDKLogger.log(.info, category: .connection, "🔌 Attempting to connect to \(url)")
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
            let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: url.absoluteString, errorType: "connectionFailed")
            if shouldLog {
                NDKLogger.log(.error, category: .connection, "❌ Connection failed to \(url): \(error)")
                if let summary = await connectionErrorRateLimiter.getSuppressedErrorSummary(for: url.absoluteString) {
                    NDKLogger.log(.debug, category: .connection, "📊 \(summary)")
                }
            }
            // For initial connection failures, don't auto-retry (as per Gemini's suggestion)
            if isInitialConnection {
                isInitialConnection = false
                if shouldLog {
                    NDKLogger.log(.debug, category: .connection, "🛑 Initial connection failure - not auto-retrying")
                }
                throw error
            } else {
                // For subsequent failures, schedule reconnection
                if shouldLog {
                    NDKLogger.log(.debug, category: .connection, "🔄 Scheduling reconnection for \(url)")
                }
                await scheduleReconnection()
                throw error
            }
        }
    }

    private func _connect() async {
        guard !isConnected else {
            resumeAllContinuations(with: .success(()))
            return
        }

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard webSocketTask == nil else {
                resumeAllContinuations(with: .success(()))
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
            NDKLogger.log(.info, category: .connection, "Mock WebSocket connection to \(url) (Linux doesn't support WebSockets)")
            isConnected = true
            connectedAt = Date()
            resumeAllContinuations(with: .success(()))

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

        // Stop monitoring tasks
        stopHealthChecks()
        stopStateMonitoring()

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
            await cleanupPendingEvents(error: NDKError.connectionLost(relay: url.absoluteString, message: "Connection closed"))

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

    /// Publish an event and wait for OK response.
    ///
    /// Sends an event to the relay and waits for an OK response to confirm
    /// whether the relay accepted or rejected the event.
    ///
    /// - Parameters:
    ///   - event: The Nostr event to publish
    ///   - timeout: Maximum time to wait for OK response (default: 30 seconds)
    ///
    /// - Returns: `true` if the relay accepted the event, `false` if rejected
    ///
    /// - Throws:
    ///   - `NDKError.timeout` if no OK response is received within the timeout period
    ///   - `NDKError.publishFailed` if the relay rejects the event with an error message
    ///   - `NDKError.connectionLost` if the connection is lost during publishing
    ///
    /// Example:
    /// ```swift
    /// let event = try await eventBuilder.build()
    /// do {
    ///     let accepted = try await connection.publishEvent(event)
    ///     if accepted {
    ///         print("Event published successfully")
    ///     } else {
    ///         print("Event rejected by relay")
    ///     }
    /// } catch {
    ///     print("Failed to publish: \(error)")
    /// }
    /// ```
    public func publishEvent(_ event: NDKEvent, timeout: TimeInterval = NetworkConstants.timeoutRelayConnection) async throws -> Bool {
        // Ensure we're connected first
        if !isConnected {
            try await connect()
        }

        let eventId = event.id
        NDKLogger.log(.debug, category: .network, "publishEvent called for event \(eventId)")

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

        // Create independent timeout task that won't be cancelled if send succeeds
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            guard let self = self else { return }
            await self.handleTimeout(eventId: eventId)
        }
        eventTimeoutTasks[eventId] = timeoutTask

        // Send the event (don't wait for OK here - it will arrive asynchronously)
        do {
            let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
            try await send(eventMessage)
            NDKLogger.log(.debug, category: .network, "Event sent, waiting for OK response...")
        } catch {
            // Cancel timeout and resume with error immediately
            timeoutTask.cancel()
            eventTimeoutTasks.removeValue(forKey: eventId)
            resumePendingEvent(eventId: eventId, with: .failure(error))
        }
    }

    /// Handle timeout for a pending event (actor-isolated)
    private func handleTimeout(eventId: EventID) {
        let error = NDKError.timeout(operation: "publishEvent", seconds: Int(NetworkConstants.timeoutRelayConnection))
        resumePendingEvent(eventId: eventId, with: .failure(error))
    }

    /// Send raw JSON to relay
    public func send(_ json: String) async throws {
        guard isConnected else {
            throw NDKError.connectionLost(relay: url.absoluteString, message: ErrorMessageConstants.Messages.notConnected)
        }

        // Log network traffic
        do {
            let parsed = try NostrMessage.parse(from: json)
            NDKNetworkLogger.logNetworkSend(to: url, message: json, parsed: parsed)
        } catch {
            NDKLogger.log(.warning, category: .network, "Failed to parse outgoing message for logging: \(error)")
            NDKNetworkLogger.logNetworkSend(to: url, message: json, parsed: nil)
        }

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                throw NDKError.connectionLost(relay: url.absoluteString, message: "No WebSocket task")
            }

            let message = URLSessionWebSocketTask.Message.string(json)
            try await task.send(message)
        #else
            // Mock sending for Linux
            NDKLogger.log(.debug, category: .network, "Mock send to \(url): \(json)")
        #endif

        messagesSent += 1
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
                    }
                }
            } catch {
                // Connection closed or error occurred
                let ndkError = mapToNDKError(error, operation: "receive message")
                let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: url.absoluteString, errorType: "receiveError")
                if shouldLog {
                    NDKLogger.log(.error, category: .connection, "🔴 Receive loop ended with error: \(ndkError)")
                }
                await handleConnectionError(ndkError, shouldLog: false) // Don't double-log
            }
        }
    #endif

    private func handleReceivedMessage(_ json: String) async {
        // Validate input
        guard !json.isEmpty else {
            NDKLogger.log(.warning, category: .network, "Received empty message from relay \(url)")
            return
        }

        do {
            let message = try NostrMessage.parse(from: json)

            // Log received message
            NDKNetworkLogger.logNetworkReceive(from: url, message: json, parsed: message)

            // Handle OK messages for pending events
            if case let .ok(eventId, accepted, errorMessage) = message {
                if accepted {
                    resumePendingEvent(eventId: eventId, with: .success(true))
                } else {
                    let error = NDKError.publishFailed(
                        relay: url.absoluteString,
                        message: errorMessage ?? "Event rejected by relay"
                    )
                    resumePendingEvent(eventId: eventId, with: .failure(error))
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
                let error = NDKError.connectionLost(relay: url.absoluteString, message: "No WebSocket task")
                resumeAllContinuations(with: .failure(error))
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
                            let ndkError = await self.mapToNDKError(error, operation: "ping")
                            let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: self.url.absoluteString, errorType: "pingFailed")
                            if shouldLog {
                                NDKLogger.log(.error, category: .connection, "❌ Ping failed for \(self.url): \(ndkError)")
                            }
                            await self.resumeContinuationWithError(ndkError)
                            await self.handleConnectionError(ndkError, shouldLog: false) // Don't double-log
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
                resumeAllContinuations(with: .success(()))
                return
            }

            isConnected = true
            isInitialConnection = false
            connectedAt = Date()
            retryPolicy.reset()

            // Start monitoring tasks
            startHealthChecks()
            startStateMonitoring()

            resumeAllContinuations(with: .success(()))

            // Notify delegate
            await notifyDelegate { delegate in
                delegate.relayConnectionDidConnect(self)
            }
        }

        private func resumeContinuationWithError(_ error: Error) async {
            resumeAllContinuations(with: .failure(error))
        }
    #endif

    private func handleConnectionError(_ error: Error, shouldLog: Bool = true) async {
        if shouldLog {
            let shouldLogError = await connectionErrorRateLimiter.shouldLogError(for: url.absoluteString, errorType: "connectionError")
            if shouldLogError {
                let logLevel: NDKLogLevel = isInitialConnection ? .error : .warning
                NDKLogger.log(logLevel, category: .connection, "🔴 Connection error for \(url): \(error)")
                if let summary = await connectionErrorRateLimiter.getSuppressedErrorSummary(for: url.absoluteString) {
                    NDKLogger.log(.debug, category: .connection, "📊 \(summary)")
                }
            }
        }
        isConnected = false
        connectedAt = nil

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            webSocketTask = nil
        #endif

        // Clean up any pending event continuations to prevent leaks
        await cleanupPendingEvents(error: error)

        await notifyDelegate { delegate in
            delegate.relayConnectionDidDisconnect(self, error: error)
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
                do {
                    try await self.connect()
                } catch {
                    NDKLogger.log(.warning, category: .connection, "Reconnection failed to \(self.url): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Error Handling Helpers

    /// Resume all waiting continuations with result
    private func resumeAllContinuations(with result: Result<Void, Error>) {
        for continuation in connectionContinuations {
            switch result {
            case .success:
                continuation.resume()
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
        connectionContinuations.removeAll()
        isConnecting = false
    }

    /// Resume a pending event continuation with result
    private func resumePendingEvent(eventId: EventID, with result: Result<Bool, Error>) {
        // Cancel and remove the timeout task
        eventTimeoutTasks.removeValue(forKey: eventId)?.cancel()

        // Resume the continuation if it exists
        if let continuation = pendingEvents.removeValue(forKey: eventId) {
            switch result {
            case let .success(value):
                continuation.resume(returning: value)
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }

    /// Clean up pending events with appropriate error
    private func cleanupPendingEvents(error: Error) async {
        let eventIds = Array(pendingEvents.keys)
        let ndkError = mapToNDKError(error, operation: "send event")

        for eventId in eventIds {
            NDKLogger.log(.warning, category: .relay, "⚠️ Failing pending event \(eventId) due to connection error")
            resumePendingEvent(eventId: eventId, with: .failure(ndkError))
        }
    }

    /// Map generic errors to specific NDKError cases
    private func mapToNDKError(_ error: Error, operation: String) -> NDKError {
        // Check if it's already an NDKError
        if let ndkError = error as? NDKError {
            return ndkError
        }

        // Map URLError cases
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return NDKError.timeout(operation: operation, seconds: Int(NetworkConstants.timeoutRelayConnection))
            case .notConnectedToInternet, .networkConnectionLost:
                return NDKError.connectionLost(relay: url.absoluteString, message: urlError.localizedDescription)
            case .cannotConnectToHost, .cannotFindHost:
                return NDKError.connectionFailed(relay: url.absoluteString, message: urlError.localizedDescription, underlying: error)
            default:
                return NDKError.networkError(for: url.absoluteString, operation: operation, error: error)
            }
        }

        // Default to network error
        return NDKError.networkError(for: url.absoluteString, operation: operation, error: error)
    }

    // MARK: - Health Check & State Monitoring

    /// Start periodic health checks
    private func startHealthChecks() {
        guard config.enableHealthChecks else { return }

        // Cancel any existing health check task
        healthCheckTask?.cancel()

        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                // Wait for the configured interval
                try? await Task.sleep(nanoseconds: UInt64(self.config.healthCheckInterval * Double(TimeConstants.nanosecondsPerSecond)))

                guard !Task.isCancelled else { return }

                // Perform health check
                await self.performHealthCheck()
            }
        }
    }

    /// Stop periodic health checks
    private func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    /// Perform a health check
    private func performHealthCheck() async {
        guard isConnected else { return }

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard let task = webSocketTask else {
                NDKLogger.log(.warning, category: .connection, "⚠️ Health check failed - no WebSocket task for \(url)")
                await handleHealthCheckFailure()
                return
            }

            let checkCompleted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                var checkHandled = false

                // Set up timeout
                let timeoutTask = Task { [weak self] in
                    guard let self = self else { return }
                    try? await Task.sleep(nanoseconds: UInt64(self.config.healthCheckTimeout * Double(TimeConstants.nanosecondsPerSecond)))
                    if !checkHandled {
                        checkHandled = true
                        NDKLogger.log(.warning, category: .connection, "⏰ Health check timeout for \(self.url)")
                        continuation.resume(returning: false)
                    }
                }

                task.sendPing { [weak self] error in
                    guard !checkHandled else { return }
                    checkHandled = true
                    timeoutTask.cancel()

                    if let error = error {
                        Task { [weak self] in
                            guard let self = self else { return }
                            NDKLogger.log(.warning, category: .connection, "❌ Health check ping failed for \(self.url): \(error)")
                            continuation.resume(returning: false)
                        }
                    } else {
                        Task { [weak self] in
                            guard let self = self else { return }
                            await self.updateLastHealthCheck()
                            NDKLogger.log(.trace, category: .connection, "✅ Health check passed for \(self.url)")
                            continuation.resume(returning: true)
                        }
                    }
                }
            }

            if !checkCompleted {
                await handleHealthCheckFailure()
            }
        #endif
    }

    /// Update last health check timestamp
    private func updateLastHealthCheck() {
        lastHealthCheckAt = Date()
    }

    /// Handle health check failure
    private func handleHealthCheckFailure() async {
        NDKLogger.log(.error, category: .connection, "🔴 Health check failed for \(url) - reconnecting...")
        let error = NDKError.connectionLost(relay: url.absoluteString, message: "Health check failed")
        await handleConnectionError(error)
    }

    /// Start WebSocket state monitoring
    private func startStateMonitoring() {
        guard config.enableStateMonitoring else { return }

        // Cancel any existing state monitor task
        stateMonitorTask?.cancel()

        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            stateMonitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self = self else { return }

                    // Check WebSocket state every 5 seconds
                    try? await Task.sleep(nanoseconds: UInt64(5 * Double(TimeConstants.nanosecondsPerSecond)))

                    guard !Task.isCancelled else { return }

                    await self.checkWebSocketState()
                }
            }
        #endif
    }

    /// Stop WebSocket state monitoring
    private func stopStateMonitoring() {
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
    }

    /// Check WebSocket task state
    private func checkWebSocketState() async {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
            guard isConnected else { return }

            guard let task = webSocketTask else {
                NDKLogger.log(.warning, category: .connection, "⚠️ Connected but no WebSocket task for \(url)")
                let error = NDKError.connectionLost(relay: url.absoluteString, message: "WebSocket task missing")
                await handleConnectionError(error)
                return
            }

            // Check if the task is in a running state
            switch task.state {
            case .running:
                // All good
                break
            case .suspended:
                NDKLogger.log(.warning, category: .connection, "⚠️ WebSocket task suspended for \(url)")
                task.resume() // Try to resume
            case .canceling, .completed:
                NDKLogger.log(.error, category: .connection, "🔴 WebSocket task no longer running for \(url)")
                let error = NDKError.connectionLost(relay: url.absoluteString, message: "WebSocket task ended")
                await handleConnectionError(error)
            @unknown default:
                NDKLogger.log(.warning, category: .connection, "❓ Unknown WebSocket state for \(url)")
            }
        #endif
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
