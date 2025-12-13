import Foundation

/// NIP-77 message types for Negentropy synchronization over Nostr.
///
/// These message types implement the Nostr Negentropy Protocol (NIP-77)
/// for efficient event synchronization between clients and relays.
public enum NIP77MessageType: String {
    case negOpen = "NEG-OPEN"
    case negMsg = "NEG-MSG"
    case negClose = "NEG-CLOSE"
    case negErr = "NEG-ERR"
}

/// NIP-77 message structure for Negentropy protocol over Nostr.
///
/// Represents messages exchanged between clients and relays during Negentropy
/// synchronization sessions as defined in NIP-77.
///
/// ## Protocol Flow
///
/// 1. **NEG-OPEN**: Client initiates sync with filter and initial Negentropy data
/// 2. **NEG-MSG**: Bidirectional exchange of reconciliation messages
/// 3. **NEG-CLOSE**: Clean termination of sync session
/// 4. **NEG-ERR**: Error reporting and recovery
///
/// ## Usage
///
/// ```swift
/// // Start a sync session
/// let openMsg = NIP77Message.negOpen(
///     subscriptionId: "sync-123",
///     filter: NDKFilter(kinds: [1]),
///     initialMessage: negentropyData.hexString
/// )
/// let json = try openMsg.toJSON()
/// await relay.send(json)
///
/// // Continue reconciliation
/// let msgResponse = NIP77Message.negMsg(
///     subscriptionId: "sync-123",
///     message: responseData.hexString
/// )
/// await relay.send(try msgResponse.toJSON())
/// ```
public struct NIP77Message {
    // MARK: - Properties

    public let messageType: NIP77MessageType
    public let subscriptionId: String
    public let filter: NDKFilter?
    public let initialMessage: String?
    public let message: String?
    public let reason: String?

    // MARK: - Constructors

    /// Creates a NEG-OPEN message to initiate synchronization.
    ///
    /// - Parameters:
    ///   - subscriptionId: Unique identifier for this sync session
    ///   - filter: Nostr filter defining which events to synchronize
    ///   - initialMessage: Initial Negentropy reconciliation data as hex string
    /// - Returns: NEG-OPEN message ready for transmission
    public static func negOpen(subscriptionId: String, filter: NDKFilter, initialMessage: String) -> NIP77Message {
        return NIP77Message(
            messageType: .negOpen,
            subscriptionId: subscriptionId,
            filter: filter,
            initialMessage: initialMessage,
            message: nil,
            reason: nil
        )
    }

    /// Creates a NEG-MSG message for continuing synchronization.
    ///
    /// - Parameters:
    ///   - subscriptionId: Unique identifier for this sync session
    ///   - message: Negentropy reconciliation data as hex string
    /// - Returns: NEG-MSG message ready for transmission
    public static func negMsg(subscriptionId: String, message: String) -> NIP77Message {
        return NIP77Message(
            messageType: .negMsg,
            subscriptionId: subscriptionId,
            filter: nil,
            initialMessage: nil,
            message: message,
            reason: nil
        )
    }

    /// Creates a NEG-CLOSE message to terminate synchronization.
    ///
    /// - Parameters:
    ///   - subscriptionId: Unique identifier for the sync session to close
    /// - Returns: NEG-CLOSE message ready for transmission
    public static func negClose(subscriptionId: String) -> NIP77Message {
        return NIP77Message(
            messageType: .negClose,
            subscriptionId: subscriptionId,
            filter: nil,
            initialMessage: nil,
            message: nil,
            reason: nil
        )
    }

    /// Creates a NEG-ERR message to report an error.
    ///
    /// - Parameters:
    ///   - subscriptionId: Unique identifier for this sync session
    ///   - reason: Human-readable error description
    /// - Returns: NEG-ERR message ready for transmission
    public static func negErr(subscriptionId: String, reason: String) -> NIP77Message {
        return NIP77Message(
            messageType: .negErr,
            subscriptionId: subscriptionId,
            filter: nil,
            initialMessage: nil,
            message: nil,
            reason: reason
        )
    }

    // MARK: - Encoding

    /// Encode to JSON array format for Nostr
    public func toJSON() throws -> Any {
        var array: [Any] = [messageType.rawValue, subscriptionId]

        switch messageType {
        case .negOpen:
            if let filter = filter, let initialMessage = initialMessage {
                array.append(filter.toDictionary())
                array.append(initialMessage)
            } else {
                throw NIP77Error.missingRequiredField("filter or initialMessage")
            }

        case .negMsg:
            if let message = message {
                array.append(message)
            } else {
                throw NIP77Error.missingRequiredField("message")
            }

        case .negErr:
            if let reason = reason {
                array.append(reason)
            } else {
                throw NIP77Error.missingRequiredField("reason")
            }

        case .negClose:
            break // No additional data
        }

        return array
    }

    // MARK: - Decoding

    /// Parse from JSON array
    public static func parse(from json: Any) throws -> NIP77Message {
        guard let array = json as? [Any], array.count >= 2 else {
            throw NIP77Error.invalidMessageFormat("Expected array with at least 2 elements")
        }

        guard let typeString = array[0] as? String,
              let messageType = NIP77MessageType(rawValue: typeString)
        else {
            throw NIP77Error.invalidMessageType(String(describing: array[0]))
        }

        guard let subscriptionId = array[1] as? String else {
            throw NIP77Error.invalidMessageFormat("Missing subscription ID")
        }

        switch messageType {
        case .negOpen:
            guard array.count >= 4,
                  let filterDict = array[2] as? [String: Any],
                  let initialMessage = array[3] as? String
            else {
                throw NIP77Error.missingRequiredField("filter or initialMessage")
            }

            let filter = try NDKFilter.fromDictionary(filterDict)
            return NIP77Message(
                messageType: .negOpen,
                subscriptionId: subscriptionId,
                filter: filter,
                initialMessage: initialMessage,
                message: nil,
                reason: nil
            )

        case .negMsg:
            guard array.count >= 3,
                  let message = array[2] as? String
            else {
                throw NIP77Error.missingRequiredField("message")
            }

            return NIP77Message(
                messageType: .negMsg,
                subscriptionId: subscriptionId,
                filter: nil,
                initialMessage: nil,
                message: message,
                reason: nil
            )

        case .negErr:
            guard array.count >= 3,
                  let reason = array[2] as? String
            else {
                throw NIP77Error.missingRequiredField("reason")
            }

            return NIP77Message(
                messageType: .negErr,
                subscriptionId: subscriptionId,
                filter: nil,
                initialMessage: nil,
                message: nil,
                reason: reason
            )

        case .negClose:
            return NIP77Message(
                messageType: .negClose,
                subscriptionId: subscriptionId,
                filter: nil,
                initialMessage: nil,
                message: nil,
                reason: nil
            )
        }
    }
}

/// NIP-77 specific errors
public enum NIP77Error: LocalizedError {
    case invalidMessageType(String)
    case invalidMessageFormat(String)
    case missingRequiredField(String)
    case syncFailed(String)
    case relayError(String)
    case unsupportedByRelay
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidMessageType(type):
            return "Invalid NIP-77 message type: \(type)"
        case let .invalidMessageFormat(reason):
            return "Invalid NIP-77 message format: \(reason)"
        case let .missingRequiredField(field):
            return "Missing required field: \(field)"
        case let .syncFailed(reason):
            return "Negentropy sync failed: \(reason)"
        case let .relayError(error):
            return ErrorMessageConstants.relayError(relay: "NIP-77", message: error)
        case .unsupportedByRelay:
            return "Relay does not support NIP-77"
        case let .timeout(message):
            return ErrorMessageConstants.withContext(ErrorMessageConstants.Messages.timeout, context: message)
        }
    }
}

// Extension for NDKFilter to support dictionary conversion
extension NDKFilter {
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let ids = ids {
            dict["ids"] = ids
        }
        if let authors = authors {
            dict["authors"] = authors
        }
        if let kinds = kinds {
            dict["kinds"] = kinds
        }
        if let since = since {
            dict["since"] = since
        }
        if let until = until {
            dict["until"] = until
        }
        if let tags = tags {
            var tagDict: [String: [String]] = [:]
            for (key, values) in tags {
                tagDict["#\(key)"] = Array(values)
            }
            dict.merge(tagDict) { _, new in new }
        }
        if let limit = limit {
            dict["limit"] = limit
        }

        return dict
    }

    static func fromDictionary(_ dict: [String: Any]) throws -> NDKFilter {
        var filter = NDKFilter()

        if let ids = dict["ids"] as? [String] {
            filter.ids = ids
        }
        if let authors = dict["authors"] as? [String] {
            filter.authors = authors
        }
        if let kinds = dict["kinds"] as? [Int] {
            filter.kinds = kinds
        }
        if let since = dict["since"] as? Int64 {
            filter.since = Timestamp(since)
        }
        if let until = dict["until"] as? Int64 {
            filter.until = Timestamp(until)
        }
        if let limit = dict["limit"] as? Int {
            filter.limit = limit
        }

        // Parse tags
        var tags: [String: Set<String>] = [:]
        for (key, value) in dict {
            if key.hasPrefix("#"), key.count > 1,
               let values = value as? [String]
            {
                let tagName = String(key.dropFirst())
                tags[tagName] = Set(values)
            }
        }

        // Create filter with tags if needed
        if !tags.isEmpty {
            filter = NDKFilter(
                ids: filter.ids,
                authors: filter.authors,
                kinds: filter.kinds,
                events: nil,
                pubkeys: nil,
                since: filter.since,
                until: filter.until,
                limit: filter.limit,
                tags: tags
            )
        }

        return filter
    }
}
