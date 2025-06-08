import Foundation

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

    /// Parse a message from relay
    public static func parse(from json: String) throws -> NostrMessage {
        guard let data = json.data(using: .utf8) else {
            throw NDKError.protocol("parse_error", "Invalid JSON string")
        }

        let array = try JSONSerialization.jsonObject(with: data) as? [Any]
        guard let array = array, !array.isEmpty else {
            throw NDKError.protocol("parse_error", "Invalid message format")
        }

        guard let typeString = array[0] as? String,
              let type = NostrMessageType(rawValue: typeString)
        else {
            throw NDKError.protocol("parse_error", "Unknown message type")
        }

        switch type {
        case .event:
            guard array.count >= 2 else {
                throw NDKError.protocol("parse_error", "Invalid EVENT message")
            }

            let subscriptionId = array.count > 2 ? array[1] as? String : nil
            let eventIndex = subscriptionId != nil ? 2 : 1

            guard let eventDict = array[eventIndex] as? [String: Any] else {
                throw NDKError.protocol("parse_error", "Invalid event data")
            }

            let event = try JSONCoding.decodeFromDictionary(NDKEvent.self, from: eventDict)

            return .event(subscriptionId: subscriptionId, event: event)

        case .req:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String
            else {
                throw NDKError.protocol("parse_error", "Invalid REQ message")
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
                throw NDKError.protocol("parse_error", "Invalid CLOSE message")
            }
            return .close(subscriptionId: subscriptionId)

        case .notice:
            guard array.count >= 2,
                  let message = array[1] as? String
            else {
                throw NDKError.protocol("parse_error", "Invalid NOTICE message")
            }
            return .notice(message: message)

        case .eose:
            guard array.count >= 2,
                  let subscriptionId = array[1] as? String
            else {
                throw NDKError.protocol("parse_error", "Invalid EOSE message")
            }
            return .eose(subscriptionId: subscriptionId)

        case .ok:
            guard array.count >= 3,
                  let eventId = array[1] as? String,
                  let accepted = array[2] as? Bool
            else {
                throw NDKError.protocol("parse_error", "Invalid OK message")
            }
            let message = array.count > 3 ? array[3] as? String : nil
            return .ok(eventId: eventId, accepted: accepted, message: message)

        case .auth:
            guard array.count >= 2,
                  let challenge = array[1] as? String
            else {
                throw NDKError.protocol("parse_error", "Invalid AUTH message")
            }
            return .auth(challenge: challenge)

        case .count:
            guard array.count >= 3,
                  let subscriptionId = array[1] as? String,
                  let countDict = array[2] as? [String: Any],
                  let count = countDict["count"] as? Int
            else {
                throw NDKError.protocol("parse_error", "Invalid COUNT message")
            }
            return .count(subscriptionId: subscriptionId, count: count)
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
        }

        let data = try JSONSerialization.data(withJSONObject: array, options: [.withoutEscapingSlashes])
        guard let json = String(data: data, encoding: .utf8) else {
            throw NDKError.protocol("parse_error", "Failed to serialize message")
        }


        return json
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
        case .notice, .ok, .auth:
            return nil
        }
    }
}
