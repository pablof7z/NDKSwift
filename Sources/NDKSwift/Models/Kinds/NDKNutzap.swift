import Foundation

/// Cashu proof for NIP-61
public struct CashuProof: Codable {
    public let id: String // Keyset id
    public let amount: Int // Amount in Satoshis
    public let secret: String // Initial secret
    public let C: String // Unblinded signature

    public init(id: String, amount: Int, secret: String, C: String) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
    }
}

/// Represents a NIP-61 nutzap event
public struct NDKNutzap {
    /// The underlying event
    public var event: NDKEvent

    /// The NDK instance
    public var ndk: NDK {
        return event.ndk ?? NDK()
    }

    /// Initialize a new nutzap
    public init(ndk: NDK) {
        self.event = NDKEvent(content: "", tags: [])
        self.event.ndk = ndk
        self.event.kind = EventKind.nutzap

        // Ensure we have an alt tag
        if event.tagValue("alt") == nil {
            event.tags.append(["alt", "This is a nutzap"])
        }
    }

    /// The Cashu proofs
    public var proofs: [CashuProof] {
        get {
            // Try to get proofs from tags first (preferred format)
            let proofTags = event.tags.filter { $0.first == "proof" }
            if !proofTags.isEmpty {
                return proofTags.compactMap { tag in
                    guard let proofJSON = tag[safe: 1],
                          let data = proofJSON.data(using: .utf8),
                          let proof = try? JSONDecoder().decode(CashuProof.self, from: data)
                    else {
                        return nil
                    }
                    return proof
                }
            }

            // Fallback to content (old format)
            guard let data = event.content.data(using: .utf8),
                  let proofs = try? JSONDecoder().decode([CashuProof].self, from: data)
            else {
                return []
            }
            return proofs
        }
        set {
            // Remove old proof tags
            event.tags = event.tags.filter { $0.first != "proof" }

            // Add new proof tags
            for proof in newValue {
                if let proofData = try? JSONEncoder().encode(proof),
                   let proofJSON = String(data: proofData, encoding: .utf8)
                {
                    event.tags.append(["proof", proofJSON])
                }
            }
        }
    }

    /// The comment for the nutzap
    public var comment: String? {
        get {
            // Check for comment tag first
            if let commentTag = event.tags.first(where: { $0.first == "comment" }) {
                return commentTag[safe: 1]
            }
            // Fallback to content if it's not JSON
            if !event.content.isEmpty, !event.content.starts(with: "["), !event.content.starts(with: "{") {
                return event.content
            }
            return nil
        }
        set {
            event.content = newValue ?? ""
        }
    }

    /// The mint URL
    public var mint: String? {
        get { event.tagValue("u") }
        set {
            event.tags = event.tags.filter { $0.first != "u" }
            if let value = newValue {
                event.tags.append(["u", value])
            }
        }
    }

    /// The target event or user
    public var target: NDKEventPointer? {
        // Check for 'e' tag (event)
        if let eventTag = event.tags.first(where: { $0.first == "e" }),
           let eventId = eventTag[safe: 1]
        {
            return .event(eventId, relayURL: eventTag[safe: 2])
        }

        // Check for 'p' tag (user)
        if let pubkeyTag = event.tags.first(where: { $0.first == "p" }),
           let pubkey = pubkeyTag[safe: 1]
        {
            return .pubkey(pubkey)
        }

        return nil
    }

    /// Set the target for the nutzap
    public mutating func setTarget(_ target: NDKEventPointer) {
        // Remove existing target tags
        event.tags = event.tags.filter { $0.first != "e" && $0.first != "p" }

        // Add new target tag
        switch target {
        case let .event(id, relayURL):
            if let relayURL = relayURL {
                event.tags.append(["e", id, relayURL])
            } else {
                event.tags.append(["e", id])
            }
        case let .pubkey(pubkey):
            event.tags.append(["p", pubkey])
        }
    }

    /// The recipient's pubkey
    public var recipientPubkey: String? {
        // For nutzaps, the recipient is always in a 'p' tag
        return event.tags.first(where: { $0.first == "p" })?[safe: 1]
    }

    /// Set the recipient
    public mutating func setRecipient(_ pubkey: String) {
        if target == nil || target?.pubkey != pubkey {
            // If no target or target is different, add p tag
            event.tags.append(["p", pubkey])
        }
    }

    /// The unit (always "sat" for nutzaps)
    public var unit: String {
        return event.tagValue("unit") ?? "sat"
    }

    /// Get P2PK data if present
    public var p2pkData: String? {
        guard let firstProof = proofs.first else { return nil }

        do {
            // Try to parse the secret
            if let secretData = firstProof.secret.data(using: .utf8) {
                let decoded = try JSONSerialization.jsonObject(with: secretData)

                // Check if it's an array with P2PK format
                if let array = decoded as? [Any],
                   array.count > 1,
                   let kind = array[0] as? String,
                   kind == "P2PK",
                   let payload = array[1] as? [String: Any],
                   let data = payload["data"] as? String
                {
                    return data
                }

                // Check if it's a direct object with P2PK data
                if let dict = decoded as? [String: Any],
                   let data = dict["data"] as? String
                {
                    return data
                }
            }
        } catch {
            // Secret is not P2PK formatted
        }

        return nil
    }

    /// Total amount of the nutzap
    public var totalAmount: Int {
        return proofs.reduce(0) { $0 + $1.amount }
    }

    /// Create from an existing event
    public static func from(_ event: NDKEvent) -> NDKNutzap? {
        guard event.kind == EventKind.nutzap else { return nil }

        var nutzap = NDKNutzap(ndk: event.ndk ?? NDK())
        nutzap.event = event

        // Validate that we have proofs
        guard !nutzap.proofs.isEmpty else { return nil }

        return nutzap
    }

    /// Sign the nutzap
    public mutating func sign() async throws {
        try await event.sign()
    }

    /// Publish the nutzap to specific relays
    public func publish(on _: NDKRelaySet) async throws {
        // Ensure the event is signed
        var mutableSelf = self
        if event.sig == nil {
            try await mutableSelf.sign()
        }

        // TODO: Implement relay-specific publishing
        // For now, use the standard publish method
        _ = try await ndk.publish(mutableSelf.event)
    }
}

/// Event pointer for targets
public enum NDKEventPointer {
    case event(String, relayURL: String?)
    case pubkey(String)

    var pubkey: String? {
        switch self {
        case let .pubkey(pk):
            return pk
        default:
            return nil
        }
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
