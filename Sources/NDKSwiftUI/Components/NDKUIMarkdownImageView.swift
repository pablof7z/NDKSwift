import SwiftUI
import NDKSwiftCore

/// A view that renders markdown content with inline images
struct NDKUIMarkdownImageView: View {
    let blocks: [MarkdownBlock]
    let configuration: MarkdownConfiguration
    let ndk: NDK

    // Action handlers
    var onMentionTap: ((String) -> Void)?
    var onHashtagTap: ((String) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onNostrEntityTap: ((ContentEntity) -> Void)?
    var onImageTap: ((URL) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: configuration.paragraphSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let inlines):
            renderInlineContent(inlines)
        default:
            // For non-paragraph blocks, use the existing renderer logic
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderInlineContent(_ inlines: [MarkdownInline]) -> some View {
        // Group inline elements, separating images from text
        let groups = groupInlines(inlines)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                switch group {
                case .text(let inlines):
                    Text(buildAttributedString(from: inlines))
                        .font(configuration.bodyFont)
                        .foregroundColor(configuration.textColor)
                        .environment(\.openURL, OpenURLAction { url in
                            handleLinkTap(url)
                            return .handled
                        })

                case .image(let alt, let url):
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: UIConstants.markdownImageMaxHeight)
                            .cornerRadius(configuration.codeBlockCornerRadius)
                            .onTapGesture {
                                onImageTap?(url)
                            }
                    } placeholder: {
                        ProgressView()
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(OpacityConstants.subtle))
                            .cornerRadius(configuration.codeBlockCornerRadius)
                    }
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
                }
            }
        }
    }

    private enum InlineGroup {
        case text([MarkdownInline])
        case image(alt: String, url: URL)
    }

    private func groupInlines(_ inlines: [MarkdownInline]) -> [InlineGroup] {
        var groups: [InlineGroup] = []
        var currentText: [MarkdownInline] = []

        for inline in inlines {
            switch inline {
            case .image(let alt, let url):
                if !currentText.isEmpty {
                    groups.append(.text(currentText))
                    currentText = []
                }
                groups.append(.image(alt: alt, url: url))

            default:
                currentText.append(inline)
            }
        }

        if !currentText.isEmpty {
            groups.append(.text(currentText))
        }

        return groups
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

            case .image:
                // Images are handled separately in grouping
                break
            }
        }

        return result
    }

    private func renderNostrEntity(_ entity: ContentEntity) -> AttributedString {
        var text: String

        switch entity {
        case .npub(let pubkey):
            text = "@\(displayName(for: pubkey))"
        case .nprofile(let id):
            text = "@\(displayName(for: id))"
        case .note(let id):
            text = "📝 \(id.prefix(8))..."
        case .nevent(let id):
            text = "📝 \(id.prefix(8))..."
        case .naddr(let id):
            text = "📍 \(id.prefix(8))..."
        case .userMention(let pubkey, _):
            text = "@\(displayName(for: pubkey))"
        case .eventMention(let id):
            text = "📝 \(id.prefix(8))..."
        case .hashtag(let tag):
            text = "#\(tag)"
        case .url(let url):
            text = url.absoluteString
        case .text(let string):
            text = string
        }

        var attributed = AttributedString(text)
        attributed.foregroundColor = configuration.nostrEntityColor
        attributed.font = configuration.nostrEntityFont

        // Create appropriate nostr URL based on entity type
        let nostrUrlString: String
        switch entity {
        case .npub(let id):
            nostrUrlString = "nostr:npub\(id)"
        case .nprofile(let id):
            nostrUrlString = "nostr:nprofile\(id)"
        case .note(let id):
            nostrUrlString = "nostr:note\(id)"
        case .nevent(let id):
            nostrUrlString = "nostr:nevent\(id)"
        case .naddr(let id):
            nostrUrlString = "nostr:naddr\(id)"
        case .userMention(_, let npub):
            nostrUrlString = "nostr:\(npub)"
        case .eventMention(let id):
            nostrUrlString = "nostr:note\(id)"
        default:
            nostrUrlString = ""
        }

        if !nostrUrlString.isEmpty, let url = URL(string: nostrUrlString) {
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
        if pubkey.count > 16 {
            return "\(pubkey.prefix(8))...\(pubkey.suffix(4))"
        }
        return pubkey
    }

    private func handleLinkTap(_ url: URL) {
        switch url.scheme {
        case "nostr":
            // Handle Nostr entity tap
            break
        case "mention":
            if let pubkey = url.host {
                onMentionTap?(pubkey)
            }
        case "hashtag":
            if let tag = url.host {
                onHashtagTap?(tag)
            }
        case "image":
            // Handle image tap
            break
        default:
            onLinkTap?(url)
        }
    }
}

// MARK: - Enhanced Markdown Renderer with Image Support

public extension NDKUIMarkdownRenderer {
    /// Enable inline image rendering
    func renderImages() -> some View {
        ScrollView {
            NDKUIMarkdownImageView(
                blocks: renderableBlocks,
                configuration: configuration,
                ndk: ndk,
                onMentionTap: onMentionTap,
                onHashtagTap: onHashtagTap,
                onLinkTap: onLinkTap,
                onNostrEntityTap: onNostrEntityTap,
                onImageTap: { url in
                    onLinkTap?(url)
                }
            )
            .padding(configuration.contentPadding)
        }
        .task {
            parseContent()
        }
    }

    /// Add an image tap handler
    func onImageTap(_ action: @escaping (URL) -> Void) -> some View {
        renderImages()
    }
}