import CryptoSwift
import Foundation

/// Represents a Nostr event
/// 
/// This is an immutable struct that represents a signed Nostr event. Once created,
/// all properties are read-only and access is synchronous.
/// 
/// Use `NDKEventBuilder` to create and sign new events.
/// 
/// **Value Semantics**: This struct uses value semantics for equality comparisons.
/// Two events with the same Nostr ID will be considered equal.
public struct NDKEvent: Codable, Equatable, Hashable, Sendable {
    /// Unique event ID (32-byte hash)
    public let id: EventID

    /// Public key of the event creator
    public let pubkey: PublicKey

    /// Unix timestamp when the event was created
    public let createdAt: Timestamp

    /// Event kind
    public let kind: Kind

    /// Event tags
    public let tags: [Tag]

    /// Event content
    public let content: String

    /// Event signature
    public let sig: Signature
    

    // MARK: - Initialization

    public init(
        id: EventID,
        pubkey: PublicKey,
        createdAt: Timestamp,
        kind: Kind,
        tags: [Tag],
        content: String,
        sig: Signature
    ) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = sig
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, pubkey, createdAt = "created_at", kind, tags, content, sig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        guard let id = try container.decodeIfPresent(String.self, forKey: .id) else {
            throw NDKError.invalidEventID("Event ID is required")
        }
        
        let pubkey = try container.decode(String.self, forKey: .pubkey)
        let createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let tags = try container.decode([[String]].self, forKey: .tags)
        let content = try container.decode(String.self, forKey: .content)
        
        guard let sig = try container.decodeIfPresent(String.self, forKey: .sig) else {
            throw NDKError.invalidSignature("Event signature is required")
        }
        
        self.init(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(kind, forKey: .kind)
        try container.encode(tags, forKey: .tags)
        try container.encode(content, forKey: .content)
        try container.encode(sig, forKey: .sig)
    }

    // MARK: - Equatable & Hashable
    
    /// Compares events by their Nostr ID
    public static func == (lhs: NDKEvent, rhs: NDKEvent) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the event using its ID
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Validation

    /// Validate event structure
    public func validate() throws {
        // Validate public key
        guard HexValidator.isValid32ByteHex(pubkey) else {
            throw NDKError.invalidPublicKey(pubkey)
        }

        // Validate ID
        guard HexValidator.isValid32ByteHex(id) else {
            throw NDKError.invalidEventID(id)
        }

        // Validate signature
        guard HexValidator.isValid64ByteHex(sig) else {
            throw NDKError.invalidSignature(sig)
        }

        // Verify ID matches content
        let calculatedID = try calculateID()
        guard id == calculatedID else {
            throw NDKError.invalidEventID("Event ID does not match content: \(id)")
        }
    }

    /// Calculate event ID based on NIP-01 without modifying the event
    public func calculateID() throws -> EventID {
        let serialized = try serializeForID()
        let data = serialized.data(using: .utf8)!
        let hash = data.sha256()
        return hash.hexString
    }

    /// Serialize event for ID generation according to NIP-01
    private func serializeForID() throws -> String {
        // [0, pubkey, created_at, kind, tags, content]
        let array: [Any] = [
            0,
            pubkey,
            createdAt,
            kind,
            tags,
            content
        ]

        return try JSONCoding.serializeToString(array)
    }

    // MARK: - Tag Helpers

    /// Get all tags of a specific type
    public func tags(withName name: String) -> [Tag] {
        return tags.filter { $0.first == name }
    }

    /// Get the first tag of a specific type
    public func tag(withName name: String) -> Tag? {
        return tags.first { $0.first == name }
    }

    /// Get all referenced event IDs from 'e' tags
    /// - Returns: Array of event IDs referenced in this event
    public var referencedEventIds: [EventID] {
        let eTags = tags(withName: "e")
        return eTags.compactMap { $0.count > 1 ? $0[1] : nil }
    }

    /// Get all referenced public keys from 'p' tags
    /// - Returns: Array of public keys referenced in this event
    public var referencedPubkeys: [PublicKey] {
        let pTags = tags(withName: "p")
        return pTags.compactMap { $0.count > 1 ? $0[1] : nil }
    }

    /// Get the first value of a tag by name
    /// - Parameter name: The tag name to search for
    /// - Returns: The first value of the tag (second element) if it exists, nil otherwise
    public func tagValue(_ name: String) -> String? {
        let foundTag = tag(withName: name)
        return foundTag?.count ?? 0 > 1 ? foundTag?[1] : nil
    }
    
    /// Get the client tag information if present (NIP-89)
    /// 
    /// - Returns: A tuple containing (name, address, relay) or nil if no client tag exists
    public var clientTag: (name: String, address: String?, relay: String?)? {
        guard let tag = tag(withName: "client"), tag.count >= 2 else { return nil }
        
        let name = tag[1]
        let address = tag.count >= 3 && !tag[2].isEmpty ? tag[2] : nil
        let relay = tag.count >= 4 && !tag[3].isEmpty ? tag[3] : nil
        
        return (name: name, address: address, relay: relay)
    }

    // MARK: - Signing
    
    /// Verify the signature of this event
    /// - Returns: true if the signature is valid, false otherwise
    public func verifySignature() -> Bool {
        do {
            let calculatedID = try calculateID()
            guard calculatedID == id else { return false }
            
            // Use crypto utilities to verify signature
            let messageData = Data(hexString: id) ?? Data()
            return try Crypto.verify(signature: sig, message: messageData, publicKey: pubkey)
        } catch {
            return false
        }
    }
    

    // MARK: - Convenience

    /// Check if this event is a reply to another event
    /// - Returns: true if this event has an 'e' tag marked as "reply"
    public var isReply: Bool {
        return tags.contains { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
    }

    /// Get the event ID this is replying to
    /// - Returns: The event ID from the first 'e' tag marked as "reply", or nil if not a reply
    public var replyEventId: EventID? {
        let replyTag = tags.first { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        return replyTag?.count ?? 0 > 1 ? replyTag?[1] : nil
    }

    /// Check if this event is ephemeral (not stored by relays)
    /// - Returns: true if the event kind is between 20000-29999 (NIP-16)
    public var isEphemeral: Bool {
        return kind >= 20000 && kind < 30000
    }

    /// Check if this event is replaceable
    /// - Returns: true if the event is replaceable (kind 0, 3, or 10000-19999)
    /// - Note: Replaceable events can be overwritten by newer events with the same kind from the same author
    public var isReplaceable: Bool {
        // Kind 0 (metadata) and kind 3 (contacts) are replaceable
        // Also kinds 10000-19999 are replaceable
        return kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000)
    }

    /// Check if this event is parameterized replaceable
    /// - Returns: true if the event kind is between 30000-39999 (NIP-33)
    /// - Note: These events are replaceable based on kind, author, and 'd' tag value
    public var isParameterizedReplaceable: Bool {
        return kind >= 30000 && kind < 40000
    }
    
    /// Check if this event is protected (NIP-70)
    /// - Returns: true if the event contains a '-' tag indicating it's protected
    /// - Note: Protected events should not be deleted by relays even when requested
    public var isProtected: Bool {
        return tags.contains { $0.first == "-" }
    }

    /// Get the tag address for replaceable events
    public var tagAddress: String {
        if isParameterizedReplaceable {
            // Parameterized replaceable events
            let dTag = tags.firstTagValue(named: NostrTag.description) ?? ""
            return "\(kind):\(pubkey):\(dTag)"
        } else if isReplaceable {
            // Regular replaceable events - NIP-01 requires trailing colon
            return "\(kind):\(pubkey):"
        } else {
            return id
        }
    }
    
    /// Get the appropriate tag reference for this event
    /// Returns a tag array suitable for referencing this event in other events
    public func tagReference() -> Tag {
        if isParameterizedReplaceable {
            // Use 'a' tag for parameterized replaceable events
            return ["a", tagAddress, "", "", pubkey]
        } else if isReplaceable {
            // Use 'a' tag for replaceable events
            return ["a", tagAddress, "", "", pubkey]
        } else {
            // Use 'e' tag for regular events
            return ["e", id, "", "", pubkey]
        }
    }

    // MARK: - Serialization

    /// Returns the raw event as a dictionary compatible with Nostr protocol
    /// This matches the rawEvent() method from @ndk/ndk-core
    public func rawEvent() -> [String: Any] {
        return [
            "id": id,
            "pubkey": pubkey,
            "created_at": createdAt,
            "kind": kind,
            "tags": tags,
            "content": content,
            "sig": sig
        ]
    }

    /// Serialize event to JSON string
    public func serialize() throws -> String {
        return try JSONCoding.encodeToString(self)
    }

    /// Alias for serialize() - serialize event to JSON string
    public func toJSON() throws -> String {
        return try serialize()
    }

    // MARK: - Event Reactions
    
    /// Get mentions from this event
    public var mentions: [PublicKey] {
        return referencedPubkeys
    }

    // MARK: - NIP-19 Encoding

    /// Encode this event to bech32 format according to NIP-19
    /// Returns note1 for simple events, nevent1 for events with metadata, naddr1 for replaceable events
    public func encode(includeRelays: Bool = false, relayHints: [String]? = nil) throws -> String {
        // For parameterized replaceable events, use naddr encoding
        if isParameterizedReplaceable {
            let identifier = tagValue("d") ?? ""
            return try Bech32.naddr(
                identifier: identifier,
                kind: kind,
                author: pubkey,
                relays: includeRelays ? relayHints : nil
            )
        }

        // For other replaceable events, use naddr encoding with empty identifier
        if isReplaceable {
            return try Bech32.naddr(
                identifier: "",
                kind: kind,
                author: pubkey,
                relays: includeRelays ? relayHints : nil
            )
        }

        // For non-replaceable events, decide between note and nevent
        let hasMetadata = hasMetadataWorthyOfNevent()
        if includeRelays || hasMetadata {
            return try Bech32.nevent(
                eventId: id,
                relays: includeRelays ? relayHints : nil,
                author: pubkey,
                kind: kind
            )
        } else {
            // Simple note encoding
            return try Bech32.note(from: id)
        }
    }

    /// Check if this event has metadata that makes nevent encoding worthwhile
    private func hasMetadataWorthyOfNevent() -> Bool {
        // Use nevent if the event has non-standard kind or has important tags
        return kind != EventKind.textNote || !referencedEventIds.isEmpty || !referencedPubkeys.isEmpty
    }
    
}

// MARK: - Character extension for hex validation

private extension Character {
    var isHexDigit: Bool {
        return ("0" ... "9").contains(self) || ("a" ... "f").contains(self) || ("A" ... "F").contains(self)
    }
}