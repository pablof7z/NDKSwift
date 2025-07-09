import CryptoSwift
import Foundation

/// Actor for thread-safe event state management
actor EventStateActor {
    // Core event properties
    var id: EventID?
    var pubkey: PublicKey
    var createdAt: Timestamp
    var kind: Kind
    var tags: [Tag]
    var content: String
    var sig: Signature?
    
    // References
    weak var ndk: NDK?
    var relay: NDKRelay?
    
    // Tracking properties
    var seenOnRelays: Set<String> = []
    var relayPublishStatuses: [String: RelayPublishStatus] = [:]
    var relayOKMessages: [String: OKMessage] = [:]
    var customProperties: [String: Any] = [:]
    
    init(
        id: EventID? = nil,
        pubkey: PublicKey,
        createdAt: Timestamp,
        kind: Kind,
        tags: [Tag],
        content: String,
        sig: Signature? = nil
    ) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = sig
    }
    
    // Getters
    func getId() -> EventID? { id }
    func getPubkey() -> PublicKey { pubkey }
    func getCreatedAt() -> Timestamp { createdAt }
    func getKind() -> Kind { kind }
    func getTags() -> [Tag] { tags }
    func getContent() -> String { content }
    func getSig() -> Signature? { sig }
    func getNDK() -> NDK? { ndk }
    func getRelay() -> NDKRelay? { relay }
    func getSeenOnRelays() -> Set<String> { seenOnRelays }
    func getRelayPublishStatuses() -> [String: RelayPublishStatus] { relayPublishStatuses }
    func getRelayOKMessages() -> [String: OKMessage] { relayOKMessages }
    
    // Setters
    func setId(_ newId: EventID?) { id = newId }
    func setPubkey(_ newPubkey: PublicKey) { pubkey = newPubkey }
    func setCreatedAt(_ newCreatedAt: Timestamp) { createdAt = newCreatedAt }
    func setKind(_ newKind: Kind) { kind = newKind }
    func setTags(_ newTags: [Tag]) { tags = newTags }
    func setContent(_ newContent: String) { content = newContent }
    func setSig(_ newSig: Signature?) { sig = newSig }
    func setNDK(_ newNDK: NDK?) { ndk = newNDK }
    func setRelay(_ newRelay: NDKRelay?) { relay = newRelay }
    
    // Tag operations
    func addTag(_ tag: Tag) { tags.append(tag) }
    
    // Relay tracking
    func markSeenOn(relay: String) { seenOnRelays.insert(relay) }
    func updatePublishStatus(relay: String, status: RelayPublishStatus) { relayPublishStatuses[relay] = status }
    func addOKMessage(relay: String, accepted: Bool, message: String?) {
        relayOKMessages[relay] = OKMessage(accepted: accepted, message: message, receivedAt: Date())
    }
    
    // Get all values as a snapshot for serialization
    func getSnapshot() -> (id: EventID?, pubkey: PublicKey, createdAt: Timestamp, kind: Kind, tags: [Tag], content: String, sig: Signature?) {
        return (id, pubkey, createdAt, kind, tags, content, sig)
    }
    
    // Synchronous snapshot for Codable
    nonisolated func getSnapshotSync() -> (id: EventID?, pubkey: PublicKey, createdAt: Timestamp, kind: Kind, tags: [Tag], content: String, sig: Signature?)? {
        // This is a workaround for Codable which can't be async
        // We'll store a cached snapshot when properties change
        return nil // Will be implemented with proper caching
    }
}

/// A Sendable snapshot of an event's properties for performance optimization
public struct EventSnapshot: Sendable {
    public let id: EventID?
    public let pubkey: PublicKey
    public let createdAt: Timestamp
    public let kind: Kind
    public let tags: [Tag]
    public let content: String
    public let sig: Signature?
}

/// Represents a Nostr event
/// 
/// This class uses actor-based concurrency for thread safety. All mutable state is
/// managed by an internal `EventStateActor`, making property access async.
/// 
/// For performance-critical code that needs to access multiple properties, use the
/// `snapshot()` method to get all properties with a single await.
/// 
/// **Object Identity**: This class uses object identity for equality comparisons.
/// Two events with the same Nostr ID will only be equal if they are the same
/// object instance. Event deduplication should ensure the same instance is used
/// for a given event ID.
public final class NDKEvent: Codable, Equatable, Hashable, Sendable {
    /// Internal state actor that manages all mutable state
    private let stateActor: EventStateActor
    
    /// Unique event ID (32-byte hash)
    public var id: EventID? {
        get async { await stateActor.getId() }
    }

    /// Public key of the event creator
    public var pubkey: PublicKey {
        get async { await stateActor.getPubkey() }
    }

    /// Unix timestamp when the event was created
    public var createdAt: Timestamp {
        get async { await stateActor.getCreatedAt() }
    }

    /// Event kind
    public var kind: Kind {
        get async { await stateActor.getKind() }
    }

    /// Event tags
    public var tags: [Tag] {
        get async { await stateActor.getTags() }
    }

    /// Event content
    public var content: String {
        get async { await stateActor.getContent() }
    }

    /// Event signature
    public var sig: Signature? {
        get async { await stateActor.getSig() }
    }

    /// Reference to NDK instance
    public var ndk: NDK? {
        get async { await stateActor.getNDK() }
    }

    /// Relay that this event was received from
    public var relay: NDKRelay? {
        get async { await stateActor.getRelay() }
    }

    /// Internal method to set relay (called by relay when processing events)
    func setRelay(_ relay: NDKRelay) async {
        await stateActor.setRelay(relay)
    }

    /// Tracks which relays this event has been seen on
    public var seenOnRelays: Set<String> {
        get async { await stateActor.getSeenOnRelays() }
    }

    /// Tracks publish status for each relay
    public var relayPublishStatuses: [String: RelayPublishStatus] {
        get async { await stateActor.getRelayPublishStatuses() }
    }

    /// Tracks OK messages from relays
    public var relayOKMessages: [String: OKMessage] {
        get async { await stateActor.getRelayOKMessages() }
    }

    // MARK: - Relay Tracking Methods

    /// Mark event as seen on a relay
    public func markSeenOn(relay: String) async {
        await stateActor.markSeenOn(relay: relay)
    }

    /// Update publish status for a relay
    public func updatePublishStatus(relay: String, status: RelayPublishStatus) async {
        await stateActor.updatePublishStatus(relay: relay, status: status)
    }

    /// Store OK message from a relay
    public func addOKMessage(relay: String, accepted: Bool, message: String?) async {
        await stateActor.addOKMessage(relay: relay, accepted: accepted, message: message)
    }

    /// Get all relays where this event was successfully published
    public var successfullyPublishedRelays: [String] {
        get async {
            let statuses = await stateActor.getRelayPublishStatuses()
            return statuses.compactMap { relay, status in
                switch status {
                case .succeeded:
                    return relay
                default:
                    return nil
                }
            }
        }
    }

    /// Get all relays where publishing failed
    public var failedPublishRelays: [String] {
        get async {
            let statuses = await stateActor.getRelayPublishStatuses()
            return statuses.compactMap { relay, status in
                switch status {
                case .failed:
                    return relay
                default:
                    return nil
                }
            }
        }
    }

    /// Check if event was published to at least one relay
    public var wasPublished: Bool {
        get async {
            let successful = await successfullyPublishedRelays
            return !successful.isEmpty
        }
    }

    // MARK: - Initialization

    public init(
        pubkey: PublicKey,
        createdAt: Timestamp = Timestamp(Date().timeIntervalSince1970),
        kind: Kind,
        tags: [Tag] = [],
        content: String = ""
    ) {
        self.stateActor = EventStateActor(
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
    }

    /// Convenience initializer for creating events that will be signed later
    public convenience init(content: String = "", tags: [Tag] = []) {
        self.init(pubkey: "", createdAt: Timestamp(Date().timeIntervalSince1970), kind: 1, tags: tags, content: content)
    }
    
    /// Set NDK instance
    public func setNDK(_ ndk: NDK) async {
        await stateActor.setNDK(ndk)
    }
    
    /// Set signature
    public func setSig(_ sig: Signature?) async {
        await stateActor.setSig(sig)
    }
    
    /// Get a snapshot of all event properties with a single await
    /// This is more efficient than accessing multiple properties individually
    public func snapshot() async -> EventSnapshot {
        let (id, pubkey, createdAt, kind, tags, content, sig) = await stateActor.getSnapshot()
        return EventSnapshot(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, pubkey, createdAt = "created_at", kind, tags, content, sig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
        let pubkey = try container.decode(String.self, forKey: .pubkey)
        let createdAt = try container.decode(Timestamp.self, forKey: .createdAt)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let tags = try container.decode([[String]].self, forKey: .tags)
        let content = try container.decode(String.self, forKey: .content)
        let sig = try container.decodeIfPresent(String.self, forKey: .sig)
        
        self.stateActor = EventStateActor(
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
        // For Codable compatibility, we need to provide synchronous encoding
        // This is a limitation - prefer using serialize() for async contexts
        throw NDKError.serializationFailed("Use serialize() method for async serialization")
    }

    // MARK: - Event ID Generation

    /// Generate event ID based on NIP-01
    public func generateID() async throws -> EventID {
        let serialized = try await serializeForID()
        let data = serialized.data(using: .utf8)!
        let hash = data.sha256()
        let id = hash.toHexString()
        await stateActor.setId(id)
        return id
    }

    /// Serialize event for ID generation according to NIP-01
    private func serializeForID() async throws -> String {
        // [0, pubkey, created_at, kind, tags, content]
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        
        let snapshot = await stateActor.getSnapshot()
        let array: [Any] = [
            0,
            snapshot.pubkey,
            snapshot.createdAt,
            snapshot.kind,
            snapshot.tags,
            snapshot.content
        ]

        let data = try JSONSerialization.data(withJSONObject: array, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Validation

    /// Validate event structure
    public func validate() async throws {
        let snapshot = await stateActor.getSnapshot()
        
        // Validate public key
        guard snapshot.pubkey.count == 64, snapshot.pubkey.allSatisfy({ $0.isHexDigit }) else {
            throw NDKError.invalidPublicKey(snapshot.pubkey)
        }

        // Validate ID if present
        if let id = snapshot.id {
            guard id.count == 64, id.allSatisfy({ $0.isHexDigit }) else {
                throw NDKError.invalidEventID(id)
            }

            // Verify ID matches content
            let calculatedID = try await generateID()
            guard id == calculatedID else {
                throw NDKError.invalidEventID("Event ID does not match content: \(id)")
            }
        }

        // Validate signature if present
        if let sig = snapshot.sig {
            guard sig.count == 128, sig.allSatisfy({ $0.isHexDigit }) else {
                throw NDKError.invalidSignature(sig)
            }
        }
    }

    // MARK: - Tag Helpers

    /// Get all tags of a specific type
    public func tags(withName name: String) async -> [Tag] {
        let allTags = await stateActor.getTags()
        return allTags.filter { $0.first == name }
    }

    /// Get the first tag of a specific type
    public func tag(withName name: String) async -> Tag? {
        let allTags = await stateActor.getTags()
        return allTags.first { $0.first == name }
    }

    /// Add a tag
    public func addTag(_ tag: Tag) async {
        await stateActor.addTag(tag)
    }

    /// Add a 'p' tag for mentioning a user
    /// 
    /// - Parameters:
    ///   - user: The user to mention
    ///   - marker: Optional marker like "reply" or "mention" (NIP-10)
    public func tag(user: NDKUser, marker: String? = nil) async {
        var tag = ["p", user.pubkey]
        if let marker = marker {
            tag.append(marker)
        }
        await addTag(tag)
    }

    /// Add an 'e' tag for referencing an event
    /// 
    /// - Parameters:
    ///   - event: The event to reference
    ///   - marker: Optional marker like "reply", "root", or "mention" (NIP-10)
    ///   - relay: Optional relay hint where this event can be found
    public func tag(event: NDKEvent, marker: String? = nil, relay: String? = nil) async {
        guard let eventID = await event.id else { return }
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
        await addTag(tag)
    }

    /// Generate content tags from the event's content
    /// 
    /// Automatically scans the content for:
    /// - Hashtags (#tag) → adds 't' tags
    /// - Nostr entities (npub1..., note1..., etc.) → adds 'p' or 'e' tags
    /// - URLs → preserves as-is
    /// 
    /// This method is called automatically during signing.
    public func generateContentTags() async {
        let currentContent = await stateActor.getContent()
        let currentTags = await stateActor.getTags()
        let contentTag = ContentTagger.generateContentTags(from: currentContent, existingTags: currentTags)
        await stateActor.setContent(contentTag.content)
        await stateActor.setTags(contentTag.tags)
    }

    /// Convenience method to set content and generate tags automatically
    public func setContent(_ newContent: String, generateTags: Bool = true) async {
        await stateActor.setContent(newContent)
        if generateTags {
            await generateContentTags()
        }
    }

    /// Get all referenced event IDs
    public var referencedEventIds: [EventID] {
        get async {
            let eTags = await tags(withName: "e")
            return eTags.compactMap { $0.count > 1 ? $0[1] : nil }
        }
    }

    /// Get all referenced pubkeys
    public var referencedPubkeys: [PublicKey] {
        get async {
            let pTags = await tags(withName: "p")
            return pTags.compactMap { $0.count > 1 ? $0[1] : nil }
        }
    }

    // MARK: - Equatable & Hashable
    
    /// Compares events by object identity rather than by their Nostr ID
    /// 
    /// This implementation uses object identity (`===`) for comparison, which means
    /// two `NDKEvent` instances with the same Nostr event ID will NOT be considered
    /// equal unless they are the exact same object instance in memory.
    /// 
    /// This approach is necessary because:
    /// 1. The event's properties are async and cannot be accessed in the synchronous `==` operator
    /// 2. It ensures consistent behavior with `Set<NDKEvent>` and dictionary keys
    /// 
    /// **Important**: To ensure predictable behavior, the event deduplication logic
    /// (such as in caches and subscriptions) should always return the same object
    /// instance for a given Nostr event ID. This makes the behavior of `==` and
    /// `Set<NDKEvent>` work as expected by most developers.
    public static func == (lhs: NDKEvent, rhs: NDKEvent) -> Bool {
        return lhs === rhs
    }

    /// Hashes the event using its object identity
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    // MARK: - Signing

    /// Sign this event using the NDK instance's signer
    /// 
    /// Performs the following steps:
    /// 1. Sets the pubkey from the signer if not already set
    /// 2. Generates content tags (hashtags, mentions, etc.)
    /// 3. Generates the event ID if not already set
    /// 4. Creates the signature using the configured signer
    /// 
    /// - Throws:
    ///   - `NDKError.notConfigured` if NDK instance or signer is not set
    ///   - Signing errors from the signer implementation
    /// 
    /// - Note: This method is automatically called by `NDK.publish()` if needed
    public func sign() async throws {
        guard let ndk = await stateActor.getNDK() else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }

        // Set pubkey from signer if not already set
        let currentPubkey = await stateActor.getPubkey()
        if currentPubkey.isEmpty {
            let signerPubkey = try await signer.pubkey
            await stateActor.setPubkey(signerPubkey)
        }

        // Generate content tags before signing
        await generateContentTags()

        // Generate ID if not already set
        if await stateActor.getId() == nil {
            _ = try await generateID()
        }

        // Sign the event
        let signature = try await signer.sign(self)
        await stateActor.setSig(signature)
    }

    // MARK: - Convenience

    /// Check if this event is a reply to another event
    public var isReply: Bool {
        get async {
            let allTags = await stateActor.getTags()
            return allTags.contains { tag in
                tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
            }
        }
    }

    /// Get the event ID this is replying to
    public var replyEventId: EventID? {
        get async {
            let allTags = await stateActor.getTags()
            let replyTag = allTags.first { tag in
                tag.count >= 4 && tag[0] == "e" && tag[3] == "reply"
            }
            return replyTag?.count ?? 0 > 1 ? replyTag?[1] : nil
        }
    }

    /// Check if this event is ephemeral
    public var isEphemeral: Bool {
        get async {
            let eventKind = await stateActor.getKind()
            return eventKind >= 20000 && eventKind < 30000
        }
    }

    /// Check if this event is replaceable
    public var isReplaceable: Bool {
        get async {
            let eventKind = await stateActor.getKind()
            // Kind 0 (metadata) and kind 3 (contacts) are replaceable
            // Also kinds 10000-19999 are replaceable
            return eventKind == 0 || eventKind == 3 || (eventKind >= 10000 && eventKind < 20000)
        }
    }

    /// Check if this event is parameterized replaceable
    public var isParameterizedReplaceable: Bool {
        get async {
            let eventKind = await stateActor.getKind()
            return eventKind >= 30000 && eventKind < 40000
        }
    }

    /// Get the tag address for replaceable events
    public var tagAddress: String {
        get async {
            let eventKind = await stateActor.getKind()
            let eventPubkey = await stateActor.getPubkey()
            let isPR = await isParameterizedReplaceable
            let isR = await isReplaceable
            
            if isPR {
                // Parameterized replaceable events
                let allTags = await stateActor.getTags()
                let dTag = allTags.first(where: { $0.count >= 2 && $0[0] == "d" })?[1] ?? ""
                return "\(eventKind):\(eventPubkey):\(dTag)"
            } else if isR {
                // Regular replaceable events
                return "\(eventKind):\(eventPubkey)"
            } else {
                return await stateActor.getId() ?? ""
            }
        }
    }

    /// Get the value of a tag by name
    public func tagValue(_ name: String) async -> String? {
        let foundTag = await tag(withName: name)
        return foundTag?.count ?? 0 > 1 ? foundTag?[1] : nil
    }

    // MARK: - Serialization

    /// Returns the raw event as a dictionary compatible with Nostr protocol
    /// This matches the rawEvent() method from @ndk/ndk-core
    public func rawEvent() async -> [String: Any] {
        let snapshot = await stateActor.getSnapshot()
        var result: [String: Any] = [
            "created_at": snapshot.createdAt,
            "content": snapshot.content,
            "tags": snapshot.tags,
            "kind": snapshot.kind,
            "pubkey": snapshot.pubkey
        ]

        if let id = snapshot.id {
            result["id"] = id
        }

        if let sig = snapshot.sig {
            result["sig"] = sig
        }

        return result
    }

    /// Serialize event to JSON string
    public func serialize() async throws -> String {
        // Create a temporary struct for serialization
        struct EventData: Codable {
            let id: EventID?
            let pubkey: PublicKey
            let created_at: Timestamp
            let kind: Kind
            let tags: [Tag]
            let content: String
            let sig: Signature?
        }
        
        let snapshot = await stateActor.getSnapshot()
        let eventData = EventData(
            id: snapshot.id,
            pubkey: snapshot.pubkey,
            created_at: snapshot.createdAt,
            kind: snapshot.kind,
            tags: snapshot.tags,
            content: snapshot.content,
            sig: snapshot.sig
        )
        
        return try JSONCoding.encodeToString(eventData)
    }

    /// Alias for serialize() - serialize event to JSON string
    public func toJSON() async throws -> String {
        return try await serialize()
    }

    // MARK: - Event Reactions

    /// React to this event with the given content
    /// 
    /// Creates a kind 7 reaction event that references this event.
    /// 
    /// - Parameters:
    ///   - content: The reaction content (e.g., "+", "-", "❤️", "🤙", "⚡")
    ///   - publish: Whether to automatically publish the reaction (default: true)
    /// 
    /// - Returns: The created reaction event
    /// 
    /// - Throws: Signing or publishing errors
    /// 
    /// ## Example
    /// ```swift
    /// // React with a heart emoji
    /// let reaction = try await event.react(content: "❤️")
    /// 
    /// // Create reaction without publishing
    /// let reaction = try await event.react(content: "👍", publish: false)
    /// ```
    public func react(content: String, publish: Bool = true) async throws -> NDKEvent {
        guard let ndk = await stateActor.getNDK() else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        guard ndk.signer != nil else {
            throw NDKError.notConfigured("No signer configured")
        }

        // Create the reaction event
        let reactionEvent = NDKEvent(
            pubkey: "", // Will be set by signer
            kind: EventKind.reaction,
            tags: [],
            content: content
        )

        reactionEvent.setNDK(ndk)

        // Tag this event
        await reactionEvent.tag(event: self)

        // Also tag the author of the event being reacted to
        let eventPubkey = await stateActor.getPubkey()
        await reactionEvent.tag(user: NDKUser(pubkey: eventPubkey))

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
    public func encode(includeRelays: Bool = false) async throws -> String {
        guard let eventId = await stateActor.getId() else {
            throw NDKError.invalidEventID("Event ID is required for encoding")
        }
        
        let eventKind = await stateActor.getKind()
        let eventPubkey = await stateActor.getPubkey()

        // For parameterized replaceable events, use naddr encoding
        if await isParameterizedReplaceable {
            let identifier = await tagValue("d") ?? ""
            let relays = includeRelays ? await getRelayHints() : nil
            return try Bech32.naddr(
                identifier: identifier,
                kind: eventKind,
                author: eventPubkey,
                relays: relays
            )
        }

        // For other replaceable events, use naddr encoding with empty identifier
        if await isReplaceable {
            let relays = includeRelays ? await getRelayHints() : nil
            return try Bech32.naddr(
                identifier: "",
                kind: eventKind,
                author: eventPubkey,
                relays: relays
            )
        }

        // For non-replaceable events, decide between note and nevent
        let hasMetadata = await hasMetadataWorthyOfNevent()
        if includeRelays || hasMetadata {
            let relays = includeRelays ? await getRelayHints() : nil
            return try Bech32.nevent(
                eventId: eventId,
                relays: relays,
                author: eventPubkey,
                kind: eventKind
            )
        } else {
            // Simple note encoding
            return try Bech32.note(from: eventId)
        }
    }

    /// Get relay hints for this event
    private func getRelayHints() async -> [String]? {
        var relays: [String] = []

        // Add relay where this event was received from
        if let relay = await stateActor.getRelay() {
            relays.append(relay.url)
        }

        // Add relays from NDK instance if available
        if let ndk = await stateActor.getNDK() {
            let ndkRelays = (await ndk.relays).prefix(3).map { $0.url }
            relays.append(contentsOf: ndkRelays)
        }

        // Remove duplicates and limit to 3 relays (as recommended by NIP-19)
        let uniqueRelays = Array(Set(relays)).prefix(3)
        return uniqueRelays.isEmpty ? nil : Array(uniqueRelays)
    }

    /// Check if this event has metadata that makes nevent encoding worthwhile
    private func hasMetadataWorthyOfNevent() async -> Bool {
        // Use nevent if the event has non-standard kind or has important tags
        let eventKind = await stateActor.getKind()
        let refEventIds = await referencedEventIds
        let refPubkeys = await referencedPubkeys
        return eventKind != EventKind.textNote || !refEventIds.isEmpty || !refPubkeys.isEmpty
    }
}

// MARK: - Character extension for hex validation

private extension Character {
    var isHexDigit: Bool {
        return ("0" ... "9").contains(self) || ("a" ... "f").contains(self) || ("A" ... "F").contains(self)
    }
}
