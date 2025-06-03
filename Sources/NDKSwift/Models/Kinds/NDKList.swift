import Foundation

/// Protocol for objects that can be stored in an NDKList
public protocol NDKListItem {
    /// Convert this item to a Tag for storage in a list
    func toListTag() -> Tag
    
    /// The reference value used to identify this item in a list
    var reference: String { get }
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
        3,      // Contact list
        10000,  // Mute list
        10001,  // Pin list
        10002,  // Relay list
        10003,  // Bookmark list
        10004,  // Communities list
        10005,  // Public chats list
        10006,  // Blocked relays list
        10007,  // Search relays list
        10015,  // Interest list
        10030,  // User emoji list
        30000,  // Categorized people list
        30001,  // Categorized bookmark list
        30002,  // Relay list metadata
        30063   // Blossom server list
    ]
    
    /// Initialize a new list
    public init(ndk: NDK? = nil) {
        self.ndk = ndk
        self.createdAt = Timestamp(Date().timeIntervalSince1970)
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
            if let titleTag = tags.first(where: { $0.count > 0 && ($0[0] == "title" || $0[0] == "name") }) {
                return titleTag.count > 1 ? titleTag[1] : nil
            }
            
            // Fall back to kind-specific defaults
            return defaultTitleForKind
        }
        set {
            // Remove existing title/name tags
            tags.removeAll { $0.count > 0 && ($0[0] == "title" || $0[0] == "name") }
            
            // Add new title if provided
            if let title = newValue, !title.isEmpty {
                tags.append(["title", title])
            }
        }
    }
    
    /// Default title based on the list kind
    private var defaultTitleForKind: String? {
        switch kind {
        case 3: return "Contacts"
        case 10000: return "Muted"
        case 10001: return "Pinned"
        case 10002: return "Relays"
        case 10003: return "Bookmarks"
        case 10004: return "Communities"
        case 10005: return "Public Chats"
        case 10006: return "Blocked Relays"
        case 10007: return "Search Relays"
        case 10015: return "Interests"
        case 10030: return "Emojis"
        case 30000: return "People"
        case 30001: return "Bookmarks"
        case 30002: return "Relay Metadata"
        case 30063: return "Blossom Servers"
        default: return nil
        }
    }
    
    /// Description of this list
    public var listDescription: String? {
        get {
            let descTag = tags.first { $0.count > 0 && $0[0] == "description" }
            return (descTag?.count ?? 0) > 1 ? descTag?[1] : nil
        }
        set {
            tags.removeAll { $0.count > 0 && $0[0] == "description" }
            if let description = newValue, !description.isEmpty {
                tags.append(["description", description])
            }
        }
    }
    
    /// Image URL for this list
    public var image: String? {
        get {
            let imageTag = tags.first { $0.count > 0 && $0[0] == "image" }
            return (imageTag?.count ?? 0) > 1 ? imageTag?[1] : nil
        }
        set {
            tags.removeAll { $0.count > 0 && $0[0] == "image" }
            if let image = newValue, !image.isEmpty {
                tags.append(["image", image])
            }
        }
    }
    
    /// All public list items (non-encrypted tags)
    public var publicItems: [Tag] {
        return tags.filter { tag in
            // Include standard list item tags but exclude metadata tags
            guard tag.count > 0 else { return false }
            let tagType = tag[0]
            switch tagType {
            case "p", "e", "a", "r", "t":
                return true
            case "title", "name", "description", "image":
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
                let data = content.data(using: .utf8) ?? Data()
                let tagArrays = try JSONSerialization.jsonObject(with: data) as? [[String]]
                return tagArrays ?? []
            } catch {
                return []
            }
        }
        set {
            // Tags are already in the correct format
            let tagArrays = newValue
            
            do {
                let data = try JSONSerialization.data(withJSONObject: tagArrays)
                content = String(data: data, encoding: .utf8) ?? ""
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
    public static func from(_ event: NDKEvent) -> NDKList {
        let list = NDKList(ndk: event.ndk)
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
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        event.id = id
        event.sig = signature
        event.ndk = ndk
        return event
    }
    
    /// Check if this list contains a specific item by reference
    public func contains(_ reference: String) -> Bool {
        return allItems.contains { tag in
            guard tag.count > 1 else { return false }
            let tagType = tag[0]
            let tagValue = tag[1]
            
            switch tagType {
            case "p", "e": return tagValue == reference
            case "a": return tagValue == reference
            case "r": return tagValue == reference
            case "t": return tagValue == reference
            default: return false
            }
        }
    }
    
    /// Add an item to this list
    @discardableResult
    public func addItem(_ item: NDKListItem, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws -> NDKList {
        // Check if item already exists
        guard !contains(item.reference) else {
            return self
        }
        
        var listTag = item.toListTag()
        
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
                    guard tag.count > 0 else { return false }
                    return ["title", "name", "description", "image"].contains(tag[0])
                }.count
                tags.insert(listTag, at: metadataCount)
            } else {
                tags.append(listTag)
            }
        }
        
        // Update timestamp
        createdAt = Timestamp(Date().timeIntervalSince1970)
        
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
        createdAt = Timestamp(Date().timeIntervalSince1970)
        
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
            case "p", "e", "a", "r", "t": return tagValue == reference
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
            case "p", "e", "a", "r", "t": return tagValue != reference
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
        createdAt = Timestamp(Date().timeIntervalSince1970)
        
        return self
    }
    
    /// Create filters to fetch the contents of this list
    public func filtersForItems() -> [NDKFilter] {
        var filters: [NDKFilter] = []
        let items = allItems
        
        // Filter for events referenced by 'e' tags
        let eventIds = items.compactMap { tag -> String? in
            guard tag.count > 1 && tag[0] == "e" else { return nil }
            return tag[1]
        }
        if !eventIds.isEmpty {
            filters.append(NDKFilter(ids: eventIds))
        }
        
        // Filter for parameterized replaceable events referenced by 'a' tags
        let aTagGroups = Dictionary(grouping: items.compactMap { tag -> (kind: Int, pubkey: String, dTag: String?)? in
            guard tag.count > 1 && tag[0] == "a" else { return nil }
            let parts = tag[1].split(separator: ":")
            guard parts.count >= 2,
                  let kind = Int(parts[0]),
                  let pubkey = String(parts[1]).isEmpty ? nil : String(parts[1]) else { return nil }
            
            let dTag = parts.count > 2 ? String(parts[2]) : nil
            return (kind: kind, pubkey: pubkey, dTag: dTag)
        }) { $0.kind }
        
        for (kind, items) in aTagGroups {
            let authors = items.map { $0.pubkey }
            let filter = NDKFilter(authors: authors, kinds: [kind])
            
            // Add d-tag filter if we have specific d-tags
            let dTags = items.compactMap { $0.dTag }
            if !dTags.isEmpty && dTags.count == items.count {
                // Note: This would need proper tag filter implementation
                // filter.addTagFilter("d", values: Set(dTags))
            }
            
            filters.append(filter)
        }
        
        // Filter for profiles referenced by 'p' tags
        let pubkeys = items.compactMap { tag -> String? in
            guard tag.count > 1 && tag[0] == "p" else { return nil }
            return tag[1]
        }
        if !pubkeys.isEmpty {
            filters.append(NDKFilter(authors: pubkeys, kinds: [0]))
        }
        
        return filters
    }
    
    /// Encrypt the content using the provided signer
    private func encrypt(_ signer: NDKSigner) async throws {
        guard !encryptedItems.isEmpty else {
            content = ""
            return
        }
        
        // Create JSON representation of encrypted items
        let jsonData = try JSONSerialization.data(withJSONObject: encryptedItems)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        
        // For now, store as plain JSON - encryption would require NIP-04/44 implementation
        content = jsonString
    }
    
    /// Decrypt the content using the provided signer
    private func decrypt(_ signer: NDKSigner) async throws {
        guard !content.isEmpty else { return }
        
        // For now, assume content is plain JSON - decryption would require NIP-04/44 implementation
        // This is a placeholder for future encryption support
    }
    
    /// Sign this list as an event
    public func sign() async throws {
        guard let signer = ndk?.signer else {
            throw NDKError.signingFailed
        }
        
        let event = toNDKEvent()
        
        // Generate ID if not present
        if event.id == nil {
            _ = try event.generateID()
        }
        
        // Sign the event
        let signature = try await signer.sign(event)
        
        // Update our properties with signed values
        self.id = event.id
        self.signature = signature
        self.pubkey = try await signer.pubkey
    }
    
    /// Publish this list
    public func publish() async throws {
        guard let ndk = ndk else {
            throw NDKError.custom("NDK instance not available")
        }
        
        try await sign()
        let event = toNDKEvent()
        try await ndk.publish(event)
    }
}

// MARK: - NDKListItem Implementations

extension NDKUser: NDKListItem {
    public func toListTag() -> Tag {
        return ["p", pubkey]
    }
    
    public var reference: String {
        return pubkey
    }
}

extension NDKEvent: NDKListItem {
    public func toListTag() -> Tag {
        if isParameterizedReplaceable {
            // Use 'a' tag for parameterized replaceable events
            let dTagElement = tags.first { $0.count > 0 && $0[0] == "d" }
            let dTag = (dTagElement?.count ?? 0) > 1 ? dTagElement![1] : ""
            let aTagValue = "\(kind):\(pubkey):\(dTag)"
            return ["a", aTagValue]
        } else {
            // Use 'e' tag for regular events
            return ["e", id ?? ""]
        }
    }
    
    public var reference: String {
        if isParameterizedReplaceable {
            let dTagElement = tags.first { $0.count > 0 && $0[0] == "d" }
            let dTag = (dTagElement?.count ?? 0) > 1 ? dTagElement![1] : ""
            return "\(kind):\(pubkey):\(dTag)"
        } else {
            return id ?? ""
        }
    }
}

extension NDKRelay: NDKListItem {
    public func toListTag() -> Tag {
        return ["r", url]
    }
    
    public var reference: String {
        return url
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
    
    public func toListTag() -> Tag {
        return [tagType, value]
    }
    
    public var reference: String {
        return value
    }
}

// MARK: - Convenience Extensions

extension NDKList {
    /// Add a hashtag to this list
    public func addHashtag(_ hashtag: String, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws {
        let item = NDKStringListItem(tagType: "t", value: hashtag.hasPrefix("#") ? String(hashtag.dropFirst()) : hashtag)
        try await addItem(item, mark: mark, encrypted: encrypted, position: position)
    }
    
    /// Add a URL to this list
    public func addURL(_ url: String, mark: String? = nil, encrypted: Bool = false, position: ListPosition = .bottom) async throws {
        let item = NDKStringListItem(tagType: "r", value: url)
        try await addItem(item, mark: mark, encrypted: encrypted, position: position)
    }
    
    /// Get all hashtags in this list
    public var hashtags: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1 && tag[0] == "t" else { return nil }
            return tag[1]
        }
    }
    
    /// Get all URLs in this list
    public var urls: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1 && tag[0] == "r" else { return nil }
            return tag[1]
        }
    }
    
    /// Get all user pubkeys in this list
    public var userPubkeys: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1 && tag[0] == "p" else { return nil }
            return tag[1]
        }
    }
    
    /// Get all event IDs in this list
    public var eventIds: [String] {
        return allItems.compactMap { tag in
            guard tag.count > 1 && tag[0] == "e" else { return nil }
            return tag[1]
        }
    }
}