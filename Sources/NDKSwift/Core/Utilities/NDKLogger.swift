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
    case general = "GENERAL"
}

/// NDK Logger for configurable logging
public struct NDKLogger {
    /// Shared logger instance
    public static var shared = NDKLogger()
    
    /// Current log level
    public var logLevel: NDKLogLevel = .info
    
    /// Enable/disable network traffic logging
    public var logNetworkTraffic: Bool = true
    
    /// Enable/disable pretty printing for network messages
    public var prettyPrintNetworkMessages: Bool = true
    
    /// Categories to log
    public var enabledCategories: Set<NDKLogCategory> = Set(NDKLogCategory.allCases)
    
    private init() {}
    
    /// Log a message at the specified level
    public func log(_ level: NDKLogLevel, category: NDKLogCategory, _ message: String) {
        guard level <= logLevel else { return }
        guard enabledCategories.contains(category) else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(category.rawValue)] [\(level)] \(message)")
    }
    
    /// Log network traffic (special handling)
    public func logNetworkSend(to relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard logNetworkTraffic else { return }
        
        print("\n📤 SENDING TO \(relay.host ?? relay.absoluteString):")
        
        if prettyPrintNetworkMessages, let parsed = parsed {
            logParsedMessage(parsed)
        }
        
        print("   RAW: \(message)")
    }
    
    /// Log received network traffic
    public func logNetworkReceive(from relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard logNetworkTraffic else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        
        if prettyPrintNetworkMessages, let parsed = parsed {
            logParsedMessage(parsed)
        }
        
        print("   RAW: \(message)")
    }
    
    /// Log parsing errors
    public func logNetworkParseError(from relay: URL, message: String, error: Error) {
        guard logNetworkTraffic else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        print("   ❌ PARSE ERROR: \(error)")
        print("   RAW: \(message)")
    }
    
    private func logParsedMessage(_ message: NostrMessage) {
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