import SwiftUI
import NDKSwift

/// A SwiftUI component that renders markdown content with Nostr entity parsing
public struct NDKMarkdownRenderer: View {
    let content: String
    let ndk: NDK
    
    @State private var parsedEntities: [ContentEntity] = []
    @State private var normalizedContent: String = ""
    
    // Styling configuration
    var configuration = MarkdownConfiguration()
    
    // Action handlers
    var onMentionTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onNostrEntityTap: ((ContentEntity) -> Void)?
    
    public init(
        _ content: String,
        ndk: NDK
    ) {
        self.content = content
        self.ndk = ndk
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: configuration.paragraphSpacing) {
                ForEach(Array(renderableBlocks.enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
            .padding(configuration.contentPadding)
        }
        .task {
            parseContent()
        }
    }
    
    // MARK: - Private Methods
    
    func parseContent() {
        let result = ContentParser.parseContent(content)
        self.parsedEntities = result.entities
        self.normalizedContent = result.normalizedContent
    }
    
    var renderableBlocks: [MarkdownBlock] {
        MarkdownParser.parse(normalizedContent)
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)
            
        case .paragraph(let inlines):
            renderParagraph(inlines)
            
        case .codeBlock(let language, let code):
            renderCodeBlock(language: language, code: code)
            
        case .blockquote(let inlines):
            renderBlockquote(inlines)
            
        case .list(let items, let ordered):
            renderList(items: items, ordered: ordered)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, configuration.horizontalRulePadding)
        }
    }
    
    @ViewBuilder
    private func renderHeading(level: Int, text: String) -> some View {
        Text(text)
            .font(configuration.headingFont(for: level))
            .foregroundColor(configuration.headingColor)
            .padding(.bottom, configuration.headingSpacing)
    }
    
    @ViewBuilder
    private func renderParagraph(_ inlines: [MarkdownInline]) -> some View {
        Text(buildAttributedString(from: inlines))
            .font(configuration.bodyFont)
            .foregroundColor(configuration.textColor)
            .environment(\.openURL, OpenURLAction { url in
                handleLinkTap(url)
                return .handled
            })
    }
    
    @ViewBuilder
    private func renderCodeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = language {
                Text(language)
                    .font(configuration.codeLanguageFont)
                    .foregroundColor(configuration.codeLanguageColor)
                    .padding(.horizontal, configuration.codeBlockPadding)
                    .padding(.top, configuration.codeBlockPadding)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(configuration.codeFont)
                    .foregroundColor(configuration.codeColor)
                    .padding(configuration.codeBlockPadding)
            }
        }
        .background(configuration.codeBackgroundColor)
        .cornerRadius(configuration.codeBlockCornerRadius)
    }
    
    @ViewBuilder
    private func renderBlockquote(_ inlines: [MarkdownInline]) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(configuration.blockquoteBorderColor)
                .frame(width: configuration.blockquoteBorderWidth)
            
            Text(buildAttributedString(from: inlines))
                .font(configuration.blockquoteFont)
                .foregroundColor(configuration.blockquoteColor)
                .padding(.leading, configuration.blockquotePadding)
        }
        .padding(.vertical, configuration.blockquoteVerticalPadding)
    }
    
    @ViewBuilder
    private func renderList(items: [MarkdownList.Item], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: configuration.listItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: configuration.listBulletSpacing) {
                    Text(ordered ? "\(index + 1)." : configuration.bulletCharacter)
                        .font(configuration.listBulletFont)
                        .foregroundColor(configuration.listBulletColor)
                        .frame(minWidth: configuration.listBulletMinWidth, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: configuration.listItemInternalSpacing) {
                        Text(buildAttributedString(from: item.content))
                            .font(configuration.bodyFont)
                            .foregroundColor(configuration.textColor)
                        
                        // Handle sub-items without recursion for now
                        if !item.subItems.isEmpty {
                            VStack(alignment: .leading, spacing: configuration.listItemSpacing) {
                                ForEach(Array(item.subItems.enumerated()), id: \.offset) { subIndex, subItem in
                                    HStack(alignment: .top, spacing: configuration.listBulletSpacing) {
                                        Text(ordered ? "\(subIndex + 1)." : configuration.bulletCharacter)
                                            .font(configuration.listBulletFont)
                                            .foregroundColor(configuration.listBulletColor)
                                            .frame(minWidth: configuration.listBulletMinWidth, alignment: .trailing)
                                        
                                        Text(buildAttributedString(from: subItem.content))
                                            .font(configuration.bodyFont)
                                            .foregroundColor(configuration.textColor)
                                    }
                                }
                            }
                            .padding(.leading, configuration.listIndentation)
                        }
                    }
                }
            }
        }
    }
    
    private func buildAttributedString(from inlines: [MarkdownInline]) -> AttributedString {
        var result = AttributedString()
        
        for inline in inlines {
            switch inline {
            case .text(let string):
                result += AttributedString(string)
                
            case .bold(let inlines):
                var boldText = buildAttributedString(from: inlines)
                boldText.font = configuration.bodyFont.bold()
                result += boldText
                
            case .italic(let inlines):
                var italicText = buildAttributedString(from: inlines)
                italicText.font = configuration.bodyFont.italic()
                result += italicText
                
            case .code(let text):
                var codeText = AttributedString(text)
                codeText.font = configuration.inlineCodeFont
                codeText.foregroundColor = configuration.inlineCodeColor
                codeText.backgroundColor = configuration.inlineCodeBackgroundColor
                result += codeText
                
            case .link(let text, let url):
                var linkText = AttributedString(text)
                linkText.link = url
                linkText.foregroundColor = configuration.linkColor
                linkText.underlineStyle = configuration.linkUnderlineStyle
                result += linkText
                
            case .nostrEntity(let entity):
                result += renderNostrEntity(entity)
                
            case .mention(let pubkey):
                result += renderMention(pubkey)
                
            case .hashtag(let tag):
                result += renderHashtag(tag)
                
            case .image(_, let url):
                // Images need special handling in SwiftUI, we'll mark them with a special link
                var imageText = AttributedString(" 🖼 ")
                imageText.link = URL(string: "image:\(url.absoluteString)")
                imageText.foregroundColor = configuration.linkColor
                result += imageText
            }
        }
        
        return result
    }
    
    private func renderNostrEntity(_ entity: ContentEntity) -> AttributedString {
        var text: String
        var entityString: String
        
        switch entity {
        case .npub(let pubkey):
            text = "@\(displayName(for: pubkey))"
            entityString = "npub\(pubkey)"
        case .nprofile(let id):
            text = "@\(displayName(for: id))"
            entityString = "nprofile\(id)"
        case .note(let id):
            text = "📝 \(id.prefix(8))..."
            entityString = "note\(id)"
        case .nevent(let id):
            text = "📝 \(id.prefix(8))..."
            entityString = "nevent\(id)"
        case .naddr(let id):
            text = "📍 \(id.prefix(8))..."
            entityString = "naddr\(id)"
        case .userMention(let pubkey, let npub):
            text = "@\(displayName(for: pubkey))"
            entityString = npub
        case .eventMention(let id):
            text = "📝 \(id.prefix(8))..."
            entityString = "note\(id)"
        case .hashtag(let tag):
            return renderHashtag(tag)
        case .url(let url):
            var linkText = AttributedString(url.absoluteString)
            linkText.link = url
            linkText.foregroundColor = configuration.linkColor
            linkText.underlineStyle = configuration.linkUnderlineStyle
            return linkText
        case .text(let string):
            return AttributedString(string)
        }
        
        var attributed = AttributedString(text)
        attributed.foregroundColor = configuration.nostrEntityColor
        attributed.font = configuration.nostrEntityFont
        
        // Add tap handler via link
        if let url = URL(string: "nostr:\(entityString)") {
            attributed.link = url
        }
        
        return attributed
    }
    
    private func renderMention(_ pubkey: String) -> AttributedString {
        let displayText = "@\(displayName(for: pubkey))"
        var attributed = AttributedString(displayText)
        attributed.foregroundColor = configuration.mentionColor
        attributed.font = configuration.mentionFont
        
        if let url = URL(string: "mention:\(pubkey)") {
            attributed.link = url
        }
        
        return attributed
    }
    
    private func renderHashtag(_ tag: String) -> AttributedString {
        var attributed = AttributedString("#\(tag)")
        attributed.foregroundColor = configuration.hashtagColor
        attributed.font = configuration.hashtagFont
        
        if let url = URL(string: "hashtag:\(tag)") {
            attributed.link = url
        }
        
        return attributed
    }
    
    private func displayName(for pubkey: String) -> String {
        // TODO: Fetch profile from NDK to get display name
        // For now, return shortened pubkey
        if pubkey.count > 16 {
            return "\(pubkey.prefix(8))...\(pubkey.suffix(4))"
        }
        return pubkey
    }
    
    private func handleLinkTap(_ url: URL) {
        switch url.scheme {
        case "nostr":
            // Extract the entity identifier from the URL
            let urlString = url.absoluteString
            if let entity = parsedEntities.first(where: { entity in
                switch entity {
                case .npub(let id), .nprofile(let id), .note(let id), 
                     .nevent(let id), .naddr(let id):
                    return urlString.contains(id)
                case .userMention(_, let npub):
                    return urlString.contains(npub)
                case .eventMention(let id):
                    return urlString.contains(id)
                default:
                    return false
                }
            }) {
                onNostrEntityTap?(entity)
            }
        case "mention":
            if let pubkey = url.host {
                onMentionTap?(pubkey)
            }
        case "hashtag":
            if let tag = url.host {
                onHashtagTap?(tag)
            }
        default:
            onLinkTap?(url)
        }
    }
}

// MARK: - View Modifiers

public extension NDKMarkdownRenderer {
    func onMentionTap(_ action: @escaping (String) -> Void) -> Self {
        var view = self
        view.onMentionTap = action
        return view
    }
    
    func onHashtagTap(_ action: @escaping (String) -> Void) -> Self {
        var view = self
        view.onHashtagTap = action
        return view
    }
    
    func onLinkTap(_ action: @escaping (URL) -> Void) -> Self {
        var view = self
        view.onLinkTap = action
        return view
    }
    
    func onNostrEntityTap(_ action: @escaping (ContentEntity) -> Void) -> Self {
        var view = self
        view.onNostrEntityTap = action
        return view
    }
    
    func markdownStyle(_ style: MarkdownConfiguration) -> Self {
        var view = self
        view.configuration = style
        return view
    }
}

// MARK: - Configuration

public struct MarkdownConfiguration {
    // Colors
    public var textColor = Color.primary
    public var headingColor = Color.primary
    public var linkColor = Color.blue
    public var codeColor = Color.primary
    public var codeBackgroundColor = Color.gray.opacity(0.1)
    public var codeLanguageColor = Color.secondary
    public var blockquoteColor = Color.secondary
    public var blockquoteBorderColor = Color.gray
    public var mentionColor = Color.blue
    public var hashtagColor = Color.purple
    public var nostrEntityColor = Color.orange
    public var listBulletColor = Color.secondary
    public var inlineCodeColor = Color.primary
    public var inlineCodeBackgroundColor = Color.gray.opacity(0.1)
    
    // Fonts
    public var bodyFont = Font.body
    public var h1Font = Font.largeTitle
    public var h2Font = Font.title
    public var h3Font = Font.title2
    public var h4Font = Font.title3
    public var h5Font = Font.headline
    public var h6Font = Font.subheadline
    public var codeFont = Font.system(.body, design: .monospaced)
    public var codeLanguageFont = Font.caption
    public var blockquoteFont = Font.body.italic()
    public var mentionFont = Font.body.weight(.medium)
    public var hashtagFont = Font.body.weight(.medium)
    public var nostrEntityFont = Font.body.weight(.medium)
    public var listBulletFont = Font.body
    public var inlineCodeFont = Font.system(.body, design: .monospaced)
    
    // Spacing
    public var paragraphSpacing: CGFloat = 12
    public var headingSpacing: CGFloat = 8
    public var listItemSpacing: CGFloat = 8
    public var listItemInternalSpacing: CGFloat = 4
    public var listBulletSpacing: CGFloat = 8
    public var horizontalRulePadding: CGFloat = 16
    public var blockquoteVerticalPadding: CGFloat = 8
    
    // Dimensions
    public var codeBlockPadding: CGFloat = 12
    public var codeBlockCornerRadius: CGFloat = 8
    public var blockquoteBorderWidth: CGFloat = 4
    public var blockquotePadding: CGFloat = 12
    public var listIndentation: CGFloat = 20
    public var listBulletMinWidth: CGFloat = 20
    public var contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    
    // Styling
    public var bulletCharacter = "•"
    public var linkUnderlineStyle: Text.LineStyle = .single
    
    public init() {}
    
    func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return h1Font
        case 2: return h2Font
        case 3: return h3Font
        case 4: return h4Font
        case 5: return h5Font
        case 6: return h6Font
        default: return h6Font
        }
    }
}