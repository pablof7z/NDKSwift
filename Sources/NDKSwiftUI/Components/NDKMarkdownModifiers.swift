import SwiftUI
import NDKSwift

// MARK: - Predefined Markdown Styles

public extension MarkdownConfiguration {
    /// A minimal style with clean typography
    static var minimal: MarkdownConfiguration {
        var config = MarkdownConfiguration()
        config.headingColor = .primary
        config.linkColor = .accentColor
        config.codeBackgroundColor = Color.gray.opacity(OpacityConstants.tertiary)
        config.blockquoteBorderColor = Color.gray.opacity(OpacityConstants.border)
        config.mentionColor = .accentColor
        config.hashtagColor = .purple
        config.nostrEntityColor = .orange
        return config
    }
    
    /// A dark mode optimized style
    static var dark: MarkdownConfiguration {
        var config = MarkdownConfiguration()
        config.textColor = Color.gray
        config.headingColor = .white
        config.linkColor = Color.blue
        config.codeColor = Color.gray
        config.codeBackgroundColor = Color.black.opacity(OpacityConstants.border)
        config.blockquoteColor = Color.gray.opacity(OpacityConstants.secondary)
        config.blockquoteBorderColor = Color.gray
        config.mentionColor = Color.blue
        config.hashtagColor = Color.purple
        config.nostrEntityColor = Color.orange
        return config
    }
    
    /// A style optimized for Nostr content
    static var nostr: MarkdownConfiguration {
        var config = MarkdownConfiguration()
        config.linkColor = Color(red: 0.6, green: 0.4, blue: 1.0) // Purple-ish
        config.mentionColor = Color(red: 0.4, green: 0.6, blue: 1.0) // Blue-ish
        config.hashtagColor = Color(red: 0.8, green: 0.4, blue: 0.8) // Pink-ish
        config.nostrEntityColor = Color(red: 1.0, green: 0.6, blue: 0.2) // Orange
        config.bulletCharacter = "⚡"
        return config
    }
    
    /// A compact style with reduced spacing
    static var compact: MarkdownConfiguration {
        var config = MarkdownConfiguration()
        config.paragraphSpacing = 8
        config.headingSpacing = 4
        config.listItemSpacing = 4
        config.contentPadding = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        return config
    }
}

// MARK: - View Extensions

public extension View {
    /// Adds markdown rendering capability to any text view
    func markdownText(_ content: String, ndk: NDK, style: MarkdownConfiguration = .minimal) -> some View {
        NDKMarkdownRenderer(content, ndk: ndk)
            .markdownStyle(style)
    }
}

// MARK: - NDK Extension for Markdown

public extension NDK {
    /// Creates a markdown renderer view for the given content
    func markdownView(_ content: String) -> NDKMarkdownRenderer {
        NDKMarkdownRenderer(content, ndk: self)
    }
}

// MARK: - Markdown Preview Component

/// A component that shows a preview of markdown content with a "Show More" button
public struct NDKMarkdownPreview: View {
    let content: String
    let ndk: NDK
    let previewLines: Int
    
    @State private var isExpanded = false
    
    var configuration = MarkdownConfiguration()
    
    public init(_ content: String, ndk: NDK, previewLines: Int = 3) {
        self.content = content
        self.ndk = ndk
        self.previewLines = previewLines
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isExpanded {
                NDKMarkdownRenderer(content, ndk: ndk)
                    .markdownStyle(configuration)
            } else {
                NDKMarkdownRenderer(truncatedContent, ndk: ndk)
                    .markdownStyle(configuration)
                    .lineLimit(previewLines)
            }
            
            if shouldShowToggle {
                Button(action: { isExpanded.toggle() }) {
                    Label(
                        isExpanded ? "Show Less" : "Show More",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var truncatedContent: String {
        let lines = content.components(separatedBy: .newlines)
        if lines.count <= previewLines {
            return content
        }
        return lines.prefix(previewLines).joined(separator: "\n")
    }
    
    private var shouldShowToggle: Bool {
        content.components(separatedBy: .newlines).count > previewLines
    }
}

public extension NDKMarkdownPreview {
    func markdownStyle(_ style: MarkdownConfiguration) -> Self {
        var view = self
        view.configuration = style
        return view
    }
}

// MARK: - Markdown Entity Renderer

/// A specialized component for rendering just the Nostr entities in text
public struct NDKNostrEntityText: View {
    let content: String
    let ndk: NDK
    
    @State private var parsedEntities: [ContentEntity] = []
    @State private var attributedString = AttributedString()
    
    var textColor = Color.primary
    var font = Font.body
    var mentionColor = Color.blue
    var hashtagColor = Color.purple
    var nostrEntityColor = Color.orange
    
    public init(_ content: String, ndk: NDK) {
        self.content = content
        self.ndk = ndk
    }
    
    public var body: some View {
        Text(attributedString)
            .task {
                await parseContent()
            }
    }
    
    private func parseContent() async {
        let result = ContentParser.parseContent(content)
        self.parsedEntities = result.entities
        
        var attributed = AttributedString(result.normalizedContent)
        attributed.font = font
        attributed.foregroundColor = textColor
        
        // Apply styling to entities
        for entity in result.entities {
            let entityText: String
            switch entity {
            case .npub(let id):
                entityText = "npub\(id)"
            case .nprofile(let id):
                entityText = "nprofile\(id)"
            case .note(let id):
                entityText = "note\(id)"
            case .nevent(let id):
                entityText = "nevent\(id)"
            case .naddr(let id):
                entityText = "naddr\(id)"
            case .userMention(_, let npub):
                entityText = npub
            case .eventMention(let id):
                entityText = "#[\(id)]"
            case .hashtag(let tag):
                entityText = "#\(tag)"
            case .url(let url):
                entityText = url.absoluteString
            case .text(_):
                continue
            }
            
            if let range = attributed.range(of: entityText) {
                switch entity {
                case .npub, .nprofile, .userMention:
                    attributed[range].foregroundColor = mentionColor
                    attributed[range].font = font.weight(.medium)
                case .note, .nevent, .naddr, .eventMention:
                    attributed[range].foregroundColor = nostrEntityColor
                    attributed[range].font = font.weight(.medium)
                case .hashtag:
                    attributed[range].foregroundColor = hashtagColor
                    attributed[range].font = font.weight(.medium)
                default:
                    break
                }
            }
        }
        
        // Apply hashtag styling
        let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+", options: [])
        let nsString = result.normalizedContent as NSString
        hashtagRegex?.enumerateMatches(
            in: result.normalizedContent,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        ) { match, _, _ in
            if let match = match,
               let range = Range(match.range, in: result.normalizedContent),
               let attributedRange = attributed.range(of: String(result.normalizedContent[range])) {
                attributed[attributedRange].foregroundColor = hashtagColor
                attributed[attributedRange].font = font.weight(.medium)
            }
        }
        
        self.attributedString = attributed
    }
}

// MARK: - Convenience Initializers

public extension NDKMarkdownRenderer {
    /// Initialize with an NDKEvent's content
    init(event: NDKEvent, ndk: NDK) {
        self.init(event.content, ndk: ndk)
    }
    
    /// Initialize with optional content, showing a placeholder if nil
    init(_ content: String?, ndk: NDK, placeholder: String = "No content") {
        self.init(content ?? placeholder, ndk: ndk)
    }
}