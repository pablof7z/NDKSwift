import Foundation

/// Represents parsed entities found in content
public enum ContentEntity: Equatable {
    case text(String)
    case npub(String) // Full bech32 string
    case nprofile(String) // Full bech32 string
    case note(String) // Full bech32 string
    case nevent(String) // Full bech32 string
    case naddr(String) // Full bech32 string
    case hashtag(String) // Just the tag without #
    case url(URL)
    case userMention(pubkey: String, npub: String) // For #[index] references
    case eventMention(String) // For #[index] references
}

/// Unified content parser for Nostr content
///
/// This parser handles:
/// - Entity extraction (npubs, notes, hashtags, URLs)
/// - Content normalization (@ mentions to nostr: format)
/// - Tag reference resolution (#[0], #[1], etc.)
/// - Current user mention detection
public enum ContentParser {
    /// Parse content for simple entity extraction (used by NDKEventBuilder)
    ///
    /// - Parameter content: The content to parse
    /// - Returns: Array of entities found and normalized content
    public static func parseContent(_ content: String) -> (entities: [ContentEntity], normalizedContent: String) {
        let result = parseContentWithContext(content, tags: [], currentUserPubkey: nil)
        return (entities: result.entities, normalizedContent: result.normalizedContent)
    }

    /// Parse content with full context (used by NDK's parseContent method)
    ///
    /// - Parameters:
    ///   - content: The content to parse
    ///   - tags: Event tags for resolving #[index] references
    ///   - currentUserPubkey: Current user's pubkey for mention detection
    /// - Returns: Full parsing result with entities, normalized content, and parsed content structure
    public static func parseContentWithContext(
        _ content: String,
        tags: [[String]],
        currentUserPubkey: PublicKey?
    ) -> (entities: [ContentEntity], normalizedContent: String, parsedContent: NDKParsedContent) {
        var entities: [ContentEntity] = []
        var components: [NDKParsedContent.Component] = []
        var modifiedContent = content
        var replacements: [(range: Range<String.Index>, replacement: String)] = []

        // Extract mention mappings from tags for #[index] references
        var mentionMap: [Int: String] = [:]
        var eventMap: [Int: String] = [:]

        for (index, tag) in tags.enumerated() {
            if tag.count >= 2 {
                switch tag[0] {
                case "p":
                    mentionMap[index] = tag[1]
                case "e":
                    eventMap[index] = tag[1]
                default:
                    break
                }
            }
        }

        // Process #[index] mentions first
        if let mentionRegex = try? NSRegularExpression(pattern: #"#\[(\d+)\]"#, options: []) {
            let matches = mentionRegex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))

            for match in matches.reversed() {
                if let range = Range(match.range, in: content),
                   let indexRange = Range(match.range(at: 1), in: content)
                {
                    let indexString = String(content[indexRange])
                    if let index = Int(indexString) {
                        // Check if it's a user mention
                        if let pubkey = mentionMap[index] {
                            let npub: String
                            do {
                                npub = try String.toNpub(pubkey)
                            } catch {
                                NDKLogger.log(.warning, category: .event, "Failed to convert pubkey to npub in #[index] mention: \(error)")
                                npub = pubkey
                            }
                            entities.append(.userMention(pubkey: pubkey, npub: npub))
                            components.append(.userMention(pubkey: pubkey, npub: npub))
                            replacements.append((range: range, replacement: "@\(npub)"))
                        }
                        // Check if it's an event mention
                        else if let eventId = eventMap[index] {
                            entities.append(.eventMention(eventId))
                            components.append(.eventMention(eventId))
                            replacements.append((range: range, replacement: "note:\(eventId.prefix(8))..."))
                        }
                    }
                }
            }
        }

        // Apply #[index] replacements
        for (range, replacement) in replacements.reversed() {
            modifiedContent.replaceSubrange(range, with: replacement)
        }

        // Define patterns for entity extraction
        let patterns: [(pattern: String, type: String)] = [
            // Nostr entities: @npub, @nprofile, nostr:npub, etc.
            (#"(@|nostr:)(npub1|nprofile1|note1|nevent1|naddr1)[a-zA-Z0-9]+"#, "nostr"),
            // Hashtags
            (#"(?<=\s|^)(#[^\s!@#$%^&*()=+./,\[{\]};:'"?><]+)"#, "hashtag"),
            // URLs
            (#"https?://[^\s<>"{}|\\^`\[\]]+"#, "url"),
        ]

        var allMatches: [(range: Range<String.Index>, type: String, value: String)] = []

        // Collect all matches from the modified content
        for (pattern, type) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: modifiedContent, options: [], range: NSRange(location: 0, length: modifiedContent.utf16.count))

            for match in matches {
                if let range = Range(match.range, in: modifiedContent) {
                    allMatches.append((range: range, type: type, value: String(modifiedContent[range])))
                }
            }
        }

        // Sort matches by position
        allMatches.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Reset replacements for @ mention normalization
        replacements = []
        var lastIndex = modifiedContent.startIndex

        // Process matches
        for match in allMatches {
            // Skip if this match overlaps with previous match
            if match.range.lowerBound < lastIndex { continue }

            // Add text component before this match
            if lastIndex < match.range.lowerBound {
                let textRange = lastIndex ..< match.range.lowerBound
                let text = String(modifiedContent[textRange])
                if !text.isEmpty {
                    entities.append(.text(text))
                    components.append(.text(text))
                }
            }

            // Process the match
            switch match.type {
            case "nostr":
                let fullMatch = match.value

                // Extract the bech32 part (after @ or nostr:)
                let bech32: String
                if fullMatch.hasPrefix("@") {
                    bech32 = String(fullMatch.dropFirst())
                    // Record replacement for @ mentions
                    replacements.append((range: match.range, replacement: "\(NostrConstants.nostrPrefix)\(bech32)"))
                } else if fullMatch.hasPrefix(NostrConstants.nostrPrefix) {
                    bech32 = String(fullMatch.dropFirst(NostrConstants.nostrPrefixLength))
                } else {
                    // Shouldn't happen based on regex
                    entities.append(.text(fullMatch))
                    components.append(.text(fullMatch))
                    lastIndex = match.range.upperBound
                    continue
                }

                // Identify entity type by prefix and add to both entities and components
                if bech32.hasPrefix(NostrConstants.npubPrefix) {
                    entities.append(.npub(bech32))
                    components.append(.npubMention(bech32))
                    do {
                        guard let pubkey = try String.fromNpub(bech32) else {
                            NDKLogger.log(.warning, category: .event, "Failed to decode npub: nil result")
                            continue
                        }
                        components.append(.userMention(pubkey: pubkey, npub: bech32))
                    } catch {
                        NDKLogger.log(.warning, category: .event, "Failed to decode npub: \(error)")
                    }
                } else if bech32.hasPrefix(NostrConstants.nprofilePrefix) {
                    entities.append(.nprofile(bech32))
                    components.append(.nprofileMention(bech32))
                } else if bech32.hasPrefix(NostrConstants.notePrefix) {
                    entities.append(.note(bech32))
                    components.append(.noteMention(bech32))
                    do {
                        let eventId = try Bech32.eventId(from: bech32)
                        components.append(.eventMention(eventId))
                    } catch {
                        NDKLogger.log(.warning, category: .event, "Failed to decode note: \(error)")
                    }
                } else if bech32.hasPrefix(NostrConstants.neventPrefix) {
                    entities.append(.nevent(bech32))
                    components.append(.neventMention(bech32))
                } else if bech32.hasPrefix(NostrConstants.naddrPrefix) {
                    entities.append(.naddr(bech32))
                    // NDKParsedContent doesn't have naddr component type, just store as text
                    components.append(.text(fullMatch))
                } else {
                    entities.append(.text(fullMatch))
                    components.append(.text(fullMatch))
                }

            case "hashtag":
                let tag = String(match.value.dropFirst()) // Remove #
                entities.append(.hashtag(tag))
                components.append(.hashtag(tag))

            case "url":
                if let url = URL(string: match.value) {
                    entities.append(.url(url))
                    components.append(.url(url))
                } else {
                    entities.append(.text(match.value))
                    components.append(.text(match.value))
                }

            default:
                entities.append(.text(match.value))
                components.append(.text(match.value))
            }

            lastIndex = match.range.upperBound
        }

        // Add remaining text
        if lastIndex < modifiedContent.endIndex {
            let text = String(modifiedContent[lastIndex...])
            if !text.isEmpty {
                entities.append(.text(text))
                components.append(.text(text))
            }
        }

        // Apply @ mention replacements to get normalized content
        var normalizedContent = modifiedContent
        for (range, replacement) in replacements.reversed() {
            normalizedContent.replaceSubrange(range, with: replacement)
        }

        // Check if current user is mentioned
        let isMentioningCurrentUser = currentUserPubkey.map { userPubkey in
            entities.contains { entity in
                switch entity {
                case let .userMention(pubkey, _):
                    return pubkey == userPubkey
                case let .npub(npub):
                    do {
                        guard let pubkey = try String.fromNpub(npub) else {
                            NDKLogger.log(.warning, category: .event, "Failed to decode npub for current user check: nil result")
                            return false
                        }
                        return pubkey == userPubkey
                    } catch {
                        NDKLogger.log(.warning, category: .event, "Failed to decode npub for current user check: \(error)")
                        return false
                    }
                default:
                    return false
                }
            }
        } ?? false

        let parsedContent = NDKParsedContent(
            original: content,
            components: components,
            isMentioningCurrentUser: isMentioningCurrentUser
        )

        return (entities: entities, normalizedContent: normalizedContent, parsedContent: parsedContent)
    }
}
