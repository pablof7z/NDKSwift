
/// Protocol for objects that can be stored in an NDKList
public protocol NDKListItem {
    /// Convert this item to a Tag for storage in a list
    func toListTag() async -> Tag

    /// The reference value used to identify this item in a list
    var reference: String { get async }
}

/// Represents an item in a list with optional marking and position
public struct NDKListEntry {
    public let item: NDKListItem
    public let mark: String?
    public let encrypted: Bool
    public let position: ListPosition

    public init(item: NDKListItem, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) {
        self.item = item
        self.mark = mark
        self.encrypted = encrypted
        self.position = position
    }
}

/// Position for adding items to a list
public enum ListPosition {
    case top
    case bottom
}

/// Base class for all Nostr lists following NIP-51
/// Provides a unified interface for managing different types of lists
public class NDKList {
    // MARK: - NDKEvent Properties

    /// Unique event ID (32-byte hash)
    public var id: EventID?

    /// Public key of the event creator
    public var pubkey: PublicKey = ""

    /// Unix timestamp when the event was created
    public var createdAt: Timestamp = 0

    /// Event kind
    public var kind: Kind = 0

    /// Event tags
    public var tags: [Tag] = []

    /// Event content
    public var content: String = ""

    /// Event signature
    public var signature: Signature?

    /// Reference to NDK instance
    public weak var ndk: NDK?

    /// Supported list kinds from NIP-51 and related NIPs
    public static let supportedKinds: Set<Int> = [
        EventKind.contacts, // Contact list
        EventKind.muteList, // Mute list
        EventKind.pinList, // Pin list
        EventKind.relayList, // Relay list
        EventKind.bookmarkList, // Bookmark list
        EventKind.communitiesList, // Communities list
        EventKind.publicChatsList, // Public chats list
        EventKind.blockedRelays, // Blocked relays list
        EventKind.searchRelays, // Search relays list
        EventKind.interestList, // Interest list
        EventKind.userEmojiList, // User emoji list
        EventKind.categorizedPeopleList, // Categorized people list
        EventKind.categorizedBookmarkList, // Categorized bookmark list
        EventKind.relayListMetadata, // Relay list metadata
        EventKind.blossomServerList, // Blossom server list
    ]

    /// Initialize a new list
    public init(ndk: NDK? = nil) {
        self.ndk = ndk
        createdAt = Timestamp.now
    }

    /// Initialize a new list with the specified kind
    public convenience init(ndk: NDK? = nil, kind: Int) {
        self.init(ndk: ndk)
        self.kind = kind
    }

    /// The title of this list
    public var title: String? {
        get {
            // First check for explicit title tag
            if let titleTag = tags.first(where: { !$0.isEmpty && ($0[0] == NostrConstants.TagName.title || $0[0] == NostrConstants.TagName.name) }) {
                return titleTag.count > 1 ? titleTag[1] : nil
            }

            // Fall back to kind-specific defaults
            return defaultTitleForKind
        }
        set {
            // Remove existing title/name tags
            tags.removeAll { !$0.isEmpty && ($0[0] == NostrConstants.TagName.title || $0[0] == NostrConstants.TagName.name) }

            // Add new title if provided
            if let title = newValue, !title.isEmpty {
                tags.append([NostrConstants.TagName.title, title])
            }
        }
    }

    /// Default title based on the list kind
    private var defaultTitleForKind: String? {
        switch kind {
        case EventKind.contacts: return "Contacts"
        case EventKind.muteList: return "Muted"
        case EventKind.pinList: return "Pinned"
        case EventKind.relayList: return "Relays"
        case EventKind.bookmarkList: return "Bookmarks"
        case EventKind.communitiesList: return "Communities"
        case EventKind.publicChatsList: return "Public Chats"
        case EventKind.blockedRelays: return "Blocked Relays"
        case EventKind.searchRelays: return "Search Relays"
        case EventKind.interestList: return "Interests"
        case EventKind.userEmojiList: return "Emojis"
        case EventKind.categorizedPeopleList: return "People"
        case EventKind.categorizedBookmarkList: return "Bookmarks"
        case EventKind.relayListMetadata: return "Relay Metadata"
        case EventKind.blossomServerList: return "Blossom Servers"
        default: return nil
        }
    }

    /// Description of this list
    public var listDescription: String? {
        get {
            let descTag = tags.first { !$0.isEmpty && $0[0] == NostrConstants.TagName.description }
            return (descTag?.count ?? 0) > 1 ? descTag?[1] : nil
        }
        set {
            tags.removeAll { !$0.isEmpty && $0[0] == NostrConstants.TagName.description }
            if let description = newValue, !description.isEmpty {
                tags.append([NostrConstants.TagName.description, description])
            }
        }
    }

    /// Image URL for this list
    public var image: String? {
        get {
            let imageTag = tags.first { !$0.isEmpty && $0[0] == NostrConstants.TagName.image }
            return (imageTag?.count ?? 0) > 1 ? imageTag?[1] : nil
        }
        set {
            tags.removeAll { !$0.isEmpty && $0[0] == NostrConstants.TagName.image }
            if let image = newValue, !image.isEmpty {
                tags.append([NostrConstants.TagName.image, image])
            }
        }
    }

    /// All public list items (non-encrypted tags)
    public var publicItems: [Tag] {
        return tags.filter { tag in
            // Include standard list item tags but exclude metadata tags
            guard !tag.isEmpty else { return false }
            let tagType = tag[0]
            switch tagType {
            case NostrConstants.TagName.pubkey,
                 NostrConstants.TagName.event,
                 NostrConstants.TagName.address,
                 NostrConstants.TagName.reference,
                 NostrConstants.TagName.hashtag:
                return true
            case NostrConstants.TagName.title,
                 NostrConstants.TagName.name,
                 NostrConstants.TagName.description,
                 NostrConstants.TagName.image:
                return false
            default:
                // Include other non-metadata tags
                return !tagType.hasPrefix("_")
            }
        }
    }

    /// Encrypted list items (stored in content as JSON)
    private var encryptedItems: [Tag] {
        get {
            guard !content.isEmpty else { return [] }

            // Try to parse content as JSON array of tags
            do {
                let tagArrays = try JSONCoding.parseArray(from: content) as? [[String]]
                return tagArrays ?? []
            } catch {
                return []
            }
        }
        set {
            // Tags are already in the correct format
            let tagArrays = newValue

            do {
                content = try JSONCoding.serializeToString(tagArrays)
            } catch {
                content = ""
            }
        }
    }

    /// All items in this list (both public and encrypted)
    public var allItems: [Tag] {
        return publicItems + encryptedItems
    }

    /// Create an NDKList from an existing NDKEvent
    public static func from(_ event: NDKEvent, ndk: NDK? = nil) -> NDKList {
        let list = NDKList(ndk: ndk)
        list.id = event.id
        list.pubkey = event.pubkey
        list.createdAt = event.createdAt
        list.kind = event.kind
        list.tags = event.tags
        list.content = event.content
        list.signature = event.sig
        return list
    }

    /// Convert this list to an NDKEvent
    public func toNDKEvent() -> NDKEvent {
        let event = NDKEvent(
            id: id ?? "",
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: signature ?? ""
        )
        return event
    }

    /// Check if this list contains a specific item by reference
    public func contains(_ reference: String) -> Bool {
        return allItems.contains { tag in
            guard tag.count > 1 else { return false }
            let tagType = tag[0]
            let tagValue = tag[1]

            switch tagType {
            case NostrConstants.TagName.pubkey, NostrConstants.TagName.event:
                return tagValue == reference
            case NostrConstants.TagName.address:
                return tagValue == reference
            case NostrConstants.TagName.reference:
                return tagValue == reference
            case NostrConstants.TagName.hashtag:
                return tagValue == reference
            default: return false
            }
        }
    }

    /// Add an item to this list
    @discardableResult
    public func addItem(_ item: NDKListItem, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws -> NDKList {
        // Check if item already exists
        guard !contains(await item.reference) else {
            return self
        }

        var listTag = await item.toListTag()

        // Add mark as additional info if provided
        if let mark = mark, !mark.isEmpty {
            listTag.append(mark)
        }

        if encrypted {
            // Add to encrypted items
            var currentEncrypted = encryptedItems
            if position == .top {
                currentEncrypted.insert(listTag, at: 0)
            } else {
                currentEncrypted.append(listTag)
            }
            encryptedItems = currentEncrypted

            // Encrypt the content if we have a signer
            if let signer = ndk?.signer {
                try await encrypt(signer)
            }
        } else {
            // Add to public tags
            if position == .top {
                // Insert after metadata tags
                let metadataCount = tags.prefix { tag in
                    guard !tag.isEmpty else { return false }
                    return [NostrConstants.TagName.title, NostrConstants.TagName.name, NostrConstants.TagName.description, NostrConstants.TagName.image].contains(tag[0])
                }.count
                tags.insert(listTag, at: metadataCount)
            } else {
                tags.append(listTag)
            }
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Remove an item from this list by index
    @discardableResult
    public func removeItem(at index: Int, encrypted: Bool) async throws -> NDKList {
        if encrypted {
            var currentEncrypted = encryptedItems
            guard index < currentEncrypted.count else { return self }
            currentEncrypted.remove(at: index)
            encryptedItems = currentEncrypted

            // Re-encrypt the content if we have a signer
            if let signer = ndk?.signer {
                try await encrypt(signer)
            }
        } else {
            let publicItemTags = publicItems
            guard index < publicItemTags.count else { return self }

            let tagToRemove = publicItemTags[index]
            // Remove by comparing tag content since we can't use object identity
            tags.removeAll { $0 == tagToRemove }
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Remove an item from this list by reference value
    @discardableResult
    public func removeItem(byReference reference: String) async throws -> NDKList {
        // Remove from public tags
        tags.removeAll { tag in
            guard tag.count > 1 else { return false }
            let tagType = tag[0]
            let tagValue = tag[1]

            switch tagType {
            case NostrConstants.TagName.pubkey,
                 NostrConstants.TagName.event,
                 NostrConstants.TagName.address,
                 NostrConstants.TagName.reference,
                 NostrConstants.TagName.hashtag:
                return tagValue == reference
            default: return false
            }
        }

        // Remove from encrypted tags
        let currentEncrypted = encryptedItems
        let filteredEncrypted = currentEncrypted.filter { tag in
            guard tag.count > 1 else { return true }
            let tagType = tag[0]
            let tagValue = tag[1]

            switch tagType {
            case NostrConstants.TagName.pubkey,
                 NostrConstants.TagName.event,
                 NostrConstants.TagName.address,
                 NostrConstants.TagName.reference,
                 NostrConstants.TagName.hashtag:
                return tagValue != reference
            default: return true
            }
        }

        if filteredEncrypted.count != currentEncrypted.count {
            encryptedItems = filteredEncrypted

            // Re-encrypt the content if we have a signer
            if let signer = ndk?.signer {
                try await encrypt(signer)
            }
        }

        // Update timestamp
        createdAt = Timestamp.now

        return self
    }

    /// Create filters to fetch the contents of this list
    public func filtersForItems() -> [NDKFilter] {
        var filters: [NDKFilter] = []
        let items = allItems

        // Filter for events referenced by 'e' tags
        let eventIds = items.eventIds
        if !eventIds.isEmpty {
            filters.append(NDKFilter(ids: eventIds))
        }

        // Filter for parameterized replaceable events referenced by 'a' tags
        filters.append(contentsOf: createFiltersForATags(items))

        // Filter for profiles referenced by 'p' tags
        let pubkeys = items.pubkeys
        if !pubkeys.isEmpty {
            filters.append(NDKFilter(authors: pubkeys, kinds: [0]))
        }

        return filters
    }

    /// Parse an 'a' tag value into its components
    private func parseATag(_ value: String) -> (kind: Int, pubkey: String, dTag: String?)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let kind = Int(parts[0]) else { return nil }

        let pubkey = String(parts[1])
        guard !pubkey.isEmpty else { return nil }

        let dTag = parts.count > 2 ? String(parts[2]).nilIfEmpty : nil
        return (kind: kind, pubkey: pubkey, dTag: dTag)
    }

    /// Create filters for 'a' tags grouped by kind
    private func createFiltersForATags(_ items: [[String]]) -> [NDKFilter] {
        let aTags = items.extractTags(named: NostrConstants.TagName.address)
        let parsedATags = aTags.compactMap { tag -> (kind: Int, pubkey: String, dTag: String?)? in
            guard let value = tag[safe: 1] else { return nil }
            return parseATag(value)
        }

        let aTagGroups = Dictionary(grouping: parsedATags) { $0.kind }

        return aTagGroups.map { kind, items in
            let authors = items.map { $0.pubkey }
            let filter = NDKFilter(authors: authors, kinds: [kind])

            // Add d-tag filter if we have specific d-tags
            let dTags = items.compactMap { $0.dTag }
            if !dTags.isEmpty, dTags.count == items.count {
                // Note: This would need proper tag filter implementation
                // filter.addTagFilter("d", values: Set(dTags))
            }

            return filter
        }
    }

    /// Encrypt the content using the provided signer
    private func encrypt(_: NDKSigner) async throws {
        guard !encryptedItems.isEmpty else {
            content = ""
            return
        }

        // Create JSON representation of encrypted items
        let jsonString = try JSONCoding.serializeToString(encryptedItems)

        // For now, store as plain JSON - encryption would require NIP-04/44 implementation
        content = jsonString
    }

    /// Decrypt the content using the provided signer
    private func decrypt(_: NDKSigner) async throws {
        guard !content.isEmpty else { return }

        // For now, assume content is plain JSON - decryption would require NIP-04/44 implementation
        // This is a placeholder for future encryption support
    }

    /// Sign this list as an event
    public func sign() async throws {
        guard let ndk = ndk else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.ndkReferenceLost)
        }
        let signer = try ndk.requireSigner()

        let event = toNDKEvent()

        // Use NDKEventBuilder for signing
        let signedEvent = try await NDKEventBuilder(ndk: ndk)
            .pubkey(await signer.pubkey)
            .createdAt(event.createdAt)
            .kind(event.kind)
            .tags(event.tags)
            .content(event.content)
            .build(signer: signer)

        // Update our properties with signed values
        id = signedEvent.id
        signature = signedEvent.sig
        pubkey = signedEvent.pubkey
    }

    /// Publish this list
    public func publish() async throws {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK instance not available")
        }

        try await sign()
        let event = toNDKEvent()
        _ = try await ndk.publish(event)
    }
}

// MARK: - NDKListItem Implementations

extension NDKUser: NDKListItem {
    public func toListTag() async -> Tag {
        return [NostrConstants.TagName.pubkey, pubkey]
    }

    public var reference: String {
        get async {
            pubkey
        }
    }
}

extension NDKEvent: NDKListItem {
    public func toListTag() async -> Tag {
        if isParameterizedReplaceable {
            // Use 'a' tag for parameterized replaceable events
            let dTagElement = tags.first { !$0.isEmpty && $0[0] == NostrConstants.TagName.identifier }
            let dTag = (dTagElement?.count ?? 0) > 1 ? dTagElement![1] : ""
            let aTagValue = "\(kind):\(pubkey):\(dTag)"
            return [NostrConstants.TagName.address, aTagValue]
        } else {
            // Use 'e' tag for regular events
            return [NostrConstants.TagName.event, id]
        }
    }

    public var reference: String {
        get async {
            if isParameterizedReplaceable {
                let dTagElement = tags.first { !$0.isEmpty && $0[0] == NostrConstants.TagName.identifier }
                let dTag = (dTagElement?.count ?? 0) > 1 ? dTagElement![1] : ""
                return "\(kind):\(pubkey):\(dTag)"
            } else {
                return id
            }
        }
    }
}

extension NDKRelay: NDKListItem {
    public func toListTag() async -> Tag {
        return [NostrConstants.TagName.reference, url]
    }

    public var reference: String {
        get async {
            url
        }
    }
}

/// Simple string-based list item for hashtags and other text content
public struct NDKStringListItem: NDKListItem {
    public let tagType: String
    public let value: String

    public init(tagType: String, value: String) {
        self.tagType = tagType
        self.value = value
    }

    public func toListTag() async -> Tag {
        return [tagType, value]
    }

    public var reference: String {
        get async {
            value
        }
    }
}

// MARK: - Convenience Extensions

public extension NDKList {
    /// Add a hashtag to this list
    func addHashtag(_ hashtag: String, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws {
        let item = NDKStringListItem(tagType: NostrConstants.TagName.hashtag, value: hashtag.hasPrefix("#") ? String(hashtag.dropFirst()) : hashtag)
        try await addItem(item, mark: mark, encrypted: encrypted, position: position)
    }

    /// Add a URL to this list
    func addURL(_ url: String, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws {
        let item = NDKStringListItem(tagType: NostrConstants.TagName.reference, value: url)
        try await addItem(item, mark: mark, encrypted: encrypted, position: position)
    }

    /// Get all hashtags in this list
    var hashtags: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1, tag[0] == NostrConstants.TagName.hashtag else { return nil }
            return tag[1]
        }
    }

    /// Get all URLs in this list
    var urls: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1, tag[0] == NostrConstants.TagName.reference else { return nil }
            return tag[1]
        }
    }

    /// Get all user pubkeys in this list
    var userPubkeys: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1, tag[0] == NostrConstants.TagName.pubkey else { return nil }
            return tag[1]
        }
    }

    /// Get all event IDs in this list
    var eventIds: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1, tag[0] == NostrConstants.TagName.event else { return nil }
            return tag[1]
        }
    }
}

// MARK: - Blacklist/Blocklist Helpers

public extension NDKList {
    /// Check if this is a mute list (kind 10000)
    var isMuteList: Bool {
        return kind == EventKind.muteList
    }

    /// Check if this is a blocked relays list (kind 10006)
    var isBlockedRelaysList: Bool {
        return kind == EventKind.blockedRelays
    }

    /// Check if a specific mint URL is blacklisted (for mute lists containing mint URLs)
    func isMintBlacklisted(_ mintUrl: String) -> Bool {
        guard isMuteList else { return false }
        return urls.contains(mintUrl)
    }

    /// Check if a specific relay URL is blocked
    func isRelayBlocked(_ relayUrl: String) -> Bool {
        guard isBlockedRelaysList else { return false }
        // Normalize the relay URL before checking
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relayUrl) ?? relayUrl
        return urls.contains { url in
            let normalizedListUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
            return normalizedListUrl == normalizedUrl
        }
    }

    /// Get all blacklisted mint URLs from a mute list
    var blacklistedMints: [String] {
        guard isMuteList else { return [] }
        return urls.filter { url in
            // Check if URL looks like a mint URL (contains cashu or fedimint patterns)
            url.contains("cashu") || url.contains("fedimint") || url.contains("mint")
        }
    }

    /// Get all blocked relay URLs
    var blockedRelays: [String] {
        guard isBlockedRelaysList else { return [] }
        return urls
    }
}
