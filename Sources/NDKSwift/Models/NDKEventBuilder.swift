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
    private var createdAt: Timestamp = Timestamp.now
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
        self.createdAt = Timestamp.from(date)
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
    
    /// Add an 'e' tag for referencing an event (NIP-10 compliant)
    /// 
    /// This async version can use the NDK eventTracker to automatically determine
    /// relay hints from where the event was originally seen.
    /// 
    /// - Parameters:
    ///   - event: The event to reference
    ///   - marker: Optional marker like "reply", "root", or "mention" (NIP-10)
    ///   - preferredRelay: Optional relay hint override (takes precedence over tracked relay)
    ///   - ndk: NDK instance to get relay hints from eventTracker (optional)
    @discardableResult
    public func tagEvent(_ event: NDKEvent, marker: String? = nil, preferredRelay: String? = nil, ndk: NDK? = nil) async -> NDKEventBuilder {
        let relay: String
        
        if let preferredRelay = preferredRelay {
            // Use explicitly provided relay
            relay = preferredRelay
        } else if let ndkInstance = ndk {
            // Try to get relay hint from eventTracker
            let sourceRelay = await ndkInstance.eventTracker.getSourceRelay(eventId: event.id)
            relay = sourceRelay ?? ""
        } else {
            // No NDK available, use empty relay
            relay = ""
        }
        
        var tag = ["e", event.id]
        
        // Add relay hint (or empty string if we need to add marker/pubkey)
        if !relay.isEmpty {
            tag.append(relay)
        } else if marker != nil {
            tag.append("") // Empty relay URL
        }
        
        // Add marker
        if let marker = marker {
            tag.append(marker)
        }
        
        // Always add pubkey hint for NIP-10 compliance
        if marker != nil || !relay.isEmpty {
            // Ensure we have the right number of elements before adding pubkey
            while tag.count < 4 {
                tag.append("")
            }
            tag.append(event.pubkey)
        }
        
        return self.tag(tag)
    }
    
    /// Add a 'q' tag for quoting an event (NIP-10 compliant)
    /// 
    /// This async version can use the NDK eventTracker to automatically determine
    /// relay hints from where the event was originally seen.
    /// 
    /// - Parameters:
    ///   - event: The event to quote
    ///   - preferredRelay: Optional relay hint override (takes precedence over tracked relay)
    ///   - ndk: NDK instance to get relay hints from eventTracker (optional)
    @discardableResult
    public func quoteEvent(_ event: NDKEvent, preferredRelay: String? = nil, ndk: NDK? = nil) async -> NDKEventBuilder {
        // q tag format: ["q", <event-id>, <relay-url>, <pubkey>]
        var tag = ["q", event.id]
        
        let relay: String
        if let preferredRelay = preferredRelay {
            // Use explicitly provided relay
            relay = preferredRelay
        } else if let ndkInstance = ndk {
            // Try to get relay hint from eventTracker
            let sourceRelay = await ndkInstance.eventTracker.getSourceRelay(eventId: event.id)
            relay = sourceRelay ?? ""
        } else {
            // No NDK available, use empty relay
            relay = ""
        }
        
        // Add relay hint (or empty string)
        tag.append(relay)
        
        // Add pubkey hint for outbox model support
        tag.append(event.pubkey)
        
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
        let result = ContentTagger.generateContentTags(from: content, existingTags: tags)
        
        // Update content with normalized nostr: format
        self.content = result.content
        
        // Update tags with merged tags
        self.tags = result.tags
        
        return self
    }
    
    // MARK: - Encryption
    
    /// Encrypt the event content and build the event
    /// 
    /// This method encrypts the current content, sets it as the event content,
    /// and then builds and signs the event. This is a convenience method that
    /// combines encryption and building in one step.
    /// 
    /// - Parameters:
    ///   - recipient: The recipient to encrypt for (optional, defaults to signer's pubkey)
    ///   - signer: The signer to use for encryption and signing
    ///   - scheme: The encryption scheme to use (default: .nip44)
    /// 
    /// - Returns: A signed, immutable NDKEvent with encrypted content
    /// 
    /// - Throws: Encryption errors, signing errors, or validation errors
    /// 
    /// ## Usage
    /// ```swift
    /// // Encrypt to a specific recipient
    /// let event = try await NDKEventBuilder()
    ///     .content("Secret message")
    ///     .kind(EventKind.encryptedDirectMessage)
    ///     .encrypt(recipient: recipientUser, signer: signer)
    /// 
    /// // Encrypt to self (signer's pubkey)
    /// let event = try await NDKEventBuilder()
    ///     .content("Private note")
    ///     .kind(EventKind.cashuSpendingHistory)
    ///     .encrypt(signer: signer)
    /// ```
    @discardableResult
    public func encrypt(recipient: NDKUser? = nil, signer: NDKSigner, scheme: NDKEncryptionScheme = .nip44) async throws -> NDKEvent {
        // Use provided recipient or create one from signer's pubkey
        let encryptionRecipient: NDKUser
        if let recipient = recipient {
            encryptionRecipient = recipient
        } else {
            let signerPubkey = try await signer.pubkey
            encryptionRecipient = NDKUser(pubkey: signerPubkey)
        }
        
        // Encrypt the current content
        let encryptedContent = try await signer.encrypt(
            recipient: encryptionRecipient,
            value: content,
            scheme: scheme
        )
        
        // Update content with encrypted value
        self.content = encryptedContent
        
        // Build and return the event (don't generate content tags for encrypted content)
        return try await build(signer: signer, generateContentTags: false)
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
    /// 
    /// - Parameters:
    ///   - content: The reaction content (e.g., "+", "-", "❤️")
    ///   - event: The event to react to
    ///   - ndk: Optional NDK instance for relay hints
    public static func reaction(_ content: String, to event: NDKEvent, ndk: NDK? = nil) async -> NDKEventBuilder {
        let builder = NDKEventBuilder()
            .content(content)
            .kind(EventKind.reaction)
            .tagUser(event.pubkey)
            .tag(["k", String(event.kind)])
        
        await builder.tagEvent(event, ndk: ndk)
        return builder
    }
    
    /// Create a reply event
    /// 
    /// - Parameters:
    ///   - content: The reply content
    ///   - event: The event to reply to
    ///   - ndk: Optional NDK instance for relay hints
    public static func reply(_ content: String, to event: NDKEvent, ndk: NDK? = nil) async -> NDKEventBuilder {
        let builder = NDKEventBuilder()
            .content(content)
            .kind(EventKind.textNote)
            .tagUser(event.pubkey)
        
        await builder.tagEvent(event, marker: "reply", ndk: ndk)
        return builder
    }
    
    /// Create a quote event (text note with q tag)
    /// 
    /// This creates a kind 1 text note that quotes another event.
    /// The event reference is added to the content and a q-tag is included.
    /// 
    /// - Parameters:
    ///   - comment: The comment text to add before the quote
    ///   - event: The event to quote
    ///   - ndk: Optional NDK instance for relay hints
    public static func quote(_ comment: String, event: NDKEvent, ndk: NDK? = nil) async throws -> NDKEventBuilder {
        // Create nevent/note reference
        let reference = try event.encode()
        let fullContent = "\(comment)\n\nnostr:\(reference)"
        
        let builder = NDKEventBuilder()
            .content(fullContent)
            .kind(EventKind.textNote)
        
        await builder.quoteEvent(event, ndk: ndk)
        return builder
    }
    
    /// Create a repost event (automatically chooses kind 6 for text notes, kind 16 for others)
    /// 
    /// - Parameters:
    ///   - event: The event to repost
    ///   - includeContent: Whether to include the full event JSON in content
    ///   - ndk: Optional NDK instance for relay hints
    public static func repost(_ event: NDKEvent, includeContent: Bool = true, ndk: NDK? = nil) async -> NDKEventBuilder {
        // Determine repost kind based on original event kind
        let repostKind = event.kind == EventKind.textNote ? EventKind.repost : EventKind.genericRepost
        
        // Set content to JSON stringified event (unless it's protected)
        let content: String
        if includeContent && !event.isProtected {
            content = (try? event.serialize()) ?? ""
        } else {
            content = ""
        }
        
        var builder = NDKEventBuilder()
            .content(content)
            .kind(repostKind)
            .tagUser(event.pubkey)
        
        await builder.tagEvent(event, ndk: ndk)
        
        // For non-text events, add k tag with original kind
        if event.kind != EventKind.textNote {
            builder = builder.tag(["k", String(event.kind)])
        }
        
        return builder
    }
    
    /// Create a deletion event for multiple events with their kinds
    public static func deletion(events: [(id: EventID, kind: Kind)], reason: String = "") -> NDKEventBuilder {
        var builder = NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
        
        for event in events {
            builder = builder
                .tag(["e", event.id])
                .tag(["k", String(event.kind)])
        }
        
        return builder
    }
    
    /// Create a deletion event for a single event
    /// 
    /// - Parameters:
    ///   - event: The event to delete
    ///   - reason: The reason for deletion
    ///   - ndk: Optional NDK instance for relay hints
    public static func deletion(event: NDKEvent, reason: String = "", ndk: NDK? = nil) async -> NDKEventBuilder {
        let builder = NDKEventBuilder()
            .content(reason)
            .kind(EventKind.deletion)
            .tag(["k", String(event.kind)])
        
        await builder.tagEvent(event, ndk: ndk)
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