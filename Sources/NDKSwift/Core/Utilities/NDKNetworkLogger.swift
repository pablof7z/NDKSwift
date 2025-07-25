import Foundation

/// Network traffic logging for NDK
public enum NDKNetworkLogger {
    /// Log network traffic (special handling)
    public static func logNetworkSend(to relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        print("\n📤 SENDING TO \(relay.host ?? relay.absoluteString):")
        
        // Always show raw message, with truncation for large arrays
        let truncatedMessage = NDKLogFormatter.truncateMessage(message)
        print("   RAW: \(truncatedMessage)")
    }
    
    /// Log received network traffic
    public static func logNetworkReceive(from relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        
        // Always show raw message, with truncation for large arrays
        let truncatedMessage = NDKLogFormatter.truncateMessage(message)
        print("   RAW: \(truncatedMessage)")
    }
    
    /// Log parsing errors
    public static func logNetworkParseError(from relay: URL, message: String, error: Error) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        print("\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):")
        print("   RAW: \(NDKLogFormatter.truncateMessage(message))")
        print("   ❌ PARSE ERROR: \(error)")
    }
    
    /// Log parsed message details
    public static func logParsedMessage(_ message: NostrMessage) {
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
                    print("       SINCE: \(Date(nostrTimestamp: since))")
                }
                if let until = filter.until {
                    print("       UNTIL: \(Date(nostrTimestamp: until))")
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