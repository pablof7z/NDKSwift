import Foundation

/// Content tagging result
public struct ContentTag {
    public let tags: [Tag]
    public let content: String

    public init(tags: [Tag], content: String) {
        self.tags = tags
        self.content = content
    }
}

/// Decoded Nostr entity information
public struct DecodedNostrEntity {
    public let type: String
    public let eventId: String?
    public let pubkey: String?
    public let relays: [String]?
    public let kind: Int?
    public let identifier: String?
}

/// Content tagging utilities for NDK Swift
public enum ContentTagger {
    /// Generate hashtags from content
    public static func generateHashtags(from content: String) -> [String] {
        // Regex pattern for hashtags: #word (no special characters except underscore and hyphen)
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
    public static func decodeNostrEntity(_ entity: String) throws -> DecodedNostrEntity {
        let (hrp, data) = try Bech32.decode(entity)

        switch hrp {
        case "npub":
            guard data.count == 32 else {
                throw Bech32.Bech32Error.invalidData
            }
            let pubkey = Data(data).hexString
            return DecodedNostrEntity(type: "npub", eventId: nil, pubkey: pubkey, relays: nil, kind: nil, identifier: nil)

        case "note":
            guard data.count == 32 else {
                throw Bech32.Bech32Error.invalidData
            }
            let eventId = Data(data).hexString
            return DecodedNostrEntity(type: "note", eventId: eventId, pubkey: nil, relays: nil, kind: nil, identifier: nil)

        case "nprofile":
            let decoded = try decodeTLV(data)
            guard let pubkeyData = decoded[2]?.first, pubkeyData.count == 32 else {
                throw Bech32.Bech32Error.invalidData
            }
            let pubkey = Data(pubkeyData).hexString
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            return DecodedNostrEntity(type: "nprofile", eventId: nil, pubkey: pubkey, relays: relays.isEmpty ? nil : relays, kind: nil, identifier: nil)

        case "nevent":
            let decoded = try decodeTLV(data)
            guard let eventIdData = decoded[0]?.first, eventIdData.count == 32 else {
                throw Bech32.Bech32Error.invalidData
            }
            let eventId = Data(eventIdData).hexString
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            let pubkey = decoded[2]?.first.map { Data($0).hexString }
            let kind = decoded[3]?.first.map { kindFromBytes($0) }
            return DecodedNostrEntity(type: "nevent", eventId: eventId, pubkey: pubkey, relays: relays.isEmpty ? nil : relays, kind: kind, identifier: nil)

        case "naddr":
            let decoded = try decodeTLV(data)
            guard let identifierData = decoded[0]?.first,
                  let pubkeyData = decoded[2]?.first, pubkeyData.count == 32,
                  let kindData = decoded[3]?.first
            else {
                throw Bech32.Bech32Error.invalidData
            }
            let identifier = String(data: Data(identifierData), encoding: .utf8) ?? ""
            let pubkey = Data(pubkeyData).hexString
            let kind = kindFromBytes(kindData)
            let relays = decoded[1]?.compactMap { String(data: Data($0), encoding: .utf8) } ?? []
            let eventId = "\(kind):\(pubkey):\(identifier)"
            return DecodedNostrEntity(type: "naddr", eventId: eventId, pubkey: pubkey, relays: relays.isEmpty ? nil : relays, kind: kind, identifier: identifier)

        default:
            throw Bech32.Bech32Error.invalidHRP
        }
    }

    /// Generate content tags from text content
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
                            let relay = decoded.relays?.first ?? ""
                            newTag = ["q", eventId, relay]

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

                    // Replace the match with normalized nostr: format
                    modifiedContent.replaceSubrange(range, with: "nostr:\(entity)")

                } catch {
                    // If decoding fails, leave the original text
                    continue
                }
            }
        }

        // Add hashtag tags
        let hashtags = generateHashtags(from: modifiedContent)
        let hashtagTags = hashtags.map { ["t", $0] }
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
                throw Bech32.Bech32Error.invalidData
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
