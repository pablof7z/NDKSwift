import Foundation

// MARK: - Client Tag Configuration

/// Configuration for automatic client tagging (NIP-89)
public struct NDKClientTagConfig {
    /// The name of the client (e.g., "Nutsack", "Damus", "Primal")
    public let name: String

    /// The NIP-89 handler address in format "31990:pubkey:identifier"
    public let address: String?

    /// Optional relay hint for finding the handler event
    public let relay: String?

    /// Whether to automatically add client tags to all events (default: true)
    public let autoTag: Bool

    /// Event kinds that should not receive client tags (defaults to empty)
    public let excludedKinds: Set<Kind>

    public init(
        name: String,
        address: String? = nil,
        relay: String? = nil,
        autoTag: Bool = true,
        excludedKinds: Set<Kind> = []
    ) {
        self.name = name
        self.address = address
        self.relay = relay
        self.autoTag = autoTag
        self.excludedKinds = excludedKinds
    }
}

/// Builder pattern for creating and signing NDK events
///
/// This class provides a mutable interface for constructing events before they
/// are signed and become immutable. It handles content tag generation, ID
/// calculation, and signing.
///
/// ## Usage
/// ```swift
/// let event = try await NDKEventBuilder(ndk: ndk)
///     .content("Hello, Nostr!")
///     .kind(EventKind.textNote)
///     .tag(["t", "nostr"])
///     .build()
/// ```
public final class NDKEventBuilder {
    private var pubkey: PublicKey = ""
    private var createdAt: Timestamp = Timestamp.now
    public private(set) var kind: Kind = EventKind.textNote
    public private(set) var tags: [Tag] = []
    public private(set) var content: String = ""
    private weak var ndk: NDK?

    // MARK: - Static reference to shared NDK instance
    private static weak var sharedNDK: NDK?

    /// Set the shared NDK instance for all builders
    internal static func setSharedNDK(_ ndk: NDK) {
        sharedNDK = ndk
    }

    // MARK: - Initialization

    /// Initialize a new event builder
    public init(ndk: NDK) {
        self.ndk = ndk
    }

    /// Convenience initializer with content
    public convenience init(content: String, ndk: NDK) {
        self.init(ndk: ndk)
        self.content = content
    }

    /// Create a reply event builder for NIP-22 comments
    ///
    /// This method creates a properly configured event builder for replying to any event.
    /// It automatically handles:
    /// - Setting kind to 1111 (generic reply) for non-kind-1 events
    /// - Propagating uppercase tags (A, E, I, K, P) from parent comments
    /// - Adding proper lowercase tags (a, e, i, k, p) for the direct parent
    /// - Following NIP-22 threading conventions
    ///
    /// ## Usage
    /// ```swift
    /// let comment = try await NDKEventBuilder.reply(to: blogPost, ndk: ndk)
    ///     .content("Great article!")
    ///     .build()
    /// ```
    ///
    /// - Parameters:
    ///   - event: The event to reply to
    ///   - ndk: The NDK instance
    /// - Returns: An NDKEventBuilder configured for the reply
    public static func reply(to event: NDKEvent, ndk: NDK) -> NDKEventBuilder {
        let builder = NDKEventBuilder(ndk: ndk)

        // For kind 1 events, use standard kind 1 replies
        if event.kind == EventKind.textNote {
            builder.kind(EventKind.textNote)

            // Standard NIP-10 reply tags
            if event.tags.contains(where: { $0.first == NostrConstants.TagName.event }) {
                // Copy existing e-tags and p-tags
                for tag in event.tags {
                    if tag.first == NostrConstants.TagName.event || tag.first == NostrConstants.TagName.pubkey {
                        builder.tag(tag)
                    }
                }
                // Add reference to the event we're replying to
                builder.tag([NostrConstants.TagName.event, event.id, "", NostrConstants.Marker.reply])
                builder.tag([NostrConstants.TagName.pubkey, event.pubkey])
            } else {
                // This is a root event, tag it as such
                builder.tag([NostrConstants.TagName.event, event.id, "", NostrConstants.Marker.root])
                builder.tag([NostrConstants.TagName.pubkey, event.pubkey])
            }
        } else {
            // NIP-22 generic reply for all other kinds
            builder.kind(EventKind.genericReply)

            // Check if the parent event has uppercase tags (indicating it's a comment)
            let hasUppercaseTags = event.tags.contains { tag in
                ["A", "E", "I", "K", "P"].contains(tag.first)
            }

            if hasUppercaseTags {
                // Parent is a comment - copy its uppercase tags
                for tag in event.tags {
                    if ["A", "E", "I", "K", "P"].contains(tag.first) {
                        builder.tag(tag)
                    }
                }
            } else {
                // Parent is a root event - create new uppercase tags
                let tagReference = event.tagReference()
                let uppercaseTag = [tagReference[0].uppercased()] + Array(tagReference.dropFirst())
                builder.tag(uppercaseTag)

                // Add K tag for root kind
                builder.tag(["K", String(event.kind)])

                // Add P tag for root author
                builder.tag(["P", event.pubkey])
            }

            // Add lowercase tags for the direct parent
            let parentReference = event.tagReference()
            builder.tag(parentReference)

            // Add k tag for parent kind
            builder.tag([NostrConstants.TagName.kind, String(event.kind)])

            // Add p tag for parent author
            builder.tag([NostrConstants.TagName.pubkey, event.pubkey])

            // Carry over all p tags from parent
            for tag in event.tags where tag.first == NostrConstants.TagName.pubkey {
                if let tagValue = tag.value, tagValue != event.pubkey {
                    builder.tag(tag)
                }
            }
        }

        return builder
    }

    // MARK: - Builder Methods

    /// Set the event content with optional automatic imeta tag extraction
    /// - Parameters:
    ///   - content: The event content
    ///   - extractImeta: Whether to automatically extract media URLs and create imeta tags (default: true)
    @discardableResult
    public func content(_ content: String, extractImeta: Bool = true) -> NDKEventBuilder {
        self.content = content

        if extractImeta {
            // Extract media URLs and create basic imeta tags
            let urls = extractMediaURLs(from: content)
            for url in urls where !hasImetaTag(for: url) {
                let imeta = NDKImetaTag(url: url)
                self.tags.append(ImetaUtils.imetaTagToTag(imeta))
            }
        }

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
        guard ValidationHelpers.isValid32ByteHex(pubkey) else {
            NDKLogger.log(.warning, category: .event, "Invalid public key provided to NDKEventBuilder: \(pubkey)")
            return self
        }
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
        guard !tag.isEmpty else {
            NDKLogger.log(.warning, category: .event, "Attempted to add empty tag to NDKEventBuilder")
            return self
        }
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
    public func tagUser(_ pubkey: PublicKey, marker: String? = nil, relay: String? = nil) async -> NDKEventBuilder {
        var tag = [NostrConstants.TagName.pubkey, pubkey]

        // Determine relay hint
        let relayHint: String
        if let relay = relay {
            // Use explicitly provided relay
            relayHint = relay
        } else if let ndk = self.ndk {
            // Try to get relay hint from user's relay list or outbox
            if let outboxItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: pubkey, type: .read),
               let firstRelay = outboxItem.readRelays.first?.url {
                relayHint = firstRelay
            } else {
                relayHint = ""
            }
        } else {
            relayHint = ""
        }

        if !relayHint.isEmpty {
            tag.append(relayHint)
        } else if marker != nil {
            tag.append("") // Empty relay URL if we need to add marker
        }

        if let marker = marker {
            tag.append(marker)
        }

        return self.tag(tag)
    }

    /// Add an appropriate tag for referencing an event (NIP-10 compliant)
    ///
    /// This method intelligently determines the correct tag type:
    /// - For replaceable/parameterized replaceable events: Uses 'a' tag
    /// - For regular events: Uses 'e' tag
    ///
    /// This async version can use the NDK eventTracker to automatically determine
    /// relay hints from where the event was originally seen.
    ///
    /// - Parameters:
    ///   - event: The event to reference
    ///   - marker: Optional marker like "reply", "root", or "mention" (NIP-10) - only used for 'e' tags
    ///   - preferredRelay: Optional relay hint override (takes precedence over tracked relay)
    ///   - ndk: NDK instance to get relay hints from eventTracker (optional)
    @discardableResult
    public func tagEvent(_ event: NDKEvent, marker: String? = nil, preferredRelay: String? = nil) async -> NDKEventBuilder {
        // Check if this is a replaceable or parameterized replaceable event
        if event.isReplaceable || event.isParameterizedReplaceable {
            // Use 'a' tag for replaceable events
            return await self.tagAddressableEvent(event, preferredRelay: preferredRelay)
        }

        // Otherwise, use 'e' tag for regular events
        return await self.tagRegularEvent(event, marker: marker, preferredRelay: preferredRelay)
    }

    /// Add an 'e' tag for referencing a regular (non-replaceable) event.
    ///
    /// - Parameters:
    ///   - event: The event to reference
    ///   - marker: Optional marker like "reply", "root", or "mention" (NIP-10)
    ///   - preferredRelay: Optional relay hint override
    /// - Returns: Self for method chaining
    @discardableResult
    public func tagRegularEvent(_ event: NDKEvent, marker: String? = nil, preferredRelay: String? = nil) async -> NDKEventBuilder {
        let relay: String

        if let preferredRelay = preferredRelay {
            // Use explicitly provided relay
            relay = preferredRelay
        } else if let ndk = self.ndk {
            // Try to get relay hint from eventTracker
            let sourceRelay = await ndk.eventTracker.getSourceRelay(eventId: event.id)
            relay = sourceRelay ?? ""
        } else {
            // No NDK available, use empty relay
            relay = ""
        }

        var tag = [NostrConstants.TagName.event, event.id]

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

    /// Add a 'q' tag for quoting an event (NIP-10 compliant).
    ///
    /// - Parameters:
    ///   - event: The event to quote
    ///   - preferredRelay: Optional relay hint override
    /// - Returns: Self for method chaining
    @discardableResult
    public func quoteEvent(_ event: NDKEvent, preferredRelay: String? = nil) async -> NDKEventBuilder {
        // q tag format: ["q", <event-id>, <relay-url>, <pubkey>]
        var tag = ["q", event.id]

        let relay: String
        if let preferredRelay = preferredRelay {
            // Use explicitly provided relay
            relay = preferredRelay
        } else if let ndk = self.ndk {
            // Try to get relay hint from eventTracker
            let sourceRelay = await ndk.eventTracker.getSourceRelay(eventId: event.id)
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
    public func dTag(_ identifier: String) -> NDKEventBuilder {
        return self.tag(["d", identifier])
    }

    /// Add a 'client' tag for NIP-89 client identification
    ///
    /// This tag identifies the client that published the event, providing a way for
    /// other clients to discover and recommend applications that handle specific event kinds.
    ///
    /// - Parameters:
    ///   - name: The name of the client (e.g., "Nutsack", "Damus", "Primal")
    ///   - address: The NIP-89 handler address in format "31990:pubkey:identifier"
    ///   - relay: Optional relay hint for finding the handler event
    ///
    /// - Returns: Self for chaining
    ///
    /// ## Usage
    /// ```swift
    /// let event = try await NDKEventBuilder(ndk: ndk)
    ///     .content("Hello from my client!")
    ///     .clientTag(name: "Nutsack", address: "31990:abc123:nutsack-ios", relay: RelayConstants.example)
    ///     .build()
    /// ```
    @discardableResult
    public func clientTag(name: String, address: String? = nil, relay: String? = nil) -> NDKEventBuilder {
        var tag = [NostrConstants.TagName.client, name]

        // Add address if provided
        if let address = address, !address.isEmpty {
            tag.append(address)
        } else {
            // Add empty address to maintain tag structure if relay is provided
            if relay != nil {
                tag.append("")
            }
        }

        // Add relay if provided
        if let relay = relay {
            tag.append(relay)
        }

        return self.tag(tag)
    }

    /// Add a tag for any bech32-encoded Nostr entity
    ///
    /// Automatically decodes the bech32 string and creates the appropriate tag:
    /// - npub → 'p' tag
    /// - note → 'e' tag
    /// - naddr → 'a' tag (with coordinate format)
    /// - nevent → 'e' tag with relay and author hints
    /// - nprofile → 'p' tag with relay hints
    ///
    /// This is useful when you have a bech32 string but not the full event object.
    /// The content parser uses this internally when processing nostr: URIs.
    ///
    /// - Parameter bech32: The bech32-encoded entity (npub, note, naddr, etc.)
    /// - Returns: Self for chaining
    @discardableResult
    public func tagBech32(_ bech32String: String) async -> NDKEventBuilder {
        do {
            // Determine the type by prefix
            if bech32String.hasPrefix(NostrConstants.npubPrefix) {
                // Decode npub to get public key
                if let pubkey = try? PublicKey.fromNpub(bech32String) {
                    return await self.tagUser(pubkey)
                }

            } else if bech32String.hasPrefix(NostrConstants.notePrefix) {
                // Decode note to get event ID
                let eventId = try Bech32.eventId(from: bech32String)
                return self.tag([NostrConstants.TagName.event, eventId])

            } else if bech32String.hasPrefix(NostrConstants.naddrPrefix) {
                // For naddr, we need to parse the TLV data manually
                let (hrp, data) = try Bech32.decode(bech32String)
                guard hrp == "naddr" else { return self }

                var identifier: String?
                var relays: [String] = []
                var author: String?
                var kind: Int?

                // Parse TLV data
                var index = 0
                while index < data.count {
                    guard index + 1 < data.count else { break }

                    let type = data[index]
                    let length = Int(data[index + 1])
                    index += 2

                    guard index + length <= data.count else { break }

                    let value = Array(data[index..<index + length])

                    switch type {
                    case 0: // Identifier
                        identifier = String(bytes: value, encoding: .utf8)
                    case 1: // Relay
                        if let relay = String(bytes: value, encoding: .utf8) {
                            relays.append(relay)
                        }
                    case 2: // Author (32 bytes)
                        if value.count == 32 {
                            author = Data(value).hexString
                        }
                    case 3: // Kind (4 bytes big-endian)
                        if value.count == 4 {
                            kind = Int(value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                        }
                    default:
                        break
                    }

                    index += length
                }

                // Build the coordinate
                if let author = author, let kind = kind {
                    let coordinate = "\(kind):\(author):\(identifier ?? "")"
                    var tag = [NostrConstants.TagName.address, coordinate]
                    if let firstRelay = relays.first {
                        tag.append(firstRelay)
                    } else {
                        tag.append("")
                    }
                    return self.tag(tag)
                }

            } else if bech32String.hasPrefix(NostrConstants.neventPrefix) {
                // For nevent, parse TLV data
                let (hrp, data) = try Bech32.decode(bech32String)
                guard hrp == "nevent" else { return self }

                var eventId: String?
                var relays: [String] = []
                var author: String?

                // Parse TLV data
                var index = 0
                while index < data.count {
                    guard index + 1 < data.count else { break }

                    let type = data[index]
                    let length = Int(data[index + 1])
                    index += 2

                    guard index + length <= data.count else { break }

                    let value = Array(data[index..<index + length])

                    switch type {
                    case 0: // Event ID (32 bytes)
                        if value.count == 32 {
                            eventId = Data(value).hexString
                        }
                    case 1: // Relay
                        if let relay = String(bytes: value, encoding: .utf8) {
                            relays.append(relay)
                        }
                    case 2: // Author (32 bytes)
                        if value.count == 32 {
                            author = Data(value).hexString
                        }
                    default:
                        break
                    }

                    index += length
                }

                // Build the e tag
                if let eventId = eventId {
                    var tag = [NostrConstants.TagName.event, eventId]

                    // Add relay hint
                    if let firstRelay = relays.first {
                        tag.append(firstRelay)
                    } else {
                        tag.append("")
                    }

                    // Add author hint if present
                    if let author = author {
                        // Ensure we have marker position
                        if tag.count == 3 {
                            tag.append("") // Empty marker
                        }
                        tag.append(author)
                    }

                    return self.tag(tag)
                }

            } else if bech32String.hasPrefix(NostrConstants.nprofilePrefix) {
                // For nprofile, parse TLV data
                let (hrp, data) = try Bech32.decode(bech32String)
                guard hrp == "nprofile" else { return self }

                var pubkey: String?
                var relays: [String] = []

                // Parse TLV data
                var index = 0
                while index < data.count {
                    guard index + 1 < data.count else { break }

                    let type = data[index]
                    let length = Int(data[index + 1])
                    index += 2

                    guard index + length <= data.count else { break }

                    let value = Array(data[index..<index + length])

                    switch type {
                    case 0: // Pubkey (32 bytes)
                        if value.count == 32 {
                            pubkey = Data(value).hexString
                        }
                    case 1: // Relay
                        if let relay = String(bytes: value, encoding: .utf8) {
                            relays.append(relay)
                        }
                    default:
                        break
                    }

                    index += length
                }

                // Build the p tag
                if let pubkey = pubkey {
                    var tag = [NostrConstants.TagName.pubkey, pubkey]
                    if let firstRelay = relays.first {
                        tag.append(firstRelay)
                    }
                    return self.tag(tag)
                }
            }
        } catch {
            // Failed to decode, ignore silently
        }

        return self
    }

    /// Add an 'a' tag for referencing a replaceable or parameterized replaceable event
    ///
    /// This method intelligently determines the correct tag structure based on the event type:
    /// - For parameterized replaceable events (30000-39999): ["a", "<kind>:<pubkey>:<d-tag>", <relay-url>]
    /// - For regular replaceable events (10000-19999): ["a", "<kind>:<pubkey>:", <relay-url>]
    /// - For regular events: Falls back to using 'e' tag via tagEvent()
    ///
    /// - Parameters:
    ///   - event: The event to reference
    ///   - preferredRelay: Optional relay hint override (takes precedence over tracked relay)
    ///   - ndk: NDK instance to get relay hints from eventTracker (optional)
    @discardableResult
    public func tagAddressableEvent(_ event: NDKEvent, preferredRelay: String? = nil) async -> NDKEventBuilder {
        // Check if this is a replaceable or parameterized replaceable event
        if event.isReplaceable || event.isParameterizedReplaceable {
            // Build the coordinate (address)
            let coordinate = event.tagAddress
            var tag = [NostrConstants.TagName.address, coordinate]

            // Determine relay hint
            let relay: String
            if let preferredRelay = preferredRelay {
                // Use explicitly provided relay
                relay = preferredRelay
            } else if let ndk = self.ndk {
                // Try to get relay hint from eventTracker
                let sourceRelay = await ndk.eventTracker.getSourceRelay(eventId: event.id)
                relay = sourceRelay ?? ""
            } else {
                // No NDK available, use empty relay
                relay = ""
            }

            // Add relay hint (or empty string)
            tag.append(relay)

            return self.tag(tag)
        } else {
            // For regular events, fall back to 'e' tag
            return await self.tagEvent(event, marker: nil, preferredRelay: preferredRelay)
        }
    }

    // MARK: - Content Tag Generation

    /// Generate content tags from the event's content
    ///
    /// Automatically scans the content for:
    /// - Hashtags (#tag) → adds 't' tags
    /// - Nostr entities (npub1..., note1..., etc.) → adds appropriate tags ('p', 'e', 'a', 'q')
    /// - URLs → preserves as-is
    ///
    /// This method is called automatically during build unless disabled.
    /// Uses the NDK context (if available) to add intelligent relay hints.
    @discardableResult
    public func generateContentTags() async -> NDKEventBuilder {
        let (entities, normalizedContent) = ContentParser.parseContent(content)

        // Update content with normalized nostr: format
        self.content = normalizedContent

        // Process entities and generate tags
        for entity in entities {
            switch entity {
            case .npub(let bech32):
                await self.tagBech32(bech32)
            case .nprofile(let bech32):
                await self.tagBech32(bech32)
            case .note(let bech32):
                await self.tagBech32(bech32)
            case .nevent(let bech32):
                await self.tagBech32(bech32)
            case .naddr(let bech32):
                await self.tagBech32(bech32)
            case .hashtag(let tag):
                self.tagHashtag(tag.lowercased()) // NIP-24: hashtags must be lowercase
            case .userMention(let pubkey, _):
                // These are already handled by #[index] references in tags
                await self.tagUser(pubkey)
            case .eventMention(let eventId):
                // These are already handled by #[index] references in tags
                self.tag([NostrConstants.TagName.event, eventId])
            case .text(_), .url(_):
                // These don't generate tags
                break
            }
        }

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
    /// let event = try await NDKEventBuilder(ndk: ndk)
    ///     .content("Secret message")
    ///     .kind(EventKind.encryptedDirectMessage)
    ///     .encrypt(recipient: recipientUser, signer: signer)
    ///
    /// // Encrypt to self (signer's pubkey)
    /// let event = try await NDKEventBuilder(ndk: ndk)
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
    public func build(signer: NDKSigner? = nil, generateContentTags: Bool = true) async throws -> NDKEvent {
        // Use provided signer or fall back to NDK's signer
        let actualSigner = try GuardHelpers.unwrap(
            signer ?? ndk?.signer,
            error: NDKError.configurationError(ErrorMessageConstants.Messages.noSignerAvailable)
        )
        // Set pubkey from signer if not already set
        if pubkey.isEmpty {
            pubkey = try await actualSigner.pubkey
        }

        // Apply automatic client tagging if configured
        if let clientConfig = ndk?.clientTagConfig,
           clientConfig.autoTag,
           !clientConfig.excludedKinds.contains(kind),
           !tags.contains(where: { $0.first == NostrConstants.TagName.client }) {

            // Add client tag - address is optional
            _ = self.clientTag(name: clientConfig.name, address: clientConfig.address, relay: clientConfig.relay)
        }

        // Generate content tags if requested
        if generateContentTags {
            _ = await self.generateContentTags()
        }

        // Create temporary event to calculate ID
        let tempEvent = NDKEvent(
            id: "",  // Temporary ID
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""  // Temporary signature
        )
        
        // Calculate event ID using NDKEvent's method
        let eventId = try tempEvent.calculateID()

        // Sign the event
        let signature = try await signEvent(eventId: eventId, signer: actualSigner)

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
    public func buildUnsigned(eventId: EventID, signature: Signature, generateContentTags: Bool = true) async throws -> NDKEvent {
        // Generate content tags if requested
        if generateContentTags {
            _ = await self.generateContentTags()
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

    // Event ID calculation is now delegated to NDKEvent.calculateID()
    // This ensures a single source of truth for ID generation logic

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

    // Media functionality moved to NDKEventBuilder+Media.swift

    // NIP-68 and media methods moved to NDKEventBuilder+Media.swift

    // MARK: - Private Helpers

    /// Extract media URLs from content based on file extensions
    private func extractMediaURLs(from content: String) -> [String] {
        // Pattern to match URLs with common media file extensions
        let pattern = #"https?://[^\s]+\.(?:jpg|jpeg|png|gif|webp|bmp|svg|mp4|mp3|webm|mov|avi|mkv|flv|wmv|m4v|m4a|ogg|wav|flac|aac|opus|pdf)(?:\?[^\s]*)?"#

        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let matches = regex?.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)) ?? []

        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }

    /// Check if an imeta tag already exists for a given URL
    private func hasImetaTag(for url: String) -> Bool {
        return tags.contains { tag in
            guard tag.first == "imeta" else { return false }

            // Check if any imeta tag contains this URL
            return tag.contains { component in
                component.hasPrefix("url ") && component.dropFirst(4) == url
            }
        }
    }
}