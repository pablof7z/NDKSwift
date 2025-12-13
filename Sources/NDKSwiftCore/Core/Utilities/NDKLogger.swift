import Foundation

// MARK: - Log Entry

/// A single log entry for the developer tools log viewer
public struct NDKLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: NDKLogLevel
    public let category: NDKLogCategory
    public let message: String

    public init(timestamp: Date = Date(), level: NDKLogLevel, category: NDKLogCategory, message: String) {
        id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}

/// A network message for protocol-level debugging
public struct NDKNetworkMessage: Identifiable, Sendable {
    public enum Direction: String, Sendable {
        case inbound = "←"
        case outbound = "→"
    }

    public let id: UUID
    public let timestamp: Date
    public let relay: String
    public let direction: Direction
    public let messageType: String
    public let raw: String

    public init(timestamp: Date = Date(), relay: String, direction: Direction, messageType: String, raw: String) {
        id = UUID()
        self.timestamp = timestamp
        self.relay = relay
        self.direction = direction
        self.messageType = messageType
        self.raw = raw
    }
}

// MARK: - Log Buffer

/// Thread-safe log buffer for the developer tools
public actor NDKLogBuffer {
    public static let shared = NDKLogBuffer()

    private var entries: [NDKLogEntry] = []
    private var networkMessages: [NDKNetworkMessage] = []

    public var maxLogEntries: Int = 1000
    public var maxNetworkMessages: Int = 500

    /// Callback for real-time log updates
    public var onLogEntry: (@Sendable (NDKLogEntry) -> Void)?
    /// Callback for real-time network message updates
    public var onNetworkMessage: (@Sendable (NDKNetworkMessage) -> Void)?

    private init() {}

    public func setOnLogEntry(_ callback: (@Sendable (NDKLogEntry) -> Void)?) {
        onLogEntry = callback
    }

    public func setOnNetworkMessage(_ callback: (@Sendable (NDKNetworkMessage) -> Void)?) {
        onNetworkMessage = callback
    }

    public func addEntry(_ entry: NDKLogEntry) {
        entries.append(entry)
        if entries.count > maxLogEntries {
            entries.removeFirst(entries.count - maxLogEntries)
        }
        onLogEntry?(entry)
    }

    public func addNetworkMessage(_ message: NDKNetworkMessage) {
        networkMessages.append(message)
        if networkMessages.count > maxNetworkMessages {
            networkMessages.removeFirst(networkMessages.count - maxNetworkMessages)
        }
        onNetworkMessage?(message)
    }

    public func getEntries() -> [NDKLogEntry] {
        return entries
    }

    public func getNetworkMessages() -> [NDKNetworkMessage] {
        return networkMessages
    }

    public func getEntries(level: NDKLogLevel? = nil, category: NDKLogCategory? = nil, search: String? = nil) -> [NDKLogEntry] {
        var filtered = entries

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if let category = category {
            filtered = filtered.filter { $0.category == category }
        }

        if let search = search, !search.isEmpty {
            filtered = filtered.filter { $0.message.localizedCaseInsensitiveContains(search) }
        }

        return filtered
    }

    public func getNetworkMessages(relay: String? = nil, direction: NDKNetworkMessage.Direction? = nil, messageType: String? = nil) -> [NDKNetworkMessage] {
        var filtered = networkMessages

        if let relay = relay {
            filtered = filtered.filter { $0.relay == relay }
        }

        if let direction = direction {
            filtered = filtered.filter { $0.direction == direction }
        }

        if let messageType = messageType {
            filtered = filtered.filter { $0.messageType == messageType }
        }

        return filtered
    }

    public func clearLogs() {
        entries.removeAll()
    }

    public func clearNetworkMessages() {
        networkMessages.removeAll()
    }

    public func clearAll() {
        entries.removeAll()
        networkMessages.removeAll()
    }
}

// MARK: - Log Levels

/// Logging levels for NDK
public enum NDKLogLevel: Int, Comparable, Sendable {
    case off = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    case trace = 5

    public static func < (lhs: NDKLogLevel, rhs: NDKLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Categories for NDK logging
public enum NDKLogCategory: String, CaseIterable, Sendable {
    case network = "NETWORK"
    case relay = "RELAY"
    case subscription = "SUBSCRIPTION"
    case event = "EVENT"
    case cache = "CACHE"
    case auth = "AUTH"
    case wallet = "WALLET"
    case general = "GENERAL"

    // New categories for complex areas
    case connection = "CONNECTION" // WebSocket lifecycle, retry logic
    case outbox = "OUTBOX" // Relay selection, scoring, NIP-65
    case signer = "SIGNER" // Signing flows, NWC, Bunker
    case sync = "SYNC" // Negentropy, sync operations
    case performance = "PERFORMANCE" // Timing, throughput, latency
    case security = "SECURITY" // Encryption, key management
    case database = "DATABASE" // SQL operations, migrations
    case signature = "SIGNATURE" // Signature verification
}

/// NDK Logger for configurable logging
public enum NDKLogger {
    /// Current log level
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is acceptable here because:
    /// - Typically set once at app startup, rarely modified during runtime
    /// - Logging is a cross-cutting concern that shouldn't require `await`
    /// - Worst case: a log message uses stale config value (acceptable for logging)
    /// - Standard practice in logging libraries to accept this trade-off
    public nonisolated(unsafe) static var logLevel: NDKLogLevel = {
        #if DEBUG
            return .info
        #else
            return .warning
        #endif
    }()

    /// Enable/disable network traffic logging
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is acceptable here because:
    /// - Typically set once at app startup, rarely modified during runtime
    /// - Logging is a cross-cutting concern that shouldn't require `await`
    /// - Worst case: a log message uses stale config value (acceptable for logging)
    /// - Standard practice in logging libraries to accept this trade-off
    public nonisolated(unsafe) static var logNetworkTraffic: Bool = false

    /// Enable/disable pretty printing for network messages
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is acceptable here because:
    /// - Typically set once at app startup, rarely modified during runtime
    /// - Logging is a cross-cutting concern that shouldn't require `await`
    /// - Worst case: a log message uses stale config value (acceptable for logging)
    /// - Standard practice in logging libraries to accept this trade-off
    public nonisolated(unsafe) static var prettyPrintNetworkMessages: Bool = true

    /// Check if logging is enabled (log level is not off)
    public static var isEnabled: Bool {
        return logLevel != .off
    }

    /// Categories to log - default excludes noisiest categories for better experience
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is acceptable here because:
    /// - Typically set once at app startup, rarely modified during runtime
    /// - Logging is a cross-cutting concern that shouldn't require `await`
    /// - Worst case: a log message uses stale category filter (acceptable for logging)
    /// - Standard practice in logging libraries to accept this trade-off
    public nonisolated(unsafe) static var enabledCategories: Set<NDKLogCategory> = {
        var categories = Set(NDKLogCategory.allCases)
        // Remove noisiest categories by default
        categories.remove(.database)
        categories.remove(.performance)
        return categories
    }()

    /// Configure the logger
    public static func configure(
        logLevel: NDKLogLevel? = nil,
        enabledCategories: Set<NDKLogCategory>? = nil,
        logNetworkTraffic: Bool? = nil
    ) {
        if let level = logLevel {
            self.logLevel = level
        }
        if let categories = enabledCategories {
            self.enabledCategories = categories
        }
        if let traffic = logNetworkTraffic {
            self.logNetworkTraffic = traffic
        }
    }

    /// Custom log handler for external integration
    ///
    /// **Concurrency Safety**: `nonisolated(unsafe)` is acceptable here because:
    /// - Set once at app startup before any logging occurs
    /// - Never modified after initial configuration
    /// - Logging is a cross-cutting concern that shouldn't require `await`
    /// - Standard practice in logging libraries to accept this trade-off
    public nonisolated(unsafe) static var logHandler: ((String) -> Void)?

    /// Log a message at the specified level
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String) {
        guard level <= logLevel else { return }
        guard enabledCategories.contains(category) else { return }

        let now = Date()
        let timestamp = DateFormatters.iso8601.string(from: now)
        let emoji = NDKLogFormatter.emojiForCategory(category)
        let formattedMessage = "[\(timestamp)] [\(category.rawValue)] [\(level)] \(emoji) \(message)"

        // Add to log buffer for developer tools
        let entry = NDKLogEntry(timestamp: now, level: level, category: category, message: message)
        Task { await NDKLogBuffer.shared.addEntry(entry) }

        if let handler = logHandler {
            handler(formattedMessage)
        } else {
            #if DEBUG
                print(formattedMessage)
            #endif
        }
    }

    /// Log a network message for protocol-level debugging
    public static func logNetwork(relay: String, direction: NDKNetworkMessage.Direction, messageType: String, raw: String) {
        guard logNetworkTraffic else { return }

        let message = NDKNetworkMessage(relay: relay, direction: direction, messageType: messageType, raw: raw)
        Task { await NDKLogBuffer.shared.addNetworkMessage(message) }

        // Also log to regular log if network category is enabled
        if enabledCategories.contains(.network) {
            let dirSymbol = direction.rawValue
            log(.debug, category: .network, "\(dirSymbol) [\(relay)] \(messageType)")
        }
    }

    /// Log a message with correlation ID for tracking across components
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String, correlationId: String) {
        let messageWithCorrelation = "[\(correlationId)] \(message)"
        log(level, category: category, messageWithCorrelation)
    }

    /// Log structured data for searchable logs
    public static func logStructured(_ level: NDKLogLevel, category: NDKLogCategory, _ data: [String: Any]) {
        guard level <= logLevel else { return }
        guard enabledCategories.contains(category) else { return }

        let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "<invalid JSON>"
        log(level, category: category, jsonString)
    }

    /// Log performance timing automatically
    public static func logTiming<T>(_ level: NDKLogLevel, category: NDKLogCategory, operation: String, correlationId: String? = nil, _ block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        logTimingResult(startTime: startTime, level: level, category: category, operation: operation, correlationId: correlationId)
        return result
    }

    /// Log performance timing for async operations
    public static func logTiming<T>(_ level: NDKLogLevel, category: NDKLogCategory, operation: String, correlationId: String? = nil, _ block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        logTimingResult(startTime: startTime, level: level, category: category, operation: operation, correlationId: correlationId)
        return result
    }

    // MARK: - Private Helpers

    private static func logTimingResult(startTime: CFAbsoluteTime, level: NDKLogLevel, category: NDKLogCategory, operation: String, correlationId: String?) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = String(format: "%.2f", duration * 1000)
        let message = "⏱️ \(operation) completed in \(durationMs)ms"

        if let correlationId = correlationId {
            log(level, category: category, message, correlationId: correlationId)
        } else {
            log(level, category: category, message)
        }
    }
}

// CaseIterable conformance already added to the enum declaration

// Extension for NDKLogLevel string representation
extension NDKLogLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .off: return "OFF"
        case .error: return "ERROR"
        case .warning: return "WARNING"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .trace: return "TRACE"
        }
    }
}
