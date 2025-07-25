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
/// let openMsg = NIP77Message.open(
///     subscriptionId: "sync-123",
///     filter: NDKFilter(kinds: [1]),
///     initialMessage: negentropyData
/// )
/// let json = try openMsg.toJSON()
/// await relay.send(json)
///
/// // Continue reconciliation
/// let msgResponse = NIP77Message.message(
///     subscriptionId: "sync-123",
///     data: responseData
/// )
/// await relay.send(try msgResponse.toJSON())
/// ```
public struct NIP77Message {
    public let type: NIP77MessageType
    public let subscriptionId: String
    public let data: Data?
    public let filter: NDKFilter?
    public let error: String?

    // MARK: - Constructors

    /// Creates a NEG-OPEN message to initiate synchronization.
    ///
    /// - Parameters:
    ///   - subscriptionId: Unique identifier for this sync session
    ///   - filter: Nostr filter defining which events to synchronize
    ///   - initialMessage: Initial Negentropy reconciliation data
    /// - Returns: NEG-OPEN message ready for transmission
    public static func open(subscriptionId: String, filter: NDKFilter, initialMessage: Data) -> NIP77Message {
        return NIP77Message(
            type: .negOpen,
            subscriptionId: subscriptionId,
            data: initialMessage,
            filter: filter,
            error: nil
        )
    }

    /// Create a NEG-MSG message
    public static func message(subscriptionId: String, data: Data) -> NIP77Message {
        return NIP77Message(
            type: .negMsg,
            subscriptionId: subscriptionId,
            data: data,
            filter: nil,
            error: nil
        )
    }

    /// Create a NEG-CLOSE message
    public static func close(subscriptionId: String) -> NIP77Message {
        return NIP77Message(
            type: .negClose,
            subscriptionId: subscriptionId,
            data: nil,
            filter: nil,
            error: nil
        )
    }

    /// Create a NEG-ERR message
    public static func error(subscriptionId: String, error: String) -> NIP77Message {
        return NIP77Message(
            type: .negErr,
            subscriptionId: subscriptionId,
            data: nil,
            filter: nil,
            error: error
        )
    }

    // MARK: - Encoding

    /// Encode to JSON array format for Nostr
    public func toJSON() throws -> String {
        var array: [Any] = [type.rawValue, subscriptionId]

        switch type {
        case .negOpen:
            if let filter = filter, let data = data {
                array.append(filter.toDictionary())
                array.append(data.hexString)
            }

        case .negMsg:
            if let data = data {
                array.append(data.hexString)
            }

        case .negErr:
            if let error = error {
                array.append(error)
            }

        case .negClose:
            break // No additional data
        }

        let jsonData = try JSONSerialization.data(withJSONObject: array)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    // MARK: - Decoding

    /// Decode from JSON array
    public static func fromJSON(_ json: String) throws -> NIP77Message {
        guard let data = json.data(using: .utf8) else {
            throw NIP77Error.invalidMessage
        }

        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2 else {
            throw NIP77Error.invalidMessage
        }

        guard let typeString = array[0] as? String,
              let messageType = NIP77MessageType(rawValue: typeString),
              let subscriptionId = array[1] as? String else {
            throw NIP77Error.invalidMessage
        }

        switch messageType {
        case .negOpen:
            guard array.count >= 4,
                  let filterDict = array[2] as? [String: Any],
                  let hexData = array[3] as? String,
                  let messageData = hexData.hexDecoded() else {
                throw NIP77Error.invalidMessage
            }

            let filter = try NDKFilter.fromDictionary(filterDict)
            return NIP77Message(
                type: .negOpen,
                subscriptionId: subscriptionId,
                data: messageData,
                filter: filter,
                error: nil
            )

        case .negMsg:
            guard array.count >= 3,
                  let hexData = array[2] as? String,
                  let messageData = hexData.hexDecoded() else {
                throw NIP77Error.invalidMessage
            }

            return NIP77Message(
                type: .negMsg,
                subscriptionId: subscriptionId,
                data: messageData,
                filter: nil,
                error: nil
            )

        case .negErr:
            guard array.count >= 3,
                  let error = array[2] as? String else {
                throw NIP77Error.invalidMessage
            }

            return NIP77Message(
                type: .negErr,
                subscriptionId: subscriptionId,
                data: nil,
                filter: nil,
                error: error
            )

        case .negClose:
            return NIP77Message(
                type: .negClose,
                subscriptionId: subscriptionId,
                data: nil,
                filter: nil,
                error: nil
            )
        }
    }
}

/// NIP-77 specific errors
public enum NIP77Error: LocalizedError {
    case invalidMessage
    case syncFailed(String)
    case relayError(String)
    case unsupportedByRelay
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return ErrorMessageConstants.invalid("NIP-77 message format")
        case .syncFailed(let reason):
            return ErrorMessageConstants.withContext("Sync failed", context: reason)
        case .relayError(let error):
            return ErrorMessageConstants.relayError(relay: "NIP-77", message: error)
        case .unsupportedByRelay:
            return "Relay does not support NIP-77"
        case .timeout(let message):
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
               let values = value as? [String] {
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