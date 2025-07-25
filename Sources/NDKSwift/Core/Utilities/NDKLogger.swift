import Foundation

/// Logging levels for NDK
public enum NDKLogLevel: Int, Comparable {
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
public enum NDKLogCategory: String {
    case network = "NETWORK"
    case relay = "RELAY"
    case subscription = "SUBSCRIPTION"
    case event = "EVENT"
    case cache = "CACHE"
    case auth = "AUTH"
    case wallet = "WALLET"
    case general = "GENERAL"

    // New categories for complex areas
    case connection = "CONNECTION"     // WebSocket lifecycle, retry logic
    case outbox = "OUTBOX"            // Relay selection, scoring, NIP-65
    case signer = "SIGNER"            // Signing flows, NWC, Bunker
    case sync = "SYNC"                // Negentropy, sync operations
    case performance = "PERFORMANCE"   // Timing, throughput, latency
    case security = "SECURITY"        // Encryption, key management
    case database = "DATABASE"        // SQL operations, migrations
}

/// NDK Logger for configurable logging
public enum NDKLogger {
    // MARK: - OUTBOX_DEBUG_HOOK
    /// Disable all logging (for debugging tools)
    public static var isEnabled: Bool = true
    
    /// Current log level
    public static var logLevel: NDKLogLevel = {
        #if DEBUG
        return .info
        #else
        return .warning
        #endif
    }()

    /// Enable/disable network traffic logging
    public static var logNetworkTraffic: Bool = false

    /// Enable/disable pretty printing for network messages
    public static var prettyPrintNetworkMessages: Bool = true

    /// Categories to log - default excludes noisiest categories for better experience
    public static var enabledCategories: Set<NDKLogCategory> = {
        var categories = Set(NDKLogCategory.allCases)
        // Remove noisiest categories by default
        categories.remove(.database)
        categories.remove(.performance)
        return categories
    }()

    /// Log a message at the specified level
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String) {
        // MARK: - OUTBOX_DEBUG_HOOK
        guard isEnabled else { return }
        guard level <= logLevel else { return }
        guard enabledCategories.contains(category) else { return }

        let timestamp = DateFormatters.iso8601.string(from: Date())
        let emoji = NDKLogFormatter.emojiForCategory(category)
        print("[\(timestamp)] [\(category.rawValue)] [\(level)] \(emoji) \(message)")
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

// Extension to make NDKLogCategory conform to CaseIterable
extension NDKLogCategory: CaseIterable {}

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