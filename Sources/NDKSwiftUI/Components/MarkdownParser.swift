import Foundation
import NDKSwift

// MARK: - Markdown AST Types

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph([MarkdownInline])
    case codeBlock(language: String?, code: String)
    case blockquote([MarkdownInline])
    case list(items: [MarkdownList.Item], ordered: Bool)
    case horizontalRule
}

enum MarkdownInline {
    case text(String)
    case bold([MarkdownInline])
    case italic([MarkdownInline])
    case code(String)
    case link(text: String, url: URL)
    case image(alt: String, url: URL)
    case nostrEntity(ContentEntity)
    case mention(String) // pubkey
    case hashtag(String)
}

struct MarkdownList {
    struct Item {
        let content: [MarkdownInline]
        let subItems: [Item]
    }
}

// MARK: - Markdown Parser

struct MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        let lines = content.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0
        
        while index < lines.count {
            let line = lines[index]
            
            // Skip empty lines between blocks
            if line.trimmed.isEmpty {
                index += 1
                continue
            }
            
            // Check for different block types
            if let heading = parseHeading(line) {
                blocks.append(heading)
                index += 1
            } else if line.starts(with: "```") {
                let (codeBlock, newIndex) = parseCodeBlock(lines: lines, startIndex: index)
                if let codeBlock = codeBlock {
                    blocks.append(codeBlock)
                }
                index = newIndex
            } else if line.starts(with: ">") {
                let (blockquote, newIndex) = parseBlockquote(lines: lines, startIndex: index)
                if let blockquote = blockquote {
                    blocks.append(blockquote)
                }
                index = newIndex
            } else if isListItem(line) {
                let (list, newIndex) = parseList(lines: lines, startIndex: index)
                if let list = list {
                    blocks.append(list)
                }
                index = newIndex
            } else if line.trimmed == "---" ||
                      line.trimmed == "***" ||
                      line.trimmed == "___" {
                blocks.append(.horizontalRule)
                index += 1
            } else {
                // Parse as paragraph
                let (paragraph, newIndex) = parseParagraph(lines: lines, startIndex: index)
                if let paragraph = paragraph {
                    blocks.append(paragraph)
                }
                index = newIndex
            }
        }
        
        return blocks
    }
    
    // MARK: - Block Parsers
    
    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let trimmed = line.trimmed
        
        if trimmed.starts(with: "#") {
            var level = 0
            var index = trimmed.startIndex
            
            while index < trimmed.endIndex && trimmed[index] == "#" {
                level += 1
                index = trimmed.index(after: index)
            }
            
            if level > 0 && level <= 6 && index < trimmed.endIndex && trimmed[index] == " " {
                let text = String(trimmed[trimmed.index(after: index)...])
                    .trimmed
                return .heading(level: level, text: text)
            }
        }
        
        return nil
    }
    
    private static func parseCodeBlock(lines: [String], startIndex: Int) -> (MarkdownBlock?, Int) {
        guard startIndex < lines.count && lines[startIndex].starts(with: "```") else {
            return (nil, startIndex + 1)
        }
        
        let firstLine = lines[startIndex]
        let language = String(firstLine.dropFirst(3)).trimmed
        
        var codeLines: [String] = []
        var index = startIndex + 1
        
        while index < lines.count {
            if lines[index].starts(with: "```") {
                let code = codeLines.joined(separator: "\n")
                return (.codeBlock(language: language.isEmpty ? nil : language, code: code), index + 1)
            }
            codeLines.append(lines[index])
            index += 1
        }
        
        // Unclosed code block
        let code = codeLines.joined(separator: "\n")
        return (.codeBlock(language: language.isEmpty ? nil : language, code: code), index)
    }
    
    private static func parseBlockquote(lines: [String], startIndex: Int) -> (MarkdownBlock?, Int) {
        var quoteLines: [String] = []
        var index = startIndex
        
        while index < lines.count && lines[index].starts(with: ">") {
            let content = String(lines[index].dropFirst()).trimmed
            quoteLines.append(String(content))
            index += 1
        }
        
        if !quoteLines.isEmpty {
            let text = quoteLines.joined(separator: " ")
            let inlines = parseInline(text)
            return (.blockquote(inlines), index)
        }
        
        return (nil, startIndex + 1)
    }
    
    private static func isListItem(_ line: String) -> Bool {
        let trimmed = line.trimmed
        
        // Unordered list
        if trimmed.starts(with: "- ") || trimmed.starts(with: "* ") || trimmed.starts(with: "+ ") {
            return true
        }
        
        // Ordered list
        if let firstSpace = trimmed.firstIndex(of: " ") {
            let prefix = String(trimmed[..<firstSpace])
            if prefix.allSatisfy({ $0.isNumber }) && prefix.last == "." {
                return true
            }
        }
        
        return false
    }
    
    private static func parseList(lines: [String], startIndex: Int) -> (MarkdownBlock?, Int) {
        guard startIndex < lines.count && isListItem(lines[startIndex]) else {
            return (nil, startIndex + 1)
        }
        
        let firstLine = lines[startIndex].trimmed
        let isOrdered = !firstLine.starts(with: "-") && !firstLine.starts(with: "*") && !firstLine.starts(with: "+")
        
        var items: [MarkdownList.Item] = []
        var index = startIndex
        
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmed
            
            if trimmed.isEmpty {
                // Check if next line continues the list
                if index + 1 < lines.count && isListItem(lines[index + 1]) {
                    index += 1
                    continue
                } else {
                    break
                }
            }
            
            if !isListItem(line) {
                break
            }
            
            // Parse list item content
            let content: String
            if isOrdered {
                if let _ = trimmed.firstIndex(of: "."),
                   let spaceIndex = trimmed.firstIndex(of: " ") {
                    content = String(trimmed[trimmed.index(after: spaceIndex)...])
                } else {
                    content = trimmed
                }
            } else {
                content = String(trimmed.dropFirst(2))
            }
            
            let inlines = parseInline(content)
            items.append(MarkdownList.Item(content: inlines, subItems: []))
            index += 1
        }
        
        if !items.isEmpty {
            return (.list(items: items, ordered: isOrdered), index)
        }
        
        return (nil, startIndex + 1)
    }
    
    private static func parseParagraph(lines: [String], startIndex: Int) -> (MarkdownBlock?, Int) {
        var paragraphLines: [String] = []
        var index = startIndex
        
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmed
            
            // Stop at empty lines or block markers
            if trimmed.isEmpty ||
               trimmed.starts(with: "#") ||
               trimmed.starts(with: "```") ||
               trimmed.starts(with: ">") ||
               isListItem(line) ||
               trimmed == "---" || trimmed == "***" || trimmed == "___" {
                break
            }
            
            paragraphLines.append(line)
            index += 1
        }
        
        if !paragraphLines.isEmpty {
            let text = paragraphLines.joined(separator: " ")
            let inlines = parseInline(text)
            return (.paragraph(inlines), index)
        }
        
        return (nil, startIndex + 1)
    }
    
    // MARK: - Inline Parsers
    
    private static func parseInline(_ text: String) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var currentText = ""
        var index = text.startIndex
        
        while index < text.endIndex {
            // Check for inline code
            if text[index] == "`" {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (code, newIndex) = parseInlineCode(text, from: index)
                if let code = code {
                    result.append(.code(code))
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            // Check for bold
            if index < text.index(text.endIndex, offsetBy: -1) && 
               text[index] == "*" && text[text.index(after: index)] == "*" {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (bold, newIndex) = parseBold(text, from: index)
                if let bold = bold {
                    result.append(.bold(bold))
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            // Check for italic
            if text[index] == "*" || text[index] == "_" {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (italic, newIndex) = parseItalic(text, from: index)
                if let italic = italic {
                    result.append(.italic(italic))
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            // Check for images and links
            if text[index] == "!" && index < text.index(text.endIndex, offsetBy: -1) && 
               text[text.index(after: index)] == "[" {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (image, newIndex) = parseImage(text, from: index)
                if let image = image {
                    result.append(image)
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            // Check for links
            if text[index] == "[" {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (link, newIndex) = parseLink(text, from: index)
                if let link = link {
                    result.append(link)
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            // Check for Nostr entities
            if text[index] == "@" || text[index] == "#" || 
               (index < text.index(text.endIndex, offsetBy: -4) && 
                String(text[index..<text.index(index, offsetBy: 5)]).starts(with: "nostr")) {
                if !currentText.isEmpty {
                    result.append(.text(currentText))
                    currentText = ""
                }
                
                let (entity, newIndex) = parseNostrEntity(text, from: index)
                if let entity = entity {
                    result.append(entity)
                    index = newIndex
                } else {
                    currentText.append(text[index])
                    index = text.index(after: index)
                }
                continue
            }
            
            currentText.append(text[index])
            index = text.index(after: index)
        }
        
        if !currentText.isEmpty {
            result.append(.text(currentText))
        }
        
        return result
    }
    
    private static func parseInlineCode(_ text: String, from startIndex: String.Index) -> (String?, String.Index) {
        guard text[startIndex] == "`" else { return (nil, startIndex) }
        
        var index = text.index(after: startIndex)
        var code = ""
        
        while index < text.endIndex {
            if text[index] == "`" {
                return (code, text.index(after: index))
            }
            code.append(text[index])
            index = text.index(after: index)
        }
        
        return (nil, startIndex)
    }
    
    private static func parseBold(_ text: String, from startIndex: String.Index) -> ([MarkdownInline]?, String.Index) {
        guard startIndex < text.index(text.endIndex, offsetBy: -3),
              text[startIndex] == "*",
              text[text.index(after: startIndex)] == "*" else {
            return (nil, startIndex)
        }
        
        var index = text.index(startIndex, offsetBy: 2)
        var content = ""
        
        while index < text.index(text.endIndex, offsetBy: -1) {
            if text[index] == "*" && text[text.index(after: index)] == "*" {
                let inlines = parseInline(content)
                return (inlines, text.index(index, offsetBy: 2))
            }
            content.append(text[index])
            index = text.index(after: index)
        }
        
        return (nil, startIndex)
    }
    
    private static func parseItalic(_ text: String, from startIndex: String.Index) -> ([MarkdownInline]?, String.Index) {
        let marker = text[startIndex]
        guard marker == "*" || marker == "_" else { return (nil, startIndex) }
        
        var index = text.index(after: startIndex)
        var content = ""
        
        while index < text.endIndex {
            if text[index] == marker {
                let inlines = parseInline(content)
                return (inlines, text.index(after: index))
            }
            content.append(text[index])
            index = text.index(after: index)
        }
        
        return (nil, startIndex)
    }
    
    private static func parseLink(_ text: String, from startIndex: String.Index) -> (MarkdownInline?, String.Index) {
        guard text[startIndex] == "[" else { return (nil, startIndex) }
        
        var index = text.index(after: startIndex)
        var linkText = ""
        
        // Parse link text
        while index < text.endIndex && text[index] != "]" {
            linkText.append(text[index])
            index = text.index(after: index)
        }
        
        guard index < text.endIndex && text[index] == "]" else {
            return (nil, startIndex)
        }
        
        index = text.index(after: index)
        
        guard index < text.endIndex && text[index] == "(" else {
            return (nil, startIndex)
        }
        
        index = text.index(after: index)
        var urlString = ""
        
        // Parse URL
        while index < text.endIndex && text[index] != ")" {
            urlString.append(text[index])
            index = text.index(after: index)
        }
        
        guard index < text.endIndex && text[index] == ")" else {
            return (nil, startIndex)
        }
        
        if let url = URL(string: urlString) {
            return (.link(text: linkText, url: url), text.index(after: index))
        }
        
        return (nil, startIndex)
    }
    
    private static func parseImage(_ text: String, from startIndex: String.Index) -> (MarkdownInline?, String.Index) {
        guard startIndex < text.index(text.endIndex, offsetBy: -1),
              text[startIndex] == "!",
              text[text.index(after: startIndex)] == "[" else {
            return (nil, startIndex)
        }
        
        var index = text.index(startIndex, offsetBy: 2)
        var altText = ""
        
        // Parse alt text
        while index < text.endIndex && text[index] != "]" {
            altText.append(text[index])
            index = text.index(after: index)
        }
        
        guard index < text.endIndex && text[index] == "]" else {
            return (nil, startIndex)
        }
        
        index = text.index(after: index)
        
        guard index < text.endIndex && text[index] == "(" else {
            return (nil, startIndex)
        }
        
        index = text.index(after: index)
        var urlString = ""
        
        // Parse URL
        while index < text.endIndex && text[index] != ")" {
            urlString.append(text[index])
            index = text.index(after: index)
        }
        
        guard index < text.endIndex && text[index] == ")" else {
            return (nil, startIndex)
        }
        
        if let url = URL(string: urlString) {
            return (.image(alt: altText, url: url), text.index(after: index))
        }
        
        return (nil, startIndex)
    }
    
    private static func parseNostrEntity(_ text: String, from startIndex: String.Index) -> (MarkdownInline?, String.Index) {
        let remaining = String(text[startIndex...])
        
        // Check for mentions (@)
        if text[startIndex] == "@" {
            // Simple @mention parsing - look for word boundary
            var index = text.index(after: startIndex)
            var mention = ""
            
            while index < text.endIndex && 
                  (text[index].isLetter || text[index].isNumber || text[index] == "_") {
                mention.append(text[index])
                index = text.index(after: index)
            }
            
            if !mention.isEmpty {
                return (.mention(mention), index)
            }
        }
        
        // Check for hashtags (#)
        if text[startIndex] == "#" && startIndex < text.index(text.endIndex, offsetBy: -1) {
            let nextChar = text[text.index(after: startIndex)]
            if nextChar.isLetter || nextChar.isNumber {
                var index = text.index(after: startIndex)
                var tag = ""
                
                while index < text.endIndex && 
                      (text[index].isLetter || text[index].isNumber || text[index] == "_") {
                    tag.append(text[index])
                    index = text.index(after: index)
                }
                
                if !tag.isEmpty {
                    return (.hashtag(tag), index)
                }
            }
        }
        
        // Check for Nostr entities using ContentParser
        let result = ContentParser.parseContent(remaining)
        let entities = result.entities
        
        if let entity = entities.first {
            let entityLength: Int
            switch entity {
            case .text(let str):
                entityLength = str.count
            case .npub(let id), .nprofile(let id), .note(let id), 
                 .nevent(let id), .naddr(let id):
                // These entities include their prefix in the parsed content
                entityLength = id.count + 4 // prefix length
            case .hashtag(let tag):
                entityLength = tag.count + 1 // include #
            case .url(let url):
                entityLength = url.absoluteString.count
            case .userMention(_, let npub):
                entityLength = npub.count
            case .eventMention(let id):
                entityLength = id.count
            }
            let endIndex = text.index(startIndex, offsetBy: min(entityLength, text.distance(from: startIndex, to: text.endIndex)))
            return (.nostrEntity(entity), endIndex)
        }
        
        return (nil, startIndex)
    }
}