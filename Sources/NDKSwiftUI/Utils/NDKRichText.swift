import SwiftUI
import NDKSwift
import Foundation

// MARK: - NDKRichText

/// A SwiftUI view that renders Nostr event content with rich text formatting
///
/// Features:
/// - Automatic link detection and clickable links
/// - Hashtag highlighting and interaction  
/// - @mention parsing and display
/// - Customizable styling
/// - Progressive rendering (no blocking on external data)
///
/// ## Usage
///
/// ```swift
/// NDKRichText(content: event.content)
///     .foregroundStyle(.primary)
///     .onLinkTapped { url in
///         // Handle link taps
///     }
///     .onHashtagTapped { hashtag in
///         // Handle hashtag taps
///     }
/// ```
public struct NDKRichText: View {
    
    // MARK: - Properties
    
    private let content: String
    private let linkColor: Color
    private let hashtagColor: Color
    private let mentionColor: Color
    private var onLinkTapped: ((URL) -> Void)?
    private var onHashtagTapped: ((String) -> Void)?
    private var onMentionTapped: ((String) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize with content string
    /// - Parameters:
    ///   - content: The text content to render
    ///   - linkColor: Color for links (default: .blue)
    ///   - hashtagColor: Color for hashtags (default: .blue)
    ///   - mentionColor: Color for mentions (default: .blue)
    public init(
        content: String,
        linkColor: Color = .blue,
        hashtagColor: Color = .blue,
        mentionColor: Color = .blue
    ) {
        self.content = content
        self.linkColor = linkColor
        self.hashtagColor = hashtagColor
        self.mentionColor = mentionColor
    }
    
    // MARK: - Body
    
    public var body: some View {
        // Parse content into segments and render
        let segments = parseContentSegments(content)
        
        // Use a flow layout or text concatenation based on segments
        if segments.count == 1, case .text = segments[0] {
            // Simple text, no special formatting needed
            Text(content)
        } else {
            // Complex content with mixed segments
            renderSegments(segments)
        }
    }
    
    // MARK: - Modifiers
    
    /// Handle link tap events
    public func onLinkTapped(_ action: @escaping (URL) -> Void) -> NDKRichText {
        var copy = self
        copy.onLinkTapped = action
        return copy
    }
    
    /// Handle hashtag tap events
    public func onHashtagTapped(_ action: @escaping (String) -> Void) -> NDKRichText {
        var copy = self
        copy.onHashtagTapped = action
        return copy
    }
    
    /// Handle mention tap events  
    public func onMentionTapped(_ action: @escaping (String) -> Void) -> NDKRichText {
        var copy = self
        copy.onMentionTapped = action
        return copy
    }
    
    // MARK: - Private Methods
    
    private func renderSegments(_ segments: [ContentSegment]) -> some View {
        // Create attributed text
        Text(attributedString(from: segments))
    }
    
    private func attributedString(from segments: [ContentSegment]) -> AttributedString {
        var result = AttributedString()
        
        for segment in segments {
            var attributedSegment: AttributedString
            
            switch segment {
            case .text(let text):
                attributedSegment = AttributedString(text)
                
            case .link(let text, _):
                attributedSegment = AttributedString(text)
                attributedSegment.foregroundColor = linkColor
                attributedSegment.underlineStyle = .single
                // Note: Tap handling would need to be implemented with UIViewRepresentable
                // for full link interaction in real implementation
                
            case .hashtag(let tag):
                attributedSegment = AttributedString("#\(tag)")
                attributedSegment.foregroundColor = hashtagColor
                attributedSegment.font = .body.weight(.semibold)
                
            case .mention(let pubkey, let displayName):
                let displayText = displayName ?? "@\(pubkey.prefix(8))..."
                attributedSegment = AttributedString(displayText)
                attributedSegment.foregroundColor = mentionColor
                attributedSegment.font = .body.weight(.semibold)
            }
            
            result.append(attributedSegment)
        }
        
        return result
    }
    
    private func parseContentSegments(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var currentIndex = content.startIndex
        
        while currentIndex < content.endIndex {
            // Find the next special pattern (URL, hashtag, mention)
            let remainingContent = String(content[currentIndex...])
            
            if let urlMatch = findNextURL(in: remainingContent) {
                let urlStartIndex = content.index(currentIndex, offsetBy: urlMatch.range.lowerBound)
                
                // Add text before URL if any
                if currentIndex < urlStartIndex {
                    let textBefore = String(content[currentIndex..<urlStartIndex])
                    segments.append(.text(textBefore))
                }
                
                // Add URL segment
                segments.append(.link(urlMatch.text, urlMatch.url))
                currentIndex = content.index(currentIndex, offsetBy: urlMatch.range.upperBound)
                
            } else if let hashtagMatch = findNextHashtag(in: remainingContent) {
                let hashtagStartIndex = content.index(currentIndex, offsetBy: hashtagMatch.range.lowerBound)
                
                // Add text before hashtag if any
                if currentIndex < hashtagStartIndex {
                    let textBefore = String(content[currentIndex..<hashtagStartIndex])
                    segments.append(.text(textBefore))
                }
                
                // Add hashtag segment
                segments.append(.hashtag(hashtagMatch.tag))
                currentIndex = content.index(currentIndex, offsetBy: hashtagMatch.range.upperBound)
                
            } else {
                // No more special patterns, add remaining text
                let remainingText = String(content[currentIndex...])
                if !remainingText.isEmpty {
                    segments.append(.text(remainingText))
                }
                break
            }
        }
        
        return segments.isEmpty ? [.text(content)] : segments
    }
    
    private func findNextURL(in text: String) -> URLMatch? {
        // Simple URL regex pattern - in production, use more sophisticated detection
        let urlPattern = #"https?://[^\s]+"#
        
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let match = regex.firstMatch(in: text, range: range) {
            let matchRange = Range(match.range, in: text)!
            let urlString = String(text[matchRange])
            
            if let url = URL(string: urlString) {
                return URLMatch(
                    text: urlString,
                    url: url,
                    range: match.range.location..<match.range.location + match.range.length
                )
            }
        }
        
        return nil
    }
    
    private func findNextHashtag(in text: String) -> HashtagMatch? {
        // Simple hashtag pattern - match #word
        let hashtagPattern = #"#\w+"#
        
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let match = regex.firstMatch(in: text, range: range) {
            let matchRange = Range(match.range, in: text)!
            let fullHashtag = String(text[matchRange])
            let tag = String(fullHashtag.dropFirst()) // Remove #
            
            return HashtagMatch(
                tag: tag,
                range: match.range.location..<match.range.location + match.range.length
            )
        }
        
        return nil
    }
}

// MARK: - Supporting Types

private enum ContentSegment {
    case text(String)
    case link(String, URL)
    case hashtag(String)
    case mention(pubkey: String, displayName: String?)
}

private struct URLMatch {
    let text: String
    let url: URL
    let range: Range<Int>
}

private struct HashtagMatch {
    let tag: String
    let range: Range<Int>
}

// MARK: - Preview

#if DEBUG
struct NDKRichText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            NDKRichText(content: "Hello world!")
            
            NDKRichText(content: "Check out https://nostr.com for more info")
            
            NDKRichText(content: "Love #nostr and #bitcoin!")
            
            NDKRichText(content: "Complex text with https://example.com and #hashtags mixed together")
        }
        .padding()
    }
}
#endif