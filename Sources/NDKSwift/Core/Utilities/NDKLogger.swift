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
    /// Current log level
    public static var logLevel: NDKLogLevel = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()
    
    /// Enable/disable network traffic logging
    public static var logNetworkTraffic: Bool = true
    
    /// Enable/disable pretty printing for network messages
    public static var prettyPrintNetworkMessages: Bool = true
    
    /// Categories to log
    public static var enabledCategories: Set<NDKLogCategory> = Set(NDKLogCategory.allCases)
    
    /// Production safety - sanitize sensitive data
    public static var sanitizeSensitiveData: Bool = true
    
    /// Log a message at the specified level
    public static func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String) {
        guard level <= logLevel else { return }
        guard enabledCategories.contains(category) else { return }
        
        let sanitizedMessage = sanitizeSensitiveData ? sanitizeMessage(message) : message
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let emoji = emojiForCategory(category)
        print("[\(timestamp)] [\(category.rawValue)] [\(level)] \(emoji) \(sanitizedMessage)")
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
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = String(format: "%.2f", duration * 1000)
        
        let message = "⏱️ \(operation) completed in \(durationMs)ms"
        if let correlationId = correlationId {
            log(level, category: category, message, correlationId: correlationId)
        } else {
            log(level, category: category, message)
        }
        return result
    }
    
    /// Log performance timing for async operations
    public static func logTiming<T>(_ level: NDKLogLevel, category: NDKLogCategory, operation: String, correlationId: String? = nil, _ block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let durationMs = String(format: "%.2f", duration * 1000)
        
        let message = "⏱️ \(operation) completed in \(durationMs)ms"
        if let correlationId = correlationId {
            log(level, category: category, message, correlationId: correlationId)
        } else {
            log(level, category: category, message)
        }
        return result
    }
    
    // MARK: - Private Helpers
    
    private static func sanitizeMessage(_ message: String) -> String {
        var sanitized = message
        
        // Sanitize potential private keys (64 char hex)
        sanitized = sanitized.replacingOccurrences(
            of: "\\b[a-fA-F0-9]{64}\\b",
            with: "<PRIVATE_KEY>",
            options: .regularExpression
        )
        
        // Sanitize potential secrets and tokens
        let secretPatterns = [
            ("secret=\\w+", "secret=***"),
            ("token=\\w+", "token=***"),
            ("key=\\w+", "key=***"),
            ("password=\\w+", "password=***")
        ]
        
        for (pattern, replacement) in secretPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        return sanitized
    }
    
    private static func emojiForCategory(_ category: NDKLogCategory) -> String {
        switch category {
        case .network: return "📡"
        case .relay: return "🔗"
        case .subscription: return "🔍"
        case .event: return "📝"
        case .cache: return "💾"
        case .auth: return "🔐"
        case .wallet: return "💰"
        case .general: return "ℹ️"
        case .connection: return "🔌"
        case .outbox: return "🎯"
        case .signer: return "✍️"
        case .sync: return "🔄"
        case .performance: return "⚡"
        case .security: return "🛡️"
        case .database: return "🗄️"
        }
    }
    
    /// Log network traffic (special handling)
    public static func logNetworkSend(to relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard logNetworkTraffic else { return }
        
        print("\n📤 SENDING TO \(relay.host ?? relay.absoluteString):")
        
        if prettyPrintNetworkMessages, let parsed = parsed {
            logParsedMessage(parsed)
        }
        
        print("   RAW: \(message)")
    }
    
    /// Log received network traffic
    public static func logNetworkReceive(from relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard logNetworkTraffic else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        
        if prettyPrintNetworkMessages, let parsed = parsed {
            logParsedMessage(parsed)
        }
        
        print("   RAW: \(message)")
    }
    
    /// Log parsing errors
    public static func logNetworkParseError(from relay: URL, message: String, error: Error) {
        guard logNetworkTraffic else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        print("   ❌ PARSE ERROR: \(error)")
        print("   RAW: \(message)")
    }
    
    private static func logParsedMessage(_ message: NostrMessage) {
        switch message {
        case let .event(subscriptionId, event):
            print("   TYPE: EVENT")
            if let subId = subscriptionId {
                print("   SUBSCRIPTION: \(subId)")
            }
            print("   EVENT ID: \(event.id)")
            print("   KIND: \(event.kind)")
            print("   AUTHOR: \(String(event.pubkey.prefix(8)))...")
            if !event.content.isEmpty {
                let preview = event.content.prefix(100)
                print("   CONTENT: \(preview)\(event.content.count > 100 ? "..." : "")")
            }
            
        case let .req(subscriptionId, filters):
            print("   TYPE: REQ")
            print("   SUBSCRIPTION: \(subscriptionId)")
            print("   FILTERS: \(filters.count)")
            for (index, filter) in filters.enumerated() {
                print("     FILTER \(index + 1):")
                if let kinds = filter.kinds, !kinds.isEmpty {
                    print("       KINDS: \(kinds)")
                }
                if let authors = filter.authors, !authors.isEmpty {
                    print("       AUTHORS: \(authors.count) pubkeys")
                }
                if let limit = filter.limit {
                    print("       LIMIT: \(limit)")
                }
                if let since = filter.since {
                    print("       SINCE: \(Date(timeIntervalSince1970: TimeInterval(since)))")
                }
                if let until = filter.until {
                    print("       UNTIL: \(Date(timeIntervalSince1970: TimeInterval(until)))")
                }
            }
            
        case let .close(subscriptionId):
            print("   TYPE: CLOSE")
            print("   SUBSCRIPTION: \(subscriptionId)")
            
        case let .eose(subscriptionId):
            print("   TYPE: EOSE (End of Stored Events)")
            print("   SUBSCRIPTION: \(subscriptionId)")
            
        case let .ok(eventId, accepted, errorMessage):
            print("   TYPE: OK")
            print("   EVENT ID: \(eventId)")
            print("   ACCEPTED: \(accepted)")
            if let msg = errorMessage {
                print("   MESSAGE: \(msg)")
            }
            
        case let .notice(message):
            print("   TYPE: NOTICE")
            print("   MESSAGE: \(message)")
            
        case let .auth(challenge):
            print("   TYPE: AUTH")
            print("   CHALLENGE: \(challenge)")
            
        case let .count(subscriptionId, count):
            print("   TYPE: COUNT")
            print("   SUBSCRIPTION: \(subscriptionId)")
            print("   COUNT: \(count)")
            
        case let .negOpen(subscriptionId, filter, message):
            print("   TYPE: NEG-OPEN")
            print("   SUBSCRIPTION: \(subscriptionId)")
            print("   FILTER: \(filter)")
            print("   MESSAGE: \(message)")
            
        case let .negMsg(subscriptionId, message):
            print("   TYPE: NEG-MSG")
            print("   SUBSCRIPTION: \(subscriptionId)")
            print("   MESSAGE: \(message)")
            
        case let .negClose(subscriptionId):
            print("   TYPE: NEG-CLOSE")
            print("   SUBSCRIPTION: \(subscriptionId)")
            
        case let .negErr(subscriptionId, error):
            print("   TYPE: NEG-ERR")
            print("   SUBSCRIPTION: \(subscriptionId)")
            print("   ERROR: \(error)")
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