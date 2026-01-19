import Foundation
import os

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

    /// Map to os.Logger level
    var osLogType: OSLogType {
        switch self {
        case .off: return .debug // Won't be used when off
        case .error: return .error
        case .warning: return .default
        case .info: return .info
        case .debug: return .debug
        case .trace: return .debug
        }
    }
}

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

// MARK: - Log Categories

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
    case connection = "CONNECTION"
    case outbox = "OUTBOX"
    case signer = "SIGNER"
    case sync = "SYNC"
    case performance = "PERFORMANCE"
    case security = "SECURITY"
    case database = "DATABASE"
    case signature = "SIGNATURE"

    /// Get the os.Logger for this category
    var logger: os.Logger {
        os.Logger(subsystem: "ndk", category: rawValue.lowercased())
    }
}

// MARK: - Logger

/// NDK Logger - synchronous, os.Logger-based logging
public enum NDKLogger {
    private static let lock = OSAllocatedUnfairLock()

    // Thread-safe configuration storage
    nonisolated(unsafe) private static var _level: NDKLogLevel = {
        #if DEBUG
            return .info
        #else
            return .warning
        #endif
    }()

    nonisolated(unsafe) private static var _enabledCategories: Set<NDKLogCategory> = {
        var categories = Set(NDKLogCategory.allCases)
        categories.remove(.database)
        categories.remove(.performance)
        return categories
    }()

    nonisolated(unsafe) private static var _logNetworkTraffic: Bool = false
    nonisolated(unsafe) private static var _handler: (@Sendable (String) -> Void)?

    // MARK: - Configuration

    /// Set the minimum log level
    public static func setLogLevel(_ level: NDKLogLevel) {
        lock.withLock { _level = level }
    }

    /// Get the current log level
    public static var logLevel: NDKLogLevel {
        lock.withLock { _level }
    }

    /// Set enabled categories
    public static func setEnabledCategories(_ categories: Set<NDKLogCategory>) {
        lock.withLock { _enabledCategories = categories }
    }

    /// Get enabled categories
    public static var enabledCategories: Set<NDKLogCategory> {
        lock.withLock { _enabledCategories }
    }

    /// Enable or disable network traffic logging
    public static func setLogNetworkTraffic(_ enabled: Bool) {
        lock.withLock { _logNetworkTraffic = enabled }
    }

    /// Check if network traffic logging is enabled
    public static var logNetworkTraffic: Bool {
        lock.withLock { _logNetworkTraffic }
    }

    /// Set custom log handler (primarily for tests)
    public static func setLogHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.withLock { _handler = handler }
        NDKNetworkLogger.setHandler(handler)
    }

    /// Check if logging is enabled
    public static var isEnabled: Bool {
        lock.withLock { _level != .off }
    }

    /// Configure the logger
    public static func configure(
        logLevel: NDKLogLevel? = nil,
        enabledCategories: Set<NDKLogCategory>? = nil,
        logNetworkTraffic: Bool? = nil
    ) {
        lock.withLock {
            if let level = logLevel {
                _level = level
            }
            if let categories = enabledCategories {
                _enabledCategories = categories
            }
            if let traffic = logNetworkTraffic {
                _logNetworkTraffic = traffic
            }
        }
    }

    // MARK: - Logging

    /// Log a message at the specified level - synchronous, no await needed
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String) {
        let (currentLevel, enabled, handler) = lock.withLock {
            (_level, _enabledCategories.contains(category), _handler)
        }
        guard level.rawValue <= currentLevel.rawValue else { return }
        guard enabled else { return }

        // Primary: os.Logger
        category.logger.log(level: level.osLogType, "\(message, privacy: .public)")

        // Secondary: handler for tests
        if let handler {
            let timestamp = DateFormatters.iso8601.string(from: Date())
            let emoji = NDKLogFormatter.emojiForCategory(category)
            let formattedMessage = "[\(timestamp)] [\(category.rawValue)] [\(level)] \(emoji) \(message)"
            handler(formattedMessage)
        }
    }

    /// Log a message with correlation ID for tracking across components
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String, correlationId: String) {
        log(level, category: category, "[\(correlationId)] \(message)")
    }
}
