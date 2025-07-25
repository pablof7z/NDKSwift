
/// Nostr message types
public enum NostrMessageType: String {
    case event = "EVENT"
    case req = "REQ"
    case close = "CLOSE"
    case notice = "NOTICE"
    case eose = "EOSE"
    case ok = "OK"
    case auth = "AUTH"
    case count = "COUNT"
    // NIP-77 Negentropy messages
    case negOpen = "NEG-OPEN"
    case negMsg = "NEG-MSG"
    case negClose = "NEG-CLOSE"
    case negErr = "NEG-ERR"
}

/// Nostr message protocol
public enum NostrMessage {
    case event(subscriptionId: String?, event: NDKEvent)
    case req(subscriptionId: String, filters: [NDKFilter])
    case close(subscriptionId: String)
    case notice(message: String)
    case eose(subscriptionId: String)
    case ok(eventId: EventID, accepted: Bool, message: String?)
    case auth(challenge: String)
    case count(subscriptionId: String, count: Int)
    // NIP-77 Negentropy messages
    case negOpen(subscriptionId: String, filter: NDKFilter, message: String)
    case negMsg(subscriptionId: String, message: String)
    case negClose(subscriptionId: String)
    case negErr(subscriptionId: String, error: String)

    // MARK: - Helper Functions

    /// Create an invalid message error with consistent formatting
    private static func invalidMessageError(for messageType: String) -> NDKError {
        return .invalidMessage(ErrorMessageConstants.invalid("\(messageType) message"))
    }

    /// Parse a message from relay
    public static func parse(from json: String) throws -> NostrMessage {
        let array = try JSONCoding.parseArray(from: json)
        guard !array.isEmpty else {
            throw NDKError.parseError(for: "Nostr message", details: "Empty array")
        }

        guard let typeString = array[0] as? String,
              let type = NostrMessageType(rawValue: typeString)
        else {
            throw NDKError.parseError(for: "Nostr message type", details: "Unknown message type: \(array[0])")
        }

        switch type {
        case .event:
            guard array.count >= 2 else {
                throw invalidMessageError(for: "EVENT")
            }

            let subscriptionId = array.count > 2 ? array[1] as? String : nil
            let eventIndex = subscriptionId != nil ? 2 : 1

            guard let eventDict = array[eventIndex] as? [String: Any] else {
                throw NDKError.parseError(for: "EVENT message", details: ErrorMessageConstants.invalid("event data structure"))
            }

            let event = try JSONCoding.decodeFromDictionary(NDKEvent.self, from: eventDict)

            return .event(subscriptionId: subscriptionId, event: event)

        case .req:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String
            else {
                throw invalidMessageError(for: "REQ")
            }

            var filters: [NDKFilter] = []
            for i in 2 ..< array.count {
                guard let filterDict = array[i] as? [String: Any] else { continue }
                let filter = try JSONCoding.decodeFromDictionary(NDKFilter.self, from: filterDict)
                filters.append(filter)
            }

            return .req(subscriptionId: subscriptionId, filters: filters)

        case .close:
            guard array.count >= 2,
                  let subscriptionId = array[1] as? String
            else {
                throw invalidMessageError(for: "CLOSE")
            }
            return .close(subscriptionId: subscriptionId)

        case .notice:
            guard array.count >= 2,
                  let message = array[1] as? String
            else {
                throw invalidMessageError(for: "NOTICE")
            }
            return .notice(message: message)

        case .eose:
            guard array.count >= 2,
                  let subscriptionId = array[1] as? String
            else {
                throw invalidMessageError(for: "EOSE")
            }
            return .eose(subscriptionId: subscriptionId)

        case .ok:
            guard array.count >= 3,
                  let eventId = array[1] as? String,
                  let accepted = array[2] as? Bool
            else {
                throw invalidMessageError(for: "OK")
            }
            let message = array.count > 3 ? array[3] as? String : nil
            return .ok(eventId: eventId, accepted: accepted, message: message)

        case .auth:
            guard array.count >= 2,
                  let challenge = array[1] as? String
            else {
                throw invalidMessageError(for: "AUTH")
            }
            return .auth(challenge: challenge)

        case .count:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String,
                  let countDict = array[2] as? [String: Any],
                  let count = countDict["count"] as? Int
            else {
                throw invalidMessageError(for: "COUNT")
            }
            return .count(subscriptionId: subscriptionId, count: count)

        case .negOpen:
            guard array.count >= 4,
                  let subscriptionId = array[1] as? String,
                  let filterDict = array[2] as? [String: Any],
                  let hexMessage = array[3] as? String
            else {
                throw invalidMessageError(for: "NEG-OPEN")
            }
            let filter = try NDKFilter.fromDictionary(filterDict)
            return .negOpen(subscriptionId: subscriptionId, filter: filter, message: hexMessage)

        case .negMsg:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String,
                  let hexMessage = array[2] as? String
            else {
                throw invalidMessageError(for: "NEG-MSG")
            }
            return .negMsg(subscriptionId: subscriptionId, message: hexMessage)

        case .negClose:
            guard array.count >= 2,
                  let subscriptionId = array[1] as? String
            else {
                throw invalidMessageError(for: "NEG-CLOSE")
            }
            return .negClose(subscriptionId: subscriptionId)

        case .negErr:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String,
                  let error = array[2] as? String
            else {
                throw invalidMessageError(for: "NEG-ERR")
            }
            return .negErr(subscriptionId: subscriptionId, error: error)
        }
    }

    /// Serialize message to send to relay
    public func serialize() throws -> String {
        var array: [Any] = []

        switch self {
        case let .event(_, event):
            array.append("EVENT")
            let eventDict = try JSONCoding.encodeToDictionary(event)
            array.append(eventDict)

        case let .req(subscriptionId, filters):
            array.append("REQ")
            array.append(subscriptionId)

            for filter in filters {
                let filterDict = try JSONCoding.encodeToDictionary(filter)
                array.append(filterDict)
            }

        case let .close(subscriptionId):
            array.append("CLOSE")
            array.append(subscriptionId)

        case let .notice(message):
            array.append("NOTICE")
            array.append(message)

        case let .eose(subscriptionId):
            array.append("EOSE")
            array.append(subscriptionId)

        case let .ok(eventId, accepted, message):
            array.append("OK")
            array.append(eventId)
            array.append(accepted)
            if let message = message {
                array.append(message)
            }

        case let .auth(challenge):
            array.append("AUTH")
            array.append(challenge)

        case let .count(subscriptionId, count):
            array.append("COUNT")
            array.append(subscriptionId)
            array.append(["count": count])

        case let .negOpen(subscriptionId, filter, message):
            array.append("NEG-OPEN")
            array.append(subscriptionId)
            array.append(filter.toDictionary())
            array.append(message)

        case let .negMsg(subscriptionId, message):
            array.append("NEG-MSG")
            array.append(subscriptionId)
            array.append(message)

        case let .negClose(subscriptionId):
            array.append("NEG-CLOSE")
            array.append(subscriptionId)

        case let .negErr(subscriptionId, error):
            array.append("NEG-ERR")
            array.append(subscriptionId)
            array.append(error)
        }

        return try JSONCoding.serializeToString(array)
    }

    /// Get the subscription ID if applicable
    public var subscriptionId: String? {
        switch self {
        case let .event(id, _):
            return id
        case let .eose(id):
            return id
        case let .count(id, _):
            return id
        case let .req(id, _), let .close(id):
            return id
        case let .negOpen(id, _, _), let .negMsg(id, _), let .negClose(id), let .negErr(id, _):
            return id
        case .notice, .ok, .auth:
            return nil
        }
    }
}
