import Foundation

/// Builder pattern for creating and signing NDK events
/// 
/// This class provides a mutable interface for constructing events before they
/// are signed and become immutable. It handles content tag generation, ID
/// calculation, and signing.
/// 
/// ## Usage
/// ```swift
/// let event = try await NDKEventBuilder()
///     .content("Hello, Nostr!")
///     .kind(EventKind.textNote)
///     .tag(["t", "nostr"])
///     .build(signer: signer)
/// ```
public final class NDKEventBuilder {
    private var pubkey: PublicKey = ""
    private var createdAt: Timestamp = Timestamp(Date().timeIntervalSince1970)
    private var kind: Kind = EventKind.textNote
    private var tags: [Tag] = []
    private var content: String = ""
    
    // MARK: - Initialization
    
    public init() {}
    
    public convenience init(content: String) {
        self.init()
        self.content = content
    }
    
    // MARK: - Builder Methods
    
    /// Set the event content
    @discardableResult
    public func content(_ content: String) -> NDKEventBuilder {
        self.content = content
        return self
    }
    
    /// Set the event kind
    @discardableResult
    public func kind(_ kind: Kind) -> NDKEventBuilder {
        self.kind = kind
        return self
    }
    
    /// Set the public key
    @discardableResult
    public func pubkey(_ pubkey: PublicKey) -> NDKEventBuilder {
        self.pubkey = pubkey
        return self
    }
    
    /// Set the creation timestamp
    @discardableResult
    public func createdAt(_ timestamp: Timestamp) -> NDKEventBuilder {
        self.createdAt = timestamp
        return self
    }
    
    /// Set the creation timestamp using Date
    @discardableResult
    public func createdAt(_ date: Date) -> NDKEventBuilder {
        self.createdAt = Timestamp(date.timeIntervalSince1970)
        return self
    }
    
    /// Add a tag
    @discardableResult
    public func tag(_ tag: Tag) -> NDKEventBuilder {
        self.tags.append(tag)
        return self
    }
    
    /// Add multiple tags
    @discardableResult
    public func tags(_ tags: [Tag]) -> NDKEventBuilder {
        self.tags.append(contentsOf: tags)
        return self
    }
    
    /// Set all tags (replacing existing ones)
    @discardableResult
    public func setTags(_ tags: [Tag]) -> NDKEventBuilder {
        self.tags = tags
        return self
    }
    
    /// Add a 'p' tag for mentioning a user
    /// 
    /// - Parameters:
    ///   - pubkey: The user's public key to mention
    ///   - marker: Optional marker like "reply" or "mention" (NIP-10)
    ///   - relay: Optional relay hint
    @discardableResult
    public func tagUser(_ pubkey: PublicKey, marker: String? = nil, relay: String? = nil) -> NDKEventBuilder {
        var tag = ["p", pubkey]
        if let relay = relay {
            tag.append(relay)
        }
        if let marker = marker {
            if relay == nil {
                tag.append("") // Empty relay URL
            }
            tag.append(marker)
        }
        return self.tag(tag)
    }
    
    /// Add an 'e' tag for referencing an event
    /// 
    /// - Parameters:
    ///   - eventId: The event ID to reference
    ///   - marker: Optional marker like "reply", "root", or "mention" (NIP-10)
    ///   - relay: Optional relay hint where this event can be found
    @discardableResult
    public func tagEvent(_ eventId: EventID, marker: String? = nil, relay: String? = nil) -> NDKEventBuilder {
        var tag = ["e", eventId]
        if let relay = relay {
            tag.append(relay)
        }
        if let marker = marker {
            if relay == nil {
                tag.append("") // Empty relay URL
            }
            tag.append(marker)
        }
        return self.tag(tag)
    }
    
    /// Add a 't' tag for hashtags
    @discardableResult
    public func tagHashtag(_ hashtag: String) -> NDKEventBuilder {
        return self.tag(["t", hashtag])
    }
    
    /// Add a 'd' tag for replaceable events
    @discardableResult
    public func tagIdentifier(_ identifier: String) -> NDKEventBuilder {
        return self.tag(["d", identifier])
    }
    
    // MARK: - Content Tag Generation
    
    /// Generate content tags from the event's content
    /// 
    /// Automatically scans the content for:
    /// - Hashtags (#tag) → adds 't' tags
    /// - Nostr entities (npub1..., note1..., etc.) → adds 'p' or 'e' tags
    /// - URLs → preserves as-is
    /// 
    /// This method is called automatically during build unless disabled.
    @discardableResult
    public func generateContentTags() -> NDKEventBuilder {
        // For now, just return self until ContentTagger is updated
        // TODO: Implement content tag generation
        return self
    }
    
    // MARK: - Event Building
    
    /// Build and sign the event
    /// 
    /// - Parameters:
    ///   - signer: The signer to use for signing the event
    ///   - generateContentTags: Whether to automatically generate content tags (default: true)
    /// 
    /// - Returns: A signed, immutable NDKEvent
    /// 
    /// - Throws: Signing errors or validation errors
    public func build(signer: NDKSigner, generateContentTags: Bool = true) async throws -> NDKEvent {
        // Set pubkey from signer if not already set
        if pubkey.isEmpty {
            pubkey = try await signer.pubkey
        }
        
        // Generate content tags if requested
        if generateContentTags {
            _ = self.generateContentTags()
        }
        
        // Calculate event ID
        let eventId = try calculateEventID()
        
        // Sign the event
        let signature = try await signEvent(eventId: eventId, signer: signer)
        
        // Create the immutable event
        let event = NDKEvent(
            id: eventId,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: signature
        )
        
        // Validate the event
        try event.validate()
        
        return event
    }
    
    /// Build an unsigned event (for testing or manual signing)
    /// 
    /// - Parameters:
    ///   - eventId: The event ID to use
    ///   - signature: The signature to use
    ///   - generateContentTags: Whether to automatically generate content tags (default: true)
    /// 
    /// - Returns: An immutable NDKEvent
    /// 
    /// - Throws: Validation errors
    public func buildUnsigned(eventId: EventID, signature: Signature, generateContentTags: Bool = true) throws -> NDKEvent {
        // Generate content tags if requested
        if generateContentTags {
            _ = self.generateContentTags()
        }
        
        // Create the immutable event
        let event = NDKEvent(
            id: eventId,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: signature
        )
        
        // Validate the event
        try event.validate()
        
        return event
    }
    
    // MARK: - Private Helper Methods
    
    /// Calculate the event ID according to NIP-01
    private func calculateEventID() throws -> EventID {
        let serialized = try serializeForID()
        let data = serialized.data(using: .utf8)!
        let hash = data.sha256()
        return hash.toHexString()
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

        let data = try JSONSerialization.data(withJSONObject: array, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }
    
    /// Sign the event using the provided signer
    private func signEvent(eventId: EventID, signer: NDKSigner) async throws -> Signature {
        // Create a temporary event for signing
        let tempEvent = NDKEvent(
            id: eventId,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: "" // Empty signature for signing
        )
        
        return try await signer.sign(tempEvent)
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Create a text note event
    public static func textNote(_ content: String) -> NDKEventBuilder {
        return NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
    }
    
    /// Create a metadata event
    public static func metadata(_ content: String) -> NDKEventBuilder {
        return NDKEventBuilder()
            .content(content)
            .kind(EventKind.metadata)
    }
    
    /// Create a reaction event
    public static func reaction(_ content: String, to eventId: EventID, author: PublicKey) -> NDKEventBuilder {
        return NDKEventBuilder()
            .content(content)
            .kind(EventKind.reaction)
            .tagEvent(eventId)
            .tagUser(author)
    }
    
    /// Create a reply event
    public static func reply(_ content: String, to eventId: EventID, author: PublicKey) -> NDKEventBuilder {
        return NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .tagEvent(eventId, marker: "reply")
            .tagUser(author)
    }
    
    /// Create a repost event
    public static func repost(_ eventId: EventID, author: PublicKey, relay: String? = nil) -> NDKEventBuilder {
        return NDKEventBuilder()
            .kind(EventKind.repost)
            .tagEvent(eventId, relay: relay)
            .tagUser(author)
    }
    
    /// Create a deletion event
    public static func deletion(eventIds: [EventID], reason: String = "") -> NDKEventBuilder {
        var builder = NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
        
        for eventId in eventIds {
            builder = builder.tagEvent(eventId)
        }
        
        return builder
    }
    
    /// Create a parameterized replaceable event
    public static func parameterizedReplaceable(kind: Kind, identifier: String, content: String) -> NDKEventBuilder {
        guard kind >= 30000 && kind < 40000 else {
            fatalError("Kind \(kind) is not a parameterized replaceable event kind")
        }
        
        return NDKEventBuilder()
            .content(content)
            .kind(kind)
            .tagIdentifier(identifier)
    }
}