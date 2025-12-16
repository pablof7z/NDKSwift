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
                renderComponents(parsed.components)
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

    @ViewBuilder
    private func renderComponents(_ components: [NDKParsedContent.Component]) -> some View {
        let merged = mergeTextComponents(components)
        FlowLayout(alignment: .leading, spacing: 0) {
            ForEach(Array(merged.enumerated()), id: \.offset) { _, component in
                renderComponent(component)
            }
        }
    }

    @ViewBuilder
    private func renderComponent(_ component: NDKParsedContent.Component) -> some View {
        switch component {
        case .text(let text):
            Text(text)

        case .userMention(let pubkey, let npub):
            Mention(pubkey: pubkey, npub: npub, onTap: nil)

        case .nprofileMention(let nprofile):
            // Decode nprofile to extract pubkey
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
            if isImageURL(url) {
                Image(url: url, onTap: nil)
            } else {
                Link(url: url, onTap: nil)
            }

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
        // Use proposed width, or fallback to screen-like width when unconstrained.
        let maxWidth = proposal.width ?? 10000
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            // Measure with full maxWidth to get natural size
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))

            // If item doesn't fit on current line and we're not at start, wrap first
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            // Clamp width to maxWidth for oversized items
            let finalWidth = min(size.width, maxWidth)
            let finalSize = CGSize(width: finalWidth, height: size.height)
            sizes.append(finalSize)

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += finalWidth + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + lineHeight
        }

        // Constrain total width to maxWidth
        return (CGSize(width: min(totalWidth, maxWidth), height: totalHeight), positions, sizes)
    }
}

// MARK: - NDKUIEventPreview

/// A view for previewing event references using NDK directly
/// Alternative to EventPreviewLoader<DefaultEventView> when you have an NDK instance
public struct NDKUIEventPreview: View {
    let ndk: NDK
    let eventReference: EventReference

    @State private var event: NDKEvent?
    @State private var isLoading = true

    public enum EventReference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
    }

    public init(ndk: NDK, eventReference: EventReference) {
        self.ndk = ndk
        self.eventReference = eventReference
    }

    public var body: some View {
        Group {
            if let event = event {
                NDKUIEventView(ndk: ndk, event: event, style: .embedded, showInteractions: false)
            } else if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading event...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.ndkSecondaryBackground)
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Event not found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.ndkSecondaryBackground)
                .cornerRadius(8)
            }
        }
        .task {
            await loadEvent()
        }
    }

    private func loadEvent() async {
        guard let eventId = extractEventId() else {
            await MainActor.run {
                isLoading = false
            }
            return
        }

        let filter = NDKFilter(ids: [eventId])
        let dataSource = ndk.subscribe(filter: filter)

        for await event in dataSource.events {
            await MainActor.run {
                self.event = event
                self.isLoading = false
            }
            break // Only need first match
        }

        // If no event found after subscription completes
        await MainActor.run {
            if self.event == nil {
                self.isLoading = false
            }
        }
    }

    private func extractEventId() -> String? {
        switch eventReference {
        case .eventId(let id):
            return id
        case .note(let note):
            return try? Bech32.eventId(from: note)
        case .nevent(let nevent):
            // For nevent, decode the TLV to extract the event ID
            if let decoded = try? ContentTagger.decodeNostrEntity(nevent) {
                return decoded.eventId
            }
            return nil
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIRichTextView_Previews: PreviewProvider {
        static var previews: some View {
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                // Using default renderers via typealias
                NDKRichText(
                    content: "Hello @npub1234... check out #bitcoin at https://example.com"
                )
                .ndk(mockNDK)

                // Explicit generic parameters
                NDKUIRichTextView<DefaultMentionView, DefaultHashtagView, DefaultLinkView, DefaultImageView, DefaultEventView>(
                    content: "Simple text with #nostr"
                )
                .ndk(mockNDK)
            }
            .padding()
        }
    }
#endif
