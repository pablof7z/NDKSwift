import NDKSwiftCore
import SwiftUI

/// A generic markdown view that renders parsed markdown content with pluggable inline renderers
public struct NDKUIMarkdownView<
    Mention: MentionRenderer,
    Hashtag: HashtagRenderer,
    Link: LinkRenderer,
    Image: ImageRenderer,
    Event: EventRenderer
>: View {
    let content: String
    let tags: [Tag]
    let blockConfig: MarkdownBlockConfig

    @Environment(\.ndk) private var ndk
    @State private var parsedBlocks: [MarkdownBlock] = []

    public init(
        content: String,
        tags: [Tag] = [],
        blockConfig: MarkdownBlockConfig = .default
    ) {
        self.content = content
        self.tags = tags
        self.blockConfig = blockConfig
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: blockConfig.blockSpacing) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .task(id: content) {
            parsedBlocks = MarkdownParser.parse(content)
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(blockConfig.headingFont(for: level))
                .foregroundColor(blockConfig.headingColor)

        case .paragraph(let inlines):
            renderInlines(inlines)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(code)
                    .font(blockConfig.codeFont)
                    .padding(blockConfig.codePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(blockConfig.codeBackgroundColor)
                    .cornerRadius(blockConfig.codeCornerRadius)
            }

        case .blockquote(let inlines):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(blockConfig.blockquoteBorderColor)
                    .frame(width: 3)
                renderInlines(inlines)
                    .foregroundColor(blockConfig.blockquoteTextColor)
                    .padding(.leading, 12)
            }

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: blockConfig.listItemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        if ordered {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                        } else {
                            Text("•")
                                .foregroundColor(.secondary)
                        }
                        renderInlines(item.content)
                    }
                    .padding(.leading, blockConfig.listIndent)
                }
            }

        case .horizontalRule:
            Divider()
        }
    }

    // MARK: - Grouped Inline Rendering

    private typealias GroupedInline = ImageGroupingUtils.GroupedResult<MarkdownInline>

    @ViewBuilder
    private func renderInlines(_ inlines: [MarkdownInline]) -> some View {
        let grouped = ImageGroupingUtils.groupConsecutiveImages(
            inlines,
            getImageURL: { inline in
                if case .image(_, let url) = inline {
                    return url
                }
                return nil
            },
            isWhitespaceText: { inline in
                if case .text(let text) = inline {
                    let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if stripped.isEmpty { return true }
                    // Also treat as whitespace if only punctuation remains
                    return stripped.allSatisfy { $0.isPunctuation || $0.isWhitespace }
                }
                return false
            }
        )

        FlowLayout(alignment: .leading, spacing: 0) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { _, item in
                renderGroupedInline(item)
            }
        }
    }

    @ViewBuilder
    private func renderGroupedInline(_ item: GroupedInline) -> some View {
        switch item {
        case .single(let inline):
            renderInline(inline)
        case .imageGroup(let urls):
            Image(urls: urls, onTap: nil)
        }
    }

    @ViewBuilder
    private func renderInline(_ inline: MarkdownInline) -> some View {
        switch inline {
        case .text(let text):
            Text(text)

        case .bold(let children):
            // Flatten bold children to text for simplicity
            Text(inlineChildrenToText(children))
                .bold()

        case .italic(let children):
            // Flatten italic children to text for simplicity
            Text(inlineChildrenToText(children))
                .italic()

        case .code(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .background(blockConfig.codeBackgroundColor)
                .cornerRadius(4)

        case .link(_, let url):
            Link(url: url, onTap: nil)

        case .image(_, let url):
            Image(urls: [url], onTap: nil)

        case .nostrEntity(let entity):
            renderNostrEntity(entity)

        case .mention(let pubkey):
            Mention(pubkey: pubkey, npub: pubkey, onTap: nil)

        case .hashtag(let tag):
            Hashtag(tag: tag, onTap: nil)
        }
    }

    private func inlineChildrenToText(_ children: [MarkdownInline]) -> String {
        children.map { inline in
            switch inline {
            case .text(let text): return text
            case .bold(let children): return inlineChildrenToText(children)
            case .italic(let children): return inlineChildrenToText(children)
            case .code(let code): return code
            case .link(let text, _): return text
            case .image(let alt, _): return alt
            case .nostrEntity(let entity): return entityToText(entity)
            case .mention(let pubkey): return "@\(String(pubkey.prefix(8)))..."
            case .hashtag(let tag): return "#\(tag)"
            }
        }.joined()
    }

    private func entityToText(_ entity: ContentEntity) -> String {
        switch entity {
        case .npub(let npub), .nprofile(let npub):
            return "@\(String(npub.prefix(16)))..."
        case .hashtag(let tag):
            return "#\(tag)"
        case .url(let url):
            return url.absoluteString
        case .note(let note):
            return "note:\(String(note.prefix(8)))..."
        case .nevent(let nevent):
            return "nevent:\(String(nevent.prefix(8)))..."
        case .naddr(let naddr):
            return "naddr:\(String(naddr.prefix(8)))..."
        case .text(let text):
            return text
        case .userMention(_, let npub):
            return "@\(String(npub.prefix(8)))..."
        case .eventMention(let eventId):
            return "event:\(String(eventId.prefix(8)))..."
        }
    }

    @ViewBuilder
    private func renderNostrEntity(_ entity: ContentEntity) -> some View {
        switch entity {
        case .npub(let npub), .nprofile(let npub):
            if let pubkey = try? Bech32.pubkey(from: npub) {
                Mention(pubkey: pubkey, npub: npub, onTap: nil)
            } else {
                Text("@\(String(npub.prefix(16)))...")
                    .foregroundColor(.accentColor)
            }

        case .hashtag(let tag):
            Hashtag(tag: tag, onTap: nil)

        case .url(let url):
            Link(url: url, onTap: nil)

        case .note(let note):
            EventPreviewLoader<Event>(reference: .note(note), onTap: nil)

        case .nevent(let nevent):
            EventPreviewLoader<Event>(reference: .nevent(nevent), onTap: nil)

        case .naddr(let naddr):
            EventPreviewLoader<Event>(reference: .naddr(naddr), onTap: nil)

        case .text(let text):
            Text(text)

        case .userMention(let pubkey, let npub):
            Mention(pubkey: pubkey, npub: npub, onTap: nil)

        case .eventMention(let eventId):
            EventPreviewLoader<Event>(reference: .eventId(eventId), onTap: nil)
        }
    }
}

// MARK: - Default Typealias

/// Convenience typealias for NDKUIMarkdownView with all default renderers
public typealias NDKMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

// MARK: - Preview

#if DEBUG
    struct NDKUIMarkdownView_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            ScrollView {
                VStack(spacing: 20) {
                    NDKMarkdown(
                        content: """
                        # Heading 1

                        This is a paragraph with **bold** and *italic* text.

                        ## Heading 2

                        - List item 1
                        - List item 2
                        - List item 3

                        ```swift
                        let code = "example"
                        ```

                        > This is a blockquote
                        """
                    )
                    .ndk(mockNDK)
                }
                .padding()
            }
        }
    }
#endif
