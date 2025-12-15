import Foundation
import os

/// Network traffic logging for NDK - synchronous, no Tasks
public enum NDKNetworkLogger {
    private static let logger = os.Logger(subsystem: "ndk", category: "network-traffic")

    /// Log network traffic being sent
    public static func logNetworkSend(to relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }

        let host = relay.host ?? relay.absoluteString
        let output = "\n📤 SENDING TO \(host):\n" +
            "   RAW: \(NDKLogFormatter.truncateMessage(message))"

        logger.debug("\(output, privacy: .public)")

        if let handler = getHandler() {
            handler(output)
        }
    }

    /// Log received network traffic
    public static func logNetworkReceive(from relay: URL, message: String, parsed: NostrMessage? = nil) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }

        let host = relay.host ?? relay.absoluteString
        let output = "\n📥 RECEIVED FROM \(host):\n" +
            "   RAW: \(NDKLogFormatter.truncateMessage(message))"

        logger.debug("\(output, privacy: .public)")

        if let handler = getHandler() {
            handler(output)
        }
    }

    /// Log parsing errors
    public static func logNetworkParseError(from relay: URL, message: String, error: Error) {
        guard NDKLogger.logNetworkTraffic else { return }
        guard NDKLogger.isEnabled else { return }

        let host = relay.host ?? relay.absoluteString
        let output = "\n📥 RECEIVED FROM \(host):\n" +
            "   RAW: \(NDKLogFormatter.truncateMessage(message))\n" +
            "   ❌ PARSE ERROR: \(error)"

        logger.error("\(output, privacy: .public)")

        if let handler = getHandler() {
            handler(output)
        }
    }

    /// Log parsed message details
    public static func logParsedMessage(_ message: NostrMessage) {
        guard NDKLogger.logNetworkTraffic else { return }

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

        logger.debug("\(output, privacy: .public)")

        if let handler = getHandler() {
            handler(output)
        }
    }

    // MARK: - Handler

    private static let handlerLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (String) -> Void)?

    private static func getHandler() -> (@Sendable (String) -> Void)? {
        handlerLock.withLock { _handler }
    }

    /// Set the network log handler (called by NDKLogger.setLogHandler)
    internal static func setHandler(_ handler: (@Sendable (String) -> Void)?) {
        handlerLock.withLock { _handler = handler }
    }
}
