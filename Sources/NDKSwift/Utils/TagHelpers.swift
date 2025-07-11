import Foundation

// MARK: - Safe Array Access

extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices
    func at(_ index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
    
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Tag Validation

extension Tag {
    /// Validates common tag formats according to Nostr protocol
    var isValid: Bool {
        guard !isEmpty else { return false }
        let tagType = self[0]
        
        switch tagType {
        case "e", "p":
            // Event and pubkey tags must have 64-character hex IDs
            return count >= 2 && self[1].count == 64 && self[1].allSatisfy { $0.isHexDigit }
        case "a":
            // Addressable event references: kind:pubkey:d-tag
            guard count >= 2 else { return false }
            let parts = self[1].split(separator: ":")
            return parts.count >= 3 && Int(parts[0]) != nil && parts[1].count == 64
        case "d", "t", "r":
            // Identifier, hashtag, and URL tags just need a value
            return count >= 2
        default:
            // Unknown tags are considered valid
            return true
        }
    }
    
    /// Returns the tag name (first element)
    var name: String? {
        return self.first
    }
    
    /// Returns the primary value (second element)
    var value: String? {
        return count > 1 ? self[1] : nil
    }
    
    /// Returns the relay hint (third element) if present
    var relayHint: String? {
        return count > 2 ? self[2] : nil
    }
    
    /// Returns the marker (fourth element) if present
    var marker: String? {
        return count > 3 ? self[3] : nil
    }
}

// Note: isHexDigit is already defined in NDKEvent.swift

// MARK: - Tag Creation Helpers
// NOTE: These methods are deprecated. Use NDKEventBuilder for creating events with tags.

/*
extension NDKEvent {
    /// Tags this event as a reply to another event
    public func tagReply(to event: NDKEvent, relay: String? = nil) async {
        await tag(event: event, marker: "reply", relay: relay)
    }
    
    /// Tags this event with a root event reference
    public func tagRoot(_ event: NDKEvent, relay: String? = nil) async {
        await tag(event: event, marker: "root", relay: relay)
    }
    
    /// Tags this event with a mention of another event
    public func tagMention(_ event: NDKEvent, relay: String? = nil) async {
        await tag(event: event, marker: "mention", relay: relay)
    }
    
    /// Adds a hashtag to this event
    public func tagHashtag(_ hashtag: String) async {
        let cleanHashtag = hashtag.hasPrefix("#") ? String(hashtag.dropFirst()) : hashtag
        await addTag(["t", cleanHashtag.lowercased()])
    }
    
    /// Adds multiple hashtags to this event
    public func tagHashtags(_ hashtags: [String]) async {
        for hashtag in hashtags {
            await tagHashtag(hashtag)
        }
    }
    
    /// Adds a URL reference to this event
    public func tagURL(_ url: String, petname: String? = nil) async {
        var tag = ["r", url]
        if let petname = petname {
            tag.append(petname)
        }
        await addTag(tag)
    }
    
    /// Tags an addressable event (NIP-33)
    public func tagAddressableEvent(_ event: NDKEvent, relay: String? = nil) async {
        let isReplaceable = event.isParameterizedReplaceable
        guard isReplaceable else { return }
        let dTag = event.tagValue("d") ?? ""
        let eventKind = event.kind
        let eventPubkey = event.pubkey
        var tag = ["a", "\(eventKind):\(eventPubkey):\(dTag)"]
        if let relay = relay {
            tag.append(relay)
        }
        await addTag(tag)
    }
    
    /// Adds a subject tag (for long-form content)
    public func tagSubject(_ subject: String) async {
        await addTag(["subject", subject])
    }
    
    /// Adds a title tag (for articles/long-form content)
    public func tagTitle(_ title: String) async {
        await addTag(["title", title])
    }
    
    /// Adds an image tag with URL and optional dimensions
    public func tagImage(_ url: String, width: Int? = nil, height: Int? = nil) async {
        var tag = ["image", url]
        if let width = width, let height = height {
            tag.append("\(width)x\(height)")
        }
        await addTag(tag)
    }
}

// MARK: - Tag Query Improvements

extension NDKEvent {
    /// Gets all values at a specific position for tags with the given name
    public func tagValues(_ name: String, at position: Int = 1) async -> [String] {
        let matchingTags = await tags(withName: name)
        return matchingTags.compactMap { $0.at(position) }
    }
    
    /// Gets all tags with a specific name and marker
    public func tags(withName name: String, marker: String) async -> [Tag] {
        let matchingTags = await tags(withName: name)
        return matchingTags.filter { tag in
            tag.count > 3 && tag[3] == marker
        }
    }
    
    /// Gets the first tag with a specific name and marker
    public func tag(withName name: String, marker: String) async -> Tag? {
        let matchingTags = await tags(withName: name, marker: marker)
        return matchingTags.first
    }
    
    /// Returns the root event ID if this is part of a thread
    public var rootEventId: EventID? {
        get async {
            // First check for explicit root marker
            if let rootTag = await tag(withName: "e", marker: "root") {
                return rootTag.at(1)
            }
            // Fall back to first e tag (deprecated but still used)
            let eTags = await tags(withName: "e")
            return eTags.first?.at(1)
        }
    }
    
    /// Returns the event ID this is replying to
    public var replyToEventId: EventID? {
        get async {
            // Check for explicit reply marker
            if let replyTag = await tag(withName: "e", marker: "reply") {
                return replyTag.at(1)
            }
            // Fall back to last e tag without root marker
            let eTags = await tags(withName: "e")
            if eTags.count > 1 {
                // Skip root tag if present
                return eTags.last { $0.at(3) != "root" }?.at(1)
            }
            return nil
        }
    }
    
    /// Returns all mentioned event IDs
    public var mentionedEventIds: [EventID] {
        get async {
            let mentionTags = await tags(withName: "e", marker: "mention")
            return mentionTags.compactMap { $0.at(1) }
        }
    }
    
    /// Returns all mentioned pubkeys
    public var mentionedPubkeys: [PublicKey] {
        get async {
            let pTags = await tags(withName: "p")
            return pTags.compactMap { $0.at(1) }
        }
    }
    
    /// Returns all hashtags in this event
    public var hashtags: [String] {
        get async {
            await tagValues("t")
        }
    }
    
    /// Returns all URLs referenced in this event
    public var urls: [(url: String, petname: String?)] {
        get async {
            let rTags = await tags(withName: "r")
            return rTags.compactMap { tag in
                guard let url = tag.at(1) else { return nil }
                return (url: url, petname: tag.at(2))
            }
        }
    }
    
    /// Returns all addressable event references
    public var addressableEventRefs: [(kind: Int, pubkey: String, identifier: String, relay: String?)] {
        get async {
            let aTags = await tags(withName: "a")
            return aTags.compactMap { tag in
                guard let value = tag[safe: 1] else { return nil }
                let parts = value.split(separator: ":")
                guard parts.count >= 3,
                      let kind = Int(parts[0]) else { return nil }
                return (
                    kind: kind,
                    pubkey: String(parts[1]),
                    identifier: String(parts[2...].joined(separator: ":")), // Handle d-tags with colons
                    relay: tag.at(2)
                )
            }
        }
    }
    
    /// Returns the subject of this event (if any)
    public var subject: String? {
        get async {
            await tagValue("subject")
        }
    }
    
    /// Returns the title of this event (if any)
    public var title: String? {
        get async {
            await tagValue("title")
        }
    }
    
    /// Checks if this event is a reply based on e tags
    public var isReplyEvent: Bool {
        get async {
            let eTags = await tags(withName: "e")
            return !eTags.isEmpty
        }
    }
    
    /// Checks if this event is a root post (not a reply)
    public var isRootPost: Bool {
        get async {
            let eTags = await tags(withName: "e")
            return eTags.isEmpty
        }
    }
    
    /// Gets all image URLs from image tags
    public var imageURLs: [(url: String, dimensions: String?)] {
        get async {
            let imageTags = await tags(withName: "image")
            return imageTags.compactMap { tag in
                guard let url = tag.at(1) else { return nil }
                return (url: url, dimensions: tag[safe: 2])
            }
        }
    }
}

// MARK: - Thread Building Helpers

extension NDKEvent {
    /// Creates a reply to this event
    public func createReply(content: String, additionalTags: [Tag] = []) async -> NDKEvent {
        let eventKind = await self.kind
        let eventPubkey = await self.pubkey
        let eventNdk = await self.ndk
        
        let reply = NDKEvent(
            pubkey: "", // Will be set by signer
            kind: eventKind,
            tags: [],
            content: content
        )
        await reply.setNDK(eventNdk ?? NDK())
        
        // Add reply tag
        await reply.tagReply(to: self)
        
        // Determine root event
        if let existingRoot = await self.rootEventId {
            // This event is already part of a thread, use its root
            await reply.addTag(["e", existingRoot, "", "root"])
        } else {
            // This event is the root
            await reply.tagRoot(self)
        }
        
        // Tag the author
        await reply.tag(user: NDKUser(pubkey: eventPubkey))
        
        // Add any additional p tags from parent (for mentions)
        let pTags = await self.tags(withName: "p")
        for pTag in pTags {
            if let pubkey = pTag[safe: 1], pubkey != eventPubkey {
                await reply.addTag(pTag)
            }
        }
        
        // Add any additional tags
        await reply.addTags(additionalTags)
        
        return reply
    }
    
    /// Creates a mention of this event
    public func createMention(in event: NDKEvent) async {
        await event.tagMention(self)
    }
}

// MARK: - Batch Tag Operations

extension NDKEvent {
    /// Adds multiple tags at once
    public func addTags(_ newTags: [Tag]) async {
        for tag in newTags {
            await addTag(tag)
        }
    }
    
    /// Returns a copy of tags without duplicates (keeping the first occurrence)
    public func deduplicatedTags() async -> [Tag] {
        var seen = Set<String>()
        var uniqueTags: [Tag] = []
        
        let currentTags = await tags
        for tag in currentTags {
            let tagKey = tag.joined(separator: ":")
            if !seen.contains(tagKey) {
                seen.insert(tagKey)
                uniqueTags.append(tag)
            }
        }
        
        return uniqueTags
    }
    
    /// Returns only valid tags
    public func validTags() async -> [Tag] {
        let currentTags = await tags
        return currentTags.filter { $0.isValid }
    }
}
*/

// MARK: - Tag Builder

/// A builder for constructing complex tag sets
public struct TagBuilder {
    private var tags: [Tag] = []
    
    public init() {}
    
    /// Adds an event reference
    @discardableResult
    public mutating func event(_ id: EventID, relay: String? = nil, marker: String? = nil) -> Self {
        var tag = ["e", id]
        if let relay = relay {
            tag.append(relay)
        } else if marker != nil {
            tag.append("") // Empty relay hint
        }
        if let marker = marker {
            tag.append(marker)
        }
        tags.append(tag)
        return self
    }
    
    /// Adds a pubkey reference
    @discardableResult
    public mutating func pubkey(_ pubkey: PublicKey, relay: String? = nil, petname: String? = nil) -> Self {
        var tag = ["p", pubkey]
        if let relay = relay {
            tag.append(relay)
        }
        if let petname = petname {
            if relay == nil {
                tag.append("") // Empty relay hint
            }
            tag.append(petname)
        }
        tags.append(tag)
        return self
    }
    
    /// Adds a hashtag
    @discardableResult
    public mutating func hashtag(_ text: String) -> Self {
        let clean = text.hasPrefix("#") ? String(text.dropFirst()) : text
        tags.append(["t", clean.lowercased()])
        return self
    }
    
    /// Adds a URL reference
    @discardableResult
    public mutating func url(_ url: String, petname: String? = nil) -> Self {
        var tag = ["r", url]
        if let petname = petname {
            tag.append(petname)
        }
        tags.append(tag)
        return self
    }
    
    /// Adds a custom tag
    @discardableResult
    public mutating func custom(_ tag: Tag) -> Self {
        tags.append(tag)
        return self
    }
    
    /// Builds the final tag array
    public func build() -> [Tag] {
        return tags
    }
}

// MARK: - Filter Tag Helpers

extension NDKFilter {
    /// Adds a hashtag filter
    public mutating func addHashtagFilter(_ hashtags: String...) {
        addTagFilter("t", values: hashtags.map { $0.lowercased() })
    }
    
    /// Adds a URL filter
    public mutating func addURLFilter(_ urls: String...) {
        addTagFilter("r", values: urls)
    }
    
    /// Checks if this filter includes a specific tag type
    public func hasTagFilter(_ tagName: String) -> Bool {
        return tagFilter(tagName) != nil
    }
}
