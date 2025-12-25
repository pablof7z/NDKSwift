import NDKSwiftCore
import os.log
import SwiftUI

// MARK: - Generic Rich Text View

/// A generic rich text view that renders parsed Nostr content with pluggable renderers
public struct NDKUIRichTextView<
    Mention: MentionRenderer,
    Hashtag: HashtagRenderer,
    Link: LinkRenderer,
    Image: ImageRenderer,
    Event: EventRenderer
>: View {
    let content: String
    let tags: [Tag]
    let currentUserPubkey: PublicKey?

    @Environment(\.ndk) private var ndk
    @State private var parsedContent: NDKParsedContent?

    public init(
        content: String,
        tags: [Tag] = [],
        currentUserPubkey: PublicKey? = nil
    ) {
        self.content = content
        self.tags = tags
        self.currentUserPubkey = currentUserPubkey
    }

    public var body: some View {
        Group {
            if let parsed = parsedContent {
                renderGroupedComponents(parsed.components)
            } else {
                Text(content)
            }
        }
        .task(id: content) {
            await parseContent()
        }
    }

    private func parseContent() async {
        guard let ndk = ndk else {
            os_log(.debug, "NDKUIRichTextView: NDK not found in environment. Use .ndk(myNDK) modifier to enable content parsing.")
            return
        }
        let parsed = await ndk.parseContent(content, tags: tags, currentUserPubkey: currentUserPubkey)
        await MainActor.run {
            self.parsedContent = parsed
        }
    }

    // MARK: - Grouped Rendering

    private typealias GroupedItem = ImageGroupingUtils.GroupedResult<NDKParsedContent.Component>

    @ViewBuilder
    private func renderGroupedComponents(_ components: [NDKParsedContent.Component]) -> some View {
        let merged = mergeTextComponents(components)
        let grouped = ImageGroupingUtils.groupConsecutiveImages(
            merged,
            getImageURL: { component in
                if case .url(let url) = component, isImageURL(url) {
                    return url
                }
                return nil
            },
            isWhitespaceText: { component in
                if case .text(let text) = component {
                    // Treat text as "whitespace" if it only contains whitespace and punctuation
                    // This allows grouping images that might be separated by newlines and stray punctuation
                    let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if stripped.isEmpty { return true }
                    // Also treat as whitespace if only punctuation remains
                    let punctuationOnly = stripped.allSatisfy { $0.isPunctuation || $0.isWhitespace }
                    return punctuationOnly
                }
                return false
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { _, item in
                renderGroupedItem(item)
            }
        }
    }

    @ViewBuilder
    private func renderGroupedItem(_ item: GroupedItem) -> some View {
        switch item {
        case .single(let component):
            renderSingleComponent(component)
        case .imageGroup(let urls):
            Image(urls: urls, onTap: nil)
        }
    }

    @ViewBuilder
    private func renderSingleComponent(_ component: NDKParsedContent.Component) -> some View {
        switch component {
        case .text(let text):
            Text(text)

        case .userMention(let pubkey, let npub):
            Mention(pubkey: pubkey, npub: npub, onTap: nil)

        case .nprofileMention(let nprofile):
            if let decoded = try? ContentTagger.decodeNostrEntity(nprofile),
               let pubkey = decoded.pubkey {
                Mention(pubkey: pubkey, npub: nprofile, onTap: nil)
            } else {
                Text("@\(String(nprofile.prefix(16)))...")
                    .foregroundColor(.accentColor)
            }

        case .hashtag(let tag):
            Hashtag(tag: tag, onTap: nil)

        case .url(let url):
            // Non-image URLs are rendered as links
            // Image URLs are handled by groupConsecutiveImages
            Link(url: url, onTap: nil)

        case .eventMention(let eventId):
            EventPreviewLoader<Event>(reference: .eventId(eventId), onTap: nil)

        case .noteMention(let note):
            EventPreviewLoader<Event>(reference: .note(note), onTap: nil)

        case .neventMention(let nevent):
            EventPreviewLoader<Event>(reference: .nevent(nevent), onTap: nil)

        case .naddrMention(let naddr):
            EventPreviewLoader<Event>(reference: .naddr(naddr), onTap: nil)
        }
    }

    // MARK: - Component Helpers

    private func mergeTextComponents(_ components: [NDKParsedContent.Component]) -> [NDKParsedContent.Component] {
        var merged: [NDKParsedContent.Component] = []
        var currentText = ""

        for component in components {
            switch component {
            case .text(let text):
                currentText += text
            default:
                if !currentText.isEmpty {
                    merged.append(.text(currentText))
                    currentText = ""
                }
                merged.append(component)
            }
        }

        if !currentText.isEmpty {
            merged.append(.text(currentText))
        }

        return merged
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff"]
        let pathExtension = url.pathExtension.lowercased()

        if imageExtensions.contains(pathExtension) {
            return true
        }

        let urlString = url.absoluteString.lowercased()
        for ext in imageExtensions {
            if urlString.contains(".\(ext)?") || urlString.contains(".\(ext)&") || urlString.contains(".\(ext)#") {
                return true
            }
        }

        return false
    }
}

// MARK: - Default Typealias

/// Convenience typealias for NDKUIRichTextView with all default renderers
public typealias NDKRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? 10000
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            let finalWidth = min(size.width, maxWidth)
            let finalSize = CGSize(width: finalWidth, height: size.height)
            sizes.append(finalSize)

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += finalWidth + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: min(totalWidth, maxWidth), height: totalHeight), positions, sizes)
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIRichTextView_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                NDKRichText(
                    content: "Hello @npub1234... check out #bitcoin at https://example.com"
                )
                .ndk(mockNDK)

                NDKUIRichTextView<DefaultMentionView, DefaultHashtagView, DefaultLinkView, DefaultImageView, DefaultEventView>(
                    content: "Simple text with #nostr"
                )
                .ndk(mockNDK)
            }
            .padding()
        }
    }
#endif
