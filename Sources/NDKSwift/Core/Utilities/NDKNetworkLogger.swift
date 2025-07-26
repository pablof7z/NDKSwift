import Foundation

/// Network traffic logging for NDK
public enum NDKNetworkLogger {
    /// Log network traffic (special handling)
    public static func logNetworkSend(to relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        let output = "\n📤 SENDING TO \(relay.host ?? relay.absoluteString):\n" +
                     "   RAW: \(NDKLogFormatter.truncateMessage(message))"
        
        if let handler = NDKLogger.logHandler {
            handler(output)
        } else {
            #if DEBUG
            print(output)
            #endif
        }
    }
    
    /// Log received network traffic
    public static func logNetworkReceive(from relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        let output = "\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):\n" +
                     "   RAW: \(NDKLogFormatter.truncateMessage(message))"
        
        if let handler = NDKLogger.logHandler {
            handler(output)
        } else {
            #if DEBUG
            print(output)
            #endif
        }
    }
    
    /// Log parsing errors
    public static func logNetworkParseError(from relay: URL, message: String, error: Error) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }
        
        let output = "\n📥 RECEIVED FROM \(relay.host ?? relay.absoluteString):\n" +
                     "   RAW: \(NDKLogFormatter.truncateMessage(message))\n" +
                     "   ❌ PARSE ERROR: \(error)"
        
        if let handler = NDKLogger.logHandler {
            handler(output)
        } else {
            #if DEBUG
            print(output)
            #endif
        }
    }
    
    /// Log parsed message details
    public static func logParsedMessage(_ message: NostrMessage) {
        var output = ""
        
        switch message {
        case let .event(subscriptionId, event):
            output += "   TYPE: EVENT\n"
            if let subId = subscriptionId {
                output += "   SUBSCRIPTION: \(subId)\n"
            }
            output += "   EVENT ID: \(event.id)\n"
            output += "   KIND: \(event.kind)\n"
            output += "   AUTHOR: \(String(event.pubkey.prefix(8)))...\n"
            if !event.content.isEmpty {
                let preview = event.content.prefix(100)
                output += "   CONTENT: \(preview)\(event.content.count > 100 ? "..." : "")"
            }
            
        case let .req(subscriptionId, filters):
            output += "   TYPE: REQ\n"
            output += "   SUBSCRIPTION: \(subscriptionId)\n"
            output += "   FILTERS: \(filters.count)\n"
            for (index, filter) in filters.enumerated() {
                output += "     FILTER \(index + 1):\n"
                if let kinds = filter.kinds, !kinds.isEmpty {
                    output += "       KINDS: \(kinds)\n"
                }
                if let authors = filter.authors, !authors.isEmpty {
                    output += "       AUTHORS: \(authors.count) pubkeys\n"
                }
                if let limit = filter.limit {
                    output += "       LIMIT: \(limit)\n"
                }
                if let since = filter.since {
                    output += "       SINCE: \(Date(nostrTimestamp: since))\n"
                }
                if let until = filter.until {
                    output += "       UNTIL: \(Date(nostrTimestamp: until))"
                }
            }
            
        case let .close(subscriptionId):
            output += "   TYPE: CLOSE\n"
            output += "   SUBSCRIPTION: \(subscriptionId)"
            
        case let .eose(subscriptionId):
            output += "   TYPE: EOSE (End of Stored Events)\n"
            output += "   SUBSCRIPTION: \(subscriptionId)"
            
        case let .ok(eventId, accepted, errorMessage):
            output += "   TYPE: OK\n"
            output += "   EVENT ID: \(eventId)\n"
            output += "   ACCEPTED: \(accepted)"
            if let msg = errorMessage {
                output += "\n   MESSAGE: \(msg)"
            }
            
        case let .notice(message):
            output += "   TYPE: NOTICE\n"
            output += "   MESSAGE: \(message)"
            
        case let .auth(challenge):
            output += "   TYPE: AUTH\n"
            output += "   CHALLENGE: \(challenge)"
            
        case let .count(subscriptionId, count):
            output += "   TYPE: COUNT\n"
            output += "   SUBSCRIPTION: \(subscriptionId)\n"
            output += "   COUNT: \(count)"
            
        case let .negOpen(subscriptionId, filter, message):
            output += "   TYPE: NEG-OPEN\n"
            output += "   SUBSCRIPTION: \(subscriptionId)\n"
            output += "   FILTER: \(filter)\n"
            output += "   MESSAGE: \(message)"
            
        case let .negMsg(subscriptionId, message):
            output += "   TYPE: NEG-MSG\n"
            output += "   SUBSCRIPTION: \(subscriptionId)\n"
            output += "   MESSAGE: \(message)"
            
        case let .negClose(subscriptionId):
            output += "   TYPE: NEG-CLOSE\n"
            output += "   SUBSCRIPTION: \(subscriptionId)"
            
        case let .negErr(subscriptionId, error):
            output += "   TYPE: NEG-ERR\n"
            output += "   SUBSCRIPTION: \(subscriptionId)\n"
            output += "   ERROR: \(error)"
        }
        
        if let handler = NDKLogger.logHandler {
            handler(output)
        } else {
            #if DEBUG
            print(output)
            #endif
        }
    }
}