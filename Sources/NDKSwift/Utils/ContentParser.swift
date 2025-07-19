import Foundation

/// Represents parsed entities found in content without any tag generation logic
public enum ContentEntity: Equatable {
    case text(String)
    case npub(String) // Full bech32 string: npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s
    case nprofile(String) // Full bech32 string
    case note(String) // Full bech32 string
    case nevent(String) // Full bech32 string
    case naddr(String) // Full bech32 string
    case hashtag(String) // Just the tag without #
    case url(URL)
}

/// Pure content parser - only identifies entities, no tag generation
public enum ContentParser {
    
    /// Parse content and return identified entities
    /// 
    /// This parser:
    /// - Identifies nostr: URIs and @ mentions
    /// - Extracts hashtags
    /// - Finds URLs
    /// - Normalizes @ mentions to nostr: format
    /// 
    /// - Parameter content: The content to parse
    /// - Returns: Array of entities found in the content and normalized content
    public static func parseContent(_ content: String) -> (entities: [ContentEntity], normalizedContent: String) {
        var entities: [ContentEntity] = []
        var modifiedContent = content
        var replacements: [(range: Range<String.Index>, replacement: String)] = []
        
        // Define patterns
        let patterns: [(pattern: String, type: String)] = [
            // Nostr entities: @npub, @nprofile, nostr:npub, etc.
            (#"(@|nostr:)(npub1|nprofile1|note1|nevent1|naddr1)[a-zA-Z0-9]+"#, "nostr"),
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
        
        var lastIndex = content.startIndex
        
        // Process matches
        for match in allMatches {
            // Skip if this match overlaps with previous match
            if match.range.lowerBound < lastIndex { continue }
            
            // Add text entity before this match
            if lastIndex < match.range.lowerBound {
                let textRange = lastIndex..<match.range.lowerBound
                let text = String(content[textRange])
                if !text.isEmpty {
                    entities.append(.text(text))
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
                    lastIndex = match.range.upperBound
                    continue
                }
                
                // Identify entity type by prefix
                if bech32.hasPrefix("npub1") {
                    entities.append(.npub(bech32))
                } else if bech32.hasPrefix("nprofile1") {
                    entities.append(.nprofile(bech32))
                } else if bech32.hasPrefix("note1") {
                    entities.append(.note(bech32))
                } else if bech32.hasPrefix("nevent1") {
                    entities.append(.nevent(bech32))
                } else if bech32.hasPrefix("naddr1") {
                    entities.append(.naddr(bech32))
                } else {
                    entities.append(.text(fullMatch))
                }
                
            case "hashtag":
                let tag = String(match.value.dropFirst()) // Remove #
                entities.append(.hashtag(tag))
                
            case "url":
                if let url = URL(string: match.value) {
                    entities.append(.url(url))
                } else {
                    entities.append(.text(match.value))
                }
                
            default:
                entities.append(.text(match.value))
            }
            
            lastIndex = match.range.upperBound
        }
        
        // Add remaining text
        if lastIndex < content.endIndex {
            let text = String(content[lastIndex...])
            if !text.isEmpty {
                entities.append(.text(text))
            }
        }
        
        // Apply replacements in reverse order to maintain indices
        for (range, replacement) in replacements.reversed() {
            modifiedContent.replaceSubrange(range, with: replacement)
        }
        
        return (entities: entities, normalizedContent: modifiedContent)
    }
}