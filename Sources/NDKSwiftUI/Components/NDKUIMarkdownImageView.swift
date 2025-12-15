import NDKSwiftCore
import SwiftUI

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
        case let .heading(level, text):
            renderHeading(level: level, text: text)

        case let .paragraph(inlines):
            renderInlineContent(inlines)

        case let .codeBlock(language, code):
            renderCodeBlock(language: language, code: code)

        case let .blockquote(inlines):
            renderBlockquote(inlines)

        case let .list(items, ordered):
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

    @ViewBuilder
    private func renderInlineContent(_ inlines: [MarkdownInline]) -> some View {
        // Group inline elements, separating images from text
        let groups = groupInlines(inlines)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                switch group {
                case let .text(inlines):
                    Text(buildAttributedString(from: inlines))
                        .font(configuration.bodyFont)
                        .foregroundColor(configuration.textColor)
                        .environment(\.openURL, OpenURLAction { url in
                            handleLinkTap(url)
                            return .handled
                        })

                case let .image(alt, url):
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
            case let .image(alt, url):
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
            case let .text(string):
                result += AttributedString(string)

            case let .bold(inlines):
                var boldText = buildAttributedString(from: inlines)
                boldText.font = configuration.bodyFont.bold()
                result += boldText

            case let .italic(inlines):
                var italicText = buildAttributedString(from: inlines)
                italicText.font = configuration.bodyFont.italic()
                result += italicText

            case let .code(text):
                var codeText = AttributedString(text)
                codeText.font = configuration.inlineCodeFont
                codeText.foregroundColor = configuration.inlineCodeColor
                codeText.backgroundColor = configuration.inlineCodeBackgroundColor
                result += codeText

            case let .link(text, url):
                var linkText = AttributedString(text)
                linkText.link = url
                linkText.foregroundColor = configuration.linkColor
                linkText.underlineStyle = configuration.linkUnderlineStyle
                result += linkText

            case let .nostrEntity(entity):
                result += renderNostrEntity(entity)

            case let .mention(pubkey):
                result += renderMention(pubkey)

            case let .hashtag(tag):
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
        case let .npub(pubkey):
            text = "@\(displayName(for: pubkey))"
        case let .nprofile(id):
            text = "@\(displayName(for: id))"
        case let .note(id):
            text = "📝 \(id.prefix(8))..."
        case let .nevent(id):
            text = "📝 \(id.prefix(8))..."
        case let .naddr(id):
            text = "📍 \(id.prefix(8))..."
        case let .userMention(pubkey, _):
            text = "@\(displayName(for: pubkey))"
        case let .eventMention(id):
            text = "📝 \(id.prefix(8))..."
        case let .hashtag(tag):
            text = "#\(tag)"
        case let .url(url):
            text = url.absoluteString
        case let .text(string):
            text = string
        }

        var attributed = AttributedString(text)
        attributed.foregroundColor = configuration.nostrEntityColor
        attributed.font = configuration.nostrEntityFont

        // Create appropriate nostr URL based on entity type
        let nostrUrlString: String
        switch entity {
        case let .npub(id):
            nostrUrlString = "nostr:npub\(id)"
        case let .nprofile(id):
            nostrUrlString = "nostr:nprofile\(id)"
        case let .note(id):
            nostrUrlString = "nostr:note\(id)"
        case let .nevent(id):
            nostrUrlString = "nostr:nevent\(id)"
        case let .naddr(id):
            nostrUrlString = "nostr:naddr\(id)"
        case let .userMention(_, npub):
            nostrUrlString = "nostr:\(npub)"
        case let .eventMention(id):
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
        .onAppear {
            parseContent()
        }
    }

    /// Add an image tap handler
    func onImageTap(_: @escaping (URL) -> Void) -> some View {
        renderImages()
    }
}
