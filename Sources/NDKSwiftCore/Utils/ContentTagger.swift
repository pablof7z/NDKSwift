import Foundation

/// Utilities for working with Nostr event tags
///
/// This file provides extensions and helpers for validating and extracting
/// information from Nostr event tags according to various NIPs.

// MARK: - Tag Validation

extension Tag {
    /// Validates common tag formats according to Nostr protocol
    ///
    /// Validates tags according to their type:
    /// - `e` (event): Must have 64-character hex event ID
    /// - `p` (pubkey): Must have 64-character hex public key
    /// - `a` (addressable): Must follow kind:pubkey:d-tag format
    /// - `d` (identifier), `t` (hashtag), `r` (URL): Must have a value
    /// - Other tags: Always considered valid
    ///
    /// - Returns: true if the tag is valid according to its type
    var isValid: Bool {
        guard !isEmpty else { return false }
        let tagType = self[0]

        switch tagType {
        case "e", "p":
            // Event and pubkey tags must have 64-character hex IDs
            return count >= 2 && HexValidator.isValid32ByteHex(self[1])
        case "a":
            // Addressable event references: kind:pubkey:d-tag
            guard count >= 2 else { return false }
            let parts = self[1].split(separator: ":")
            return parts.count >= 3 && Int(parts[0]) != nil && HexValidator.isValid32ByteHex(String(parts[1]))
        case "d", "t", "r":
            // Identifier, hashtag, and URL tags just need a value
            return count >= 2
        default:
            // Unknown tags are considered valid
            return true
        }
    }

    /// Returns the tag name (first element)
    /// Example: For tag ["p", "pubkey"], returns "p"
    var name: String? {
        return first
    }

    /// Returns the primary value (second element)
    /// Example: For tag ["p", "pubkey"], returns "pubkey"
    var value: String? {
        return count > 1 ? self[1] : nil
    }

    /// Returns the relay hint (third element) if present
    /// Example: For tag ["e", "eventid", "wss://relay.com"], returns "wss://relay.com"
    var relayHint: String? {
        return count > 2 ? self[2] : nil
    }

    /// Returns the marker (fourth element) if present
    /// Example: For tag ["e", "eventid", "wss://relay.com", "reply"], returns "reply"
    var marker: String? {
        return count > 3 ? self[3] : nil
    }
}

/// Result of content tagging operations
/// Contains the extracted tags and the processed content after tag extraction
public struct ContentTag {
    /// Array of Nostr tags extracted from the content
    public let tags: [Tag]
    /// The processed content string (may be modified from original)
    public let content: String

    /// Initialize a new ContentTag result
    /// - Parameters:
    ///   - tags: Array of extracted Nostr tags
    ///   - content: The processed content string
    public init(tags: [Tag], content: String) {
        self.tags = tags
        self.content = content
    }
}

/// Represents a decoded Nostr entity from a bech32-encoded string
/// Contains all information extracted from npub, nevent, nprofile, naddr, and other Nostr entity formats
public struct DecodedNostrEntity {
    /// The type of entity (e.g., "npub", "nevent", "nprofile", "naddr")
    public let type: String
    /// Event ID for nevent/naddr entities
    public let eventId: String?
    /// Public key for npub/nprofile entities
    public let pubkey: String?
    /// Relay hints included in the entity
    public let relays: [String]?
    /// Event kind for nevent/naddr entities
    public let kind: Int?
    /// Identifier tag value for naddr entities
    public let identifier: String?
}

/// Content tagging utilities for NDK Swift
///
/// This utility provides functionality for parsing and extracting Nostr entities from text content,
/// including npubs, notes, hashtags, and URLs. It also generates the appropriate tags for events.
public enum ContentTagger {
    /// Result of parsing content without fetching entities
    public struct ParseResult {
        /// Array of parsed segments representing different content types
        public let segments: [ParseSegment]
        /// Array of Nostr tags extracted from the content
        public let tags: [Tag]
    }

    /// A parsed segment with entity information but no fetched data
    public enum ParseSegment {
        case text(String)
        case mention(npub: String)
        case event(nevent: String)
        case hashtag(String)
        case url(URL)
    }

    /// Parse content into segments without fetching entities
    ///
    /// This method analyzes the content and extracts various Nostr entities (npubs, notes, hashtags, URLs)
    /// without making any network requests to fetch additional data.
    ///
    /// - Parameter content: The text content to parse
    /// - Returns: A ParseResult containing the parsed segments and extracted tags
    public static func parseContentSegments(from content: String) -> ParseResult {
        var segments: [ParseSegment] = []
        var tags: [Tag] = []
        var lastIndex = content.startIndex

        // Combined regex for all entity types
        let patterns = [
            // Nostr entities: @npub, @nprofile, nostr:npub, etc.
            (#"(@|nostr:)(npub|nprofile|note|nevent|naddr)[a-zA-Z0-9]+"#, "nostr"),
            // Hashtags
            (#"(?<=\s|^)(#[^\s!@#$%^&*()=+./,\[{\]};:'"?><]+)"#, "hashtag"),
            // URLs
            (#"https?://[^\s<>"{}|\\^`\[\]]+"#, "url")
        ]

        var allMatches: [(range: Range<String.Index>, type: String, value: String)] = []

        // Collect all matches
        for (pattern, type) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))

            for match in matches {
                if let range = Range(match.range, in: content) {
                    allMatches.append((range: range, type: type, value: String(content[range])))
                }
            }
        }

        // Sort matches by position
        allMatches.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Process matches and create segments
        for match in allMatches {
            // Skip if this match overlaps with previous match
            if match.range.lowerBound < lastIndex { continue }

            // Add text segment before this match
            if lastIndex < match.range.lowerBound {
                let textRange = lastIndex ..< match.range.lowerBound
                let text = String(content[textRange])
                if !text.isEmpty {
                    segments.append(.text(text))
                }
            }

            // Process the match
            switch match.type {
            case "nostr":
                // Extract the entity part
                let components = match.value.components(separatedBy: CharacterSet(charactersIn: "@:"))
                if let entity = components.last, !entity.isEmpty {
                    do {
                        let decoded = try decodeNostrEntity(entity)

                        switch decoded.type {
                        case "npub", "nprofile":
                            if let pubkey = decoded.pubkey {
                                segments.append(.mention(npub: entity))
                                tags.append(["p", pubkey])
                            }
                        case "note", "nevent":
                            segments.append(.event(nevent: entity))
                            if let eventId = decoded.eventId {
                                let relay = decoded.relays?.first ?? ""
                                tags.append(["q", eventId, relay])
                            }
                            if let pubkey = decoded.pubkey {
                                tags.append(["p", pubkey])
                            }
                        case "naddr":
                            segments.append(.event(nevent: entity))
                            if let eventId = decoded.eventId {
                                // naddr uses 'a' tags
                                let relay = decoded.relays?.first ?? ""
                                tags.append(["a", eventId, relay])
                            }
                            if let pubkey = decoded.pubkey {
                                tags.append(["p", pubkey])
                            }
                        default:
                            segments.append(.text(match.value))
                        }
                    } catch {
                        segments.append(.text(match.value))
                    }
                }

            case "hashtag":
                let tag = String(match.value.dropFirst()) // Remove #
                segments.append(.hashtag(tag))
                tags.append(["t", tag.lowercased()]) // NIP-24: hashtags must be lowercase

            case "url":
                if let url = URL(string: match.value) {
                    segments.append(.url(url))
                } else {
                    segments.append(.text(match.value))
                }

            default:
                segments.append(.text(match.value))
            }

            lastIndex = match.range.upperBound
        }

        // Add remaining text
        if lastIndex < content.endIndex {
            let text = String(content[lastIndex...])
            if !text.isEmpty {
                segments.append(.text(text))
            }
        }

        // If no matches found, entire content is text
        if segments.isEmpty {
            segments.append(.text(content))
        }

        // Remove duplicate tags
        let uniqueTags = mergeTags([], tags)

        return ParseResult(segments: segments, tags: uniqueTags)
    }

    /// Generate hashtags from content
    ///
    /// Extracts all unique hashtags from the content, maintaining case sensitivity
    /// but checking for uniqueness in a case-insensitive manner.
    ///
    /// - Parameter content: The text content to search for hashtags
    /// - Returns: Array of hashtag strings (without the # prefix)
    public static func generateHashtags(from content: String) -> [String] {
        // Regex pattern for hashtags: #word (matches until special characters)
        let hashtagRegex = #"(?<=\s|^)(#[^\s!@#$%^&*()=+./,\[{\]};:'"?><]+)"#

        guard let regex = try? NSRegularExpression(pattern: hashtagRegex, options: []) else {
            return []
        }

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
        var hashtags: [String] = []
        var seenHashtags = Set<String>()

        for match in matches {
            if let range = Range(match.range, in: content) {
                let hashtag = String(content[range])
                let tag = String(hashtag.dropFirst()) // Remove the # symbol
                let normalizedTag = tag.lowercased()

                // Only add the first occurrence of each hashtag (case-insensitive)
                if !seenHashtags.contains(normalizedTag) {
                    hashtags.append(tag)
                    seenHashtags.insert(normalizedTag)
                }
            }
        }

        return hashtags
    }

    /// Decode Nostr entity from bech32 string
    ///
    /// Decodes various Nostr entity types (npub, note, nprofile, nevent, naddr) from their
    /// bech32-encoded format and extracts all embedded information.
    ///
    /// - Parameter entity: The bech32-encoded entity string
    /// - Returns: A DecodedNostrEntity containing all extracted information
    /// - Throws: NDKError if the entity format is invalid
    public static func decodeNostrEntity(_ entity: String) throws -> DecodedNostrEntity {
        let (hrp, data) = try Bech32.decode(entity)

        switch hrp {
        case "npub":
            guard data.count == 32 else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }
            let pubkey = Data(data).hexString
            return DecodedNostrEntity(type: "npub", eventId: nil, pubkey: pubkey, relays: nil, kind: nil, identifier: nil)

        case "note":
            guard data.count == 32 else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }
            let eventId = Data(data).hexString
            return DecodedNostrEntity(type: "note", eventId: eventId, pubkey: nil, relays: nil, kind: nil, identifier: nil)

        case "nprofile":
            let decoded = try decodeTLV(data)
            guard let pubkeyData = decoded[0]?.first, pubkeyData.count == 32 else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }
            let pubkey = Data(pubkeyData).hexString
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            return DecodedNostrEntity(type: "nprofile", eventId: nil, pubkey: pubkey, relays: relays.nilIfEmpty, kind: nil, identifier: nil)

        case "nevent":
            let decoded = try decodeTLV(data)
            guard let eventIdData = decoded[0]?.first, eventIdData.count == 32 else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }
            let eventId = Data(eventIdData).hexString
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            let pubkey = decoded[2]?.first.map { Data($0).hexString }
            let kind = decoded[3]?.first.map { kindFromBytes($0) }
            return DecodedNostrEntity(type: "nevent", eventId: eventId, pubkey: pubkey, relays: relays.nilIfEmpty, kind: kind, identifier: nil)

        case "naddr":
            let decoded = try decodeTLV(data)
            guard let identifierData = decoded[0]?.first,
                  let pubkeyData = decoded[2]?.first, pubkeyData.count == 32,
                  let kindData = decoded[3]?.first
            else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }
            let identifier = String(data: Data(identifierData), encoding: .utf8) ?? ""
            let pubkey = Data(pubkeyData).hexString
            let kind = kindFromBytes(kindData)
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            let eventId = "\(kind):\(pubkey):\(identifier)"
            return DecodedNostrEntity(type: "naddr", eventId: eventId, pubkey: pubkey, relays: relays.nilIfEmpty, kind: kind, identifier: identifier)

        default:
            throw NDKError.invalidDataFormat("bech32 type", details: "Unknown type: \(hrp)")
        }
    }

    /// Generate content tags from text content
    ///
    /// Parses the content for Nostr entities and hashtags, generates appropriate tags,
    /// and normalizes entity references to use the nostr: prefix format.
    ///
    /// - Parameters:
    ///   - content: The text content to process
    ///   - existingTags: Any existing tags to preserve and merge with new tags
    /// - Returns: A ContentTag containing the generated tags and normalized content
    public static func generateContentTags(from content: String, existingTags: [Tag] = []) -> ContentTag {
        var tags = existingTags
        var modifiedContent = content

        // Regex to match Nostr entities: @npub, @nprofile, nostr:npub, nostr:nprofile, etc.
        let nostrRegex = #"(@|nostr:)(npub|nprofile|note|nevent|naddr)[a-zA-Z0-9]+"#

        guard let regex = try? NSRegularExpression(pattern: nostrRegex, options: []) else {
            // If regex fails, just add hashtags
            let hashtags = generateHashtags(from: content)
            let newTags = hashtags.map { ["t", $0] }
            return ContentTag(tags: mergeTags(tags, newTags), content: content)
        }

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            if let range = Range(match.range, in: content) {
                let fullMatch = String(content[range])

                // Extract the entity part (after @ or nostr:)
                let components = fullMatch.components(separatedBy: CharacterSet(charactersIn: "@:"))
                guard let entity = components.last, !entity.isEmpty else { continue }

                do {
                    let decoded = try decodeNostrEntity(entity)
                    var newTag: Tag?

                    switch decoded.type {
                    case "npub":
                        if let pubkey = decoded.pubkey {
                            newTag = ["p", pubkey]
                        }

                    case "nprofile":
                        if let pubkey = decoded.pubkey {
                            newTag = ["p", pubkey]
                        }

                    case "note":
                        if let eventId = decoded.eventId {
                            let relay = decoded.relays?.first ?? ""
                            newTag = ["q", eventId, relay]
                        }

                    case "nevent":
                        if let eventId = decoded.eventId {
                            let relay = decoded.relays?.first ?? ""
                            newTag = ["q", eventId, relay]

                            // Also add p tag for author if available
                            if let pubkey = decoded.pubkey {
                                addTagIfNew(["p", pubkey], to: &tags)
                            }
                        }

                    case "naddr":
                        if let eventId = decoded.eventId {
                            // naddr uses 'a' tags, not 'q' tags
                            let relay = decoded.relays?.first ?? ""
                            newTag = ["a", eventId, relay]

                            // Also add p tag for author
                            if let pubkey = decoded.pubkey {
                                addTagIfNew(["p", pubkey], to: &tags)
                            }
                        }

                    default:
                        break
                    }

                    if let tag = newTag {
                        addTagIfNew(tag, to: &tags)
                    }

                    // Replace the match with normalized nostr: format only if it wasn't already in that format
                    if fullMatch.hasPrefix("@") {
                        modifiedContent.replaceSubrange(range, with: "nostr:\(entity)")
                    }
                    // Note: Tags are still generated even for nostr: prefixed entities

                } catch {
                    // If decoding fails, leave the original text
                    continue
                }
            }
        }

        // Add hashtag tags
        let hashtags = generateHashtags(from: modifiedContent)
        let hashtagTags = hashtags.map { ["t", $0.lowercased()] } // NIP-24: hashtags must be lowercase
        tags = mergeTags(tags, hashtagTags)

        return ContentTag(tags: tags, content: modifiedContent)
    }

    /// Add tag if it doesn't already exist
    private static func addTagIfNew(_ tag: Tag, to tags: inout [Tag]) {
        // Check if a similar tag already exists
        let exists = tags.contains { existingTag in
            // For 'p' and 'q' tags, check if the second element (pubkey/eventId) matches
            if tag[0] == "p" || tag[0] == "q", existingTag[0] == "p" || existingTag[0] == "q" {
                return tag.count > 1 && existingTag.count > 1 && tag[1] == existingTag[1]
            }
            // For other tags, check exact match
            return existingTag == tag
        }

        if !exists {
            tags.append(tag)
        }
    }

    /// Merge two tag arrays, removing duplicates and preferring more detailed tags
    ///
    /// When merging tags, this method removes duplicates and prefers tags with more
    /// information (e.g., a tag with relay hints over one without).
    ///
    /// - Parameters:
    ///   - tags1: First array of tags
    ///   - tags2: Second array of tags
    /// - Returns: Merged array with duplicates removed
    public static func mergeTags(_ tags1: [Tag], _ tags2: [Tag]) -> [Tag] {
        var tagMap: [String: Tag] = [:]

        // Function to generate a key for the map
        func generateKey(_ tag: Tag) -> String {
            return tag.joined(separator: ",")
        }

        // Function to check if one tag contains another
        func isContained(_ smaller: Tag, _ larger: Tag) -> Bool {
            guard smaller.count <= larger.count else { return false }
            return smaller.enumerated().allSatisfy { index, value in
                index < larger.count && value == larger[index]
            }
        }

        // Process all tags
        let allTags = tags1 + tags2

        for tag in allTags {
            var shouldAdd = true
            var keyToRemove: String?

            // Check against existing tags
            for (key, existingTag) in tagMap {
                if isContained(existingTag, tag) || isContained(tag, existingTag) {
                    // Replace with the longer or equal-length tag
                    if tag.count >= existingTag.count {
                        keyToRemove = key
                    } else {
                        shouldAdd = false
                    }
                    break
                }
            }

            if let key = keyToRemove {
                tagMap.removeValue(forKey: key)
            }

            if shouldAdd {
                tagMap[generateKey(tag)] = tag
            }
        }

        return Array(tagMap.values)
    }

    /// Decode TLV (Type-Length-Value) encoded data
    private static func decodeTLV(_ data: [UInt8]) throws -> [UInt8: [[UInt8]]] {
        var result: [UInt8: [[UInt8]]] = [:]
        var index = 0

        while index < data.count {
            guard index + 1 < data.count else { break }

            let type = data[index]
            let length = Int(data[index + 1])
            index += 2

            guard index + length <= data.count else {
                throw NDKError.invalidDataFormat("bech32 data", details: ValidationConstants.expected32Bytes)
            }

            let value = Array(data[index ..< index + length])
            index += length

            if result[type] == nil {
                result[type] = []
            }
            result[type]?.append(value)
        }

        return result
    }

    /// Convert bytes to kind integer
    private static func kindFromBytes(_ bytes: [UInt8]) -> Int {
        guard bytes.count == 4 else { return 0 }
        return Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
    }
}

// MARK: - Filter Tag Helpers

public extension NDKFilter {
    /// Adds a hashtag filter
    mutating func addHashtagFilter(_ hashtags: String...) {
        addTagFilter("t", values: hashtags.map { $0.lowercased() })
    }

    /// Adds a URL filter
    mutating func addURLFilter(_ urls: String...) {
        addTagFilter("r", values: urls)
    }

    /// Checks if this filter includes a specific tag type
    func hasTagFilter(_ tagName: String) -> Bool {
        return tagFilter(tagName) != nil
    }
}
