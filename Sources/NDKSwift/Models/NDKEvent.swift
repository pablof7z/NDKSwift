import CryptoSwift
import Foundation

/// Represents a Nostr event
public final class NDKEvent: Codable, Equatable, Hashable {
    /// Unique event ID (32-byte hash)
    public var id: EventID?

    /// Public key of the event creator
    public var pubkey: PublicKey

    /// Unix timestamp when the event was created
    public var createdAt: Timestamp

    /// Event kind
    public var kind: Kind

    /// Event tags
    public var tags: [Tag]

    /// Event content
    public var content: String

    /// Event signature
    public var sig: Signature?

    /// Reference to NDK instance
    public weak var ndk: NDK?

    /// Relay that this event was received from
    public private(set) var relay: NDKRelay?

    /// Internal method to set relay (called by relay when processing events)
    func setRelay(_ relay: NDKRelay) {
        self.relay = relay
    }

    /// Tracks which relays this event has been seen on
    public private(set) var seenOnRelays: Set<String> = []

    /// Tracks publish status for each relay
    public private(set) var relayPublishStatuses: [String: RelayPublishStatus] = [:]

    /// Tracks OK messages from relays
    public private(set) var relayOKMessages: [String: OKMessage] = [:]

    /// Custom properties for extension
    private var customProperties: [String: Any] = [:]

    // MARK: - Relay Tracking Methods

    /// Mark event as seen on a relay
    public func markSeenOn(relay: String) {
        seenOnRelays.insert(relay)
    }

    /// Update publish status for a relay
    public func updatePublishStatus(relay: String, status: RelayPublishStatus) {
        relayPublishStatuses[relay] = status
    }

    /// Store OK message from a relay
    public func addOKMessage(relay: String, accepted: Bool, message: String?) {
        relayOKMessages[relay] = OKMessage(accepted: accepted, message: message, receivedAt: Date())
    }

    /// Get all relays where this event was successfully published
    public var successfullyPublishedRelays: [String] {
        relayPublishStatuses.compactMap { relay, status in
            switch status {
            case .succeeded:
                return relay
            default:
                return nil
            }
        }
    }

    /// Get all relays where publishing failed
    public var failedPublishRelays: [String] {
        relayPublishStatuses.compactMap { relay, status in
            switch status {
            case .failed:
                return relay
            default:
                return nil
            }
        }
    }

    /// Check if event was published to at least one relay
    public var wasPublished: Bool {
        !successfullyPublishedRelays.isEmpty
    }

    // MARK: - Initialization

    public init(
        pubkey: PublicKey,
        createdAt: Timestamp = Timestamp(Date().timeIntervalSince1970),
        kind: Kind,
        tags: [Tag] = [],
        content: String = ""
    ) {
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
    }

    /// Convenience initializer for creating events that will be signed later
    public convenience init(content: String = "", tags: [Tag] = []) {
        self.init(pubkey: "", createdAt: Timestamp(Date().timeIntervalSince1970), kind: 1, tags: tags, content: content)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, pubkey, createdAt = "created_at", kind, tags, content, sig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.pubkey = try container.decode(String.self, forKey: .pubkey)
        self.createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.tags = try container.decode([[String]].self, forKey: .tags)
        self.content = try container.decode(String.self, forKey: .content)
        self.sig = try container.decodeIfPresent(String.self, forKey: .sig)
    }

    // MARK: - Event ID Generation

    /// Generate event ID based on NIP-01
    public func generateID() throws -> EventID {
        let serialized = try serializeForID()
        let data = serialized.data(using: .utf8)!
        let hash = data.sha256()
        let id = hash.toHexString()
        self.id = id
        return id
    }

    /// Serialize event for ID generation according to NIP-01
    private func serializeForID() throws -> String {
        // [0, pubkey, created_at, kind, tags, content]
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        let array: [Any] = [
            0,
            pubkey,
            createdAt,
            kind,
            tags,
            content,
        ]

        let data = try JSONSerialization.data(withJSONObject: array, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Validation

    /// Validate event structure
    public func validate() throws {
        // Validate public key
        guard pubkey.count == 64, pubkey.allSatisfy({ $0.isHexDigit }) else {
            throw NDKError.validation("invalid_public_key", "Invalid public key format")
        }

        // Validate ID if present
        if let id = id {
            guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else {
                throw NDKError.validation("invalid_event_id", "Invalid event ID format")
            }

            // Verify ID matches content
            let calculatedID = try generateID()
            guard id == calculatedID else {
                throw NDKError.validation("invalid_event_id", "Event ID does not match content")
            }
        }

        // Validate signature if present
        if let sig = sig {
            guard sig.count == 128, sig.allSatisfy({ $0.isHexDigit }) else {
                throw NDKError.validation("invalid_signature", "Invalid signature format")
            }
        }
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

    /// Add a tag
    public func addTag(_ tag: Tag) {
        tags.append(tag)
    }

    /// Add a 'p' tag for mentioning a user
    public func tag(user: NDKUser, marker: String? = nil) {
        var tag = ["p", user.pubkey]
        if let marker = marker {
            tag.append(marker)
        }
        addTag(tag)
    }

    /// Add an 'e' tag for referencing an event
    public func tag(event: NDKEvent, marker: String? = nil, relay: String? = nil) {
        guard let eventID = event.id else { return }
        var tag = ["e", eventID]
        if let relay = relay {
            tag.append(relay)
        }
        if let marker = marker {
            if relay == nil {
                tag.append("") // Empty relay URL
            }
            tag.append(marker)
        }
        addTag(tag)
    }

    /// Generate content tags from the event's content
    /// This scans for hashtags, nostr entities (npub, note, etc.) and adds appropriate tags
    public func generateContentTags() {
        let contentTag = ContentTagger.generateContentTags(from: content, existingTags: tags)
        self.content = contentTag.content
        self.tags = contentTag.tags
    }

    /// Convenience method to set content and generate tags automatically
    public func setContent(_ newContent: String, generateTags: Bool = true) {
        self.content = newContent
        if generateTags {
            generateContentTags()
        }
    }

    /// Get all referenced event IDs
    public var referencedEventIds: [EventID] {
        return tags(withName: "e").compactMap { $0.count > 1 ? $0[1] : nil }
    }

    /// Get all referenced pubkeys
    public var referencedPubkeys: [PublicKey] {
        return tags(withName: "p").compactMap { $0.count > 1 ? $0[1] : nil }
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: NDKEvent, rhs: NDKEvent) -> Bool {
        // Events are equal if they have the same ID
        guard let lhsID = lhs.id, let rhsID = rhs.id else {
            return false
        }
        return lhsID == rhsID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Signing

    /// Sign this event using the NDK instance's signer
    public func sign() async throws {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        guard let signer = ndk.signer else {
            throw NDKError.crypto("no_signer", "No signer configured")
        }

        // Set pubkey from signer if not already set
        if pubkey.isEmpty {
            pubkey = try await signer.pubkey
        }

        // Generate content tags before signing
        generateContentTags()

        // Generate ID if not already set
        if id == nil {
            _ = try generateID()
        }

        // Sign the event
        sig = try await signer.sign(self)
    }

    // MARK: - Convenience

    /// Check if this event is a reply to another event
    public var isReply: Bool {
        return tags.contains { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
    }

    /// Get the event ID this is replying to
    public var replyEventId: EventID? {
        let replyTag = tags.first { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
        }
        return replyTag?.count ?? 0 > 1 ? replyTag?[1] : nil
    }

    /// Check if this event is ephemeral
    public var isEphemeral: Bool {
        return kind >= 20000 && kind < 30000
    }

    /// Check if this event is replaceable
    public var isReplaceable: Bool {
        // Kind 0 (metadata) and kind 3 (contacts) are replaceable
        // Also kinds 10000-19999 are replaceable
        return kind == 0 || kind == 3 || (kind >= 10000 && kind < 20000)
    }

    /// Check if this event is parameterized replaceable
    public var isParameterizedReplaceable: Bool {
        return kind >= 30000 && kind < 40000
    }

    /// Get the tag address for replaceable events
    public var tagAddress: String {
        if isParameterizedReplaceable {
            // Parameterized replaceable events
            let dTag = tags.first(where: { $0.count >= 2 && $0[0] == "d" })?[1] ?? ""
            return "\(kind):\(pubkey):\(dTag)"
        } else if isReplaceable {
            // Regular replaceable events
            return "\(kind):\(pubkey)"
        } else {
            return id ?? ""
        }
    }

    /// Get the value of a tag by name
    public func tagValue(_ name: String) -> String? {
        return tag(withName: name)?.count ?? 0 > 1 ? tag(withName: name)?[1] : nil
    }

    // MARK: - Serialization

    /// Returns the raw event as a dictionary compatible with Nostr protocol
    /// This matches the rawEvent() method from @ndk/ndk-core
    public func rawEvent() -> [String: Any] {
        var result: [String: Any] = [
            "created_at": createdAt,
            "content": content,
            "tags": tags,
            "kind": kind,
            "pubkey": pubkey,
        ]

        if let id = id {
            result["id"] = id
        }

        if let sig = sig {
            result["sig"] = sig
        }

        return result
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

    /// React to this event with the given content (usually an emoji)
    /// @param content The reaction content (e.g., "+", "-", "❤️", "🤙", "⚡", etc.)
    /// @param publish Whether to automatically publish the reaction event
    /// @returns The reaction event
    public func react(content: String, publish: Bool = true) async throws -> NDKEvent {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        guard ndk.signer != nil else {
            throw NDKError.crypto("no_signer", "No signer configured")
        }

        // Create the reaction event
        let reactionEvent = NDKEvent(
            pubkey: "", // Will be set by signer
            kind: EventKind.reaction,
            tags: [],
            content: content
        )

        reactionEvent.ndk = ndk

        // Tag this event
        reactionEvent.tag(event: self)

        // Also tag the author of the event being reacted to
        reactionEvent.tag(user: NDKUser(pubkey: pubkey))

        // Sign the reaction event
        try await reactionEvent.sign()

        // Publish if requested
        if publish {
            try await ndk.publish(reactionEvent)
        }

        return reactionEvent
    }

    // MARK: - NIP-19 Encoding

    /// Encode this event to bech32 format according to NIP-19
    /// Returns note1 for simple events, nevent1 for events with metadata, naddr1 for replaceable events
    public func encode(includeRelays: Bool = false) throws -> String {
        guard let eventId = id else {
            throw NDKError.validation("missing_event_id", "Event ID is required for encoding")
        }

        // For parameterized replaceable events, use naddr encoding
        if isParameterizedReplaceable {
            let identifier = tagValue("d") ?? ""
            let relays = includeRelays ? getRelayHints() : nil
            return try Bech32.naddr(
                identifier: identifier,
                kind: kind,
                author: pubkey,
                relays: relays
            )
        }

        // For other replaceable events, use naddr encoding with empty identifier
        if isReplaceable {
            let relays = includeRelays ? getRelayHints() : nil
            return try Bech32.naddr(
                identifier: "",
                kind: kind,
                author: pubkey,
                relays: relays
            )
        }

        // For non-replaceable events, decide between note and nevent
        if includeRelays || hasMetadataWorthyOfNevent() {
            let relays = includeRelays ? getRelayHints() : nil
            return try Bech32.nevent(
                eventId: eventId,
                relays: relays,
                author: pubkey,
                kind: kind
            )
        } else {
            // Simple note encoding nsec1rfwvk7tvws2hy0sf25wu96qhefr9c0xrlvllymwe6new8e59lgdsz23vuj
            return try Bech32.note(from: eventId)
        }
    }

    /// Get relay hints for this event
    private func getRelayHints() -> [String]? {
        var relays: [String] = []

        // Add relay where this event was received from
        if let relay = relay {
            relays.append(relay.url)
        }

        // Add relays from NDK instance if available
        if let ndk = ndk {
            let ndkRelays = ndk.relays.prefix(3).map { $0.url }
            relays.append(contentsOf: ndkRelays)
        }

        // Remove duplicates and limit to 3 relays (as recommended by NIP-19)
        let uniqueRelays = Array(Set(relays)).prefix(3)
        return uniqueRelays.isEmpty ? nil : Array(uniqueRelays)
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
