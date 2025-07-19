import Foundation

/// Utility functions for parsing Nostr content
public enum NDKContentParser {
    
    /// Remove "nostr:" prefix from a string
    private static func removeNostrPrefix(_ text: String) -> String {
        return text.replacingOccurrences(of: NostrConstants.nostrPrefix, with: "")
    }
    
    /// Parse content and extract mentions, hashtags, and other references
    public static func parseContent(
        _ content: String,
        tags: [[String]] = [],
        currentUser: NDKUser? = nil
    ) async -> NDKParsedContent {
        var components: [NDKParsedContent.Component] = []
        
        // Extract mention mappings from tags
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
        
        // Pattern for various content types
        let patterns: [(pattern: String, type: NDKParsedContent.ComponentType)] = [
            // Nostr mentions: #[index]
            (#"#\[(\d+)\]"#, .text),
            // Hashtags
            (#"(?:^|\s)#(\w+)"#, .hashtag("")),
            // URLs
            (#"https?://[^\s]+"#, .url(URL(string: "")!)),
            // npub mentions
            (#"nostr:npub1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+"#, .npubMention("")),
            // note mentions
            (#"nostr:note1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+"#, .noteMention("")),
            // nevent mentions
            (#"nostr:nevent1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+"#, .neventMention("")),
            // nprofile mentions
            (#"nostr:nprofile1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+"#, .nprofileMention(""))
        ]
        
        var processedContent = content
        var processedRanges: [Range<String.Index>] = []
        
        // Process #[index] mentions first
        if let mentionRegex = try? NSRegularExpression(pattern: #"#\[(\d+)\]"#, options: []) {
            let matches = mentionRegex.matches(in: processedContent, options: [], range: NSRange(processedContent.startIndex..., in: processedContent))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: processedContent),
                   let indexRange = Range(match.range(at: 1), in: processedContent) {
                    
                    let indexString = String(processedContent[indexRange])
                    if let index = Int(indexString) {
                        // Check if it's a user mention
                        if let pubkey = mentionMap[index] {
                            let npub = (try? String.toNpub(pubkey)) ?? pubkey
                            components.append(.userMention(pubkey: pubkey, npub: npub))
                            processedContent.replaceSubrange(range, with: "@\(npub)")
                        }
                        // Check if it's an event mention
                        else if let eventId = eventMap[index] {
                            components.append(.eventMention(eventId))
                            processedContent.replaceSubrange(range, with: "note:\(eventId.prefix(8))...")
                        }
                    }
                }
            }
        }
        
        // Process other patterns
        for (pattern, componentType) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: processedContent, options: [], range: NSRange(processedContent.startIndex..., in: processedContent))
                
                for match in matches {
                    if let range = Range(match.range, in: processedContent) {
                        // Skip if this range was already processed
                        if processedRanges.contains(where: { $0.overlaps(range) }) {
                            continue
                        }
                        
                        let matchedText = String(processedContent[range])
                        
                        switch componentType {
                        case .hashtag:
                            if match.numberOfRanges > 1,
                               let hashtagRange = Range(match.range(at: 1), in: processedContent) {
                                let hashtag = String(processedContent[hashtagRange])
                                components.append(.hashtag(hashtag))
                            }
                        case .url:
                            if let url = URL(string: matchedText) {
                                components.append(.url(url))
                            }
                        case .npubMention:
                            let npub = removeNostrPrefix(matchedText)
                            if let pubkey = try? String.fromNpub(npub) {
                                components.append(.userMention(pubkey: pubkey, npub: npub))
                            }
                        case .noteMention:
                            let noteId = removeNostrPrefix(matchedText)
                            if let eventId = try? decodeNoteId(noteId) {
                                components.append(.eventMention(eventId))
                            }
                        case .neventMention:
                            let nevent = removeNostrPrefix(matchedText)
                            components.append(.neventMention(nevent))
                        case .nprofileMention:
                            let nprofile = removeNostrPrefix(matchedText)
                            components.append(.nprofileMention(nprofile))
                        default:
                            break
                        }
                        
                        processedRanges.append(range)
                    }
                }
            }
        }
        
        // Add text components for remaining content
        components.append(.text(processedContent))
        
        // Check if current user is mentioned
        let isMentioningCurrentUser = currentUser.map { user in
            components.contains { component in
                switch component {
                case .userMention(let pubkey, _):
                    return pubkey == user.pubkey
                default:
                    return false
                }
            }
        } ?? false
        
        return NDKParsedContent(
            original: content,
            components: components,
            isMentioningCurrentUser: isMentioningCurrentUser
        )
    }
    
    // Helper to decode note ID (simplified version)
    private static func decodeNoteId(_ noteId: String) throws -> String? {
        // This would use proper bech32 decoding
        // For now, return nil to indicate we need proper implementation
        return nil
    }
}