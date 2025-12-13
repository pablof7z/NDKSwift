import Foundation

// MARK: - NDKEvent Extensions for NIP-59

public extension NDKEvent {
    /// Create an unsigned event (rumor) for NIP-59
    /// This initializer creates an event without id and signature
    init(
        kind: Kind,
        content: String,
        tags: [Tag] = [],
        pubkey: PublicKey,
        createdAt: Timestamp? = nil
    ) {
        self.init(
            id: "", // Empty ID for unsigned event
            pubkey: pubkey,
            createdAt: createdAt ?? .now,
            kind: kind,
            tags: tags,
            content: content,
            sig: "" // Empty signature for unsigned event
        )
    }

    /// Parse an event from JSON string
    /// - Parameter json: JSON string representation of the event
    /// - Returns: NDKEvent instance
    static func fromJSON(_ json: String) throws -> NDKEvent {
        // Use the existing JSONCoding utility for consistency
        let dict = try JSONCoding.parseDictionary(from: json)

        // Extract fields with defaults for rumor events
        let id = dict["id"] as? String ?? ""
        let pubkey = dict["pubkey"] as? String ?? ""
        let createdAt = dict["created_at"] as? Int64 ?? dict["createdAt"] as? Int64 ?? Timestamp.now
        let kind = dict["kind"] as? Int ?? 0
        let tags = dict["tags"] as? [[String]] ?? []
        let content = dict["content"] as? String ?? ""
        let sig = dict["sig"] as? String ?? ""

        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }

    /// Check if this is an unsigned event (rumor)
    var isRumor: Bool {
        return id.isEmpty || sig.isEmpty
    }

    /// Check if this is a seal event (kind 13)
    var isSeal: Bool {
        return kind == EventKind.seal
    }

    /// Check if this is a gift wrap event (kind 1059)
    var isGiftWrap: Bool {
        return kind == EventKind.giftWrap
    }
}
