# Pluggable Content Renderers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a pluggable component system where library consumers can choose which SwiftUI views render mentions, hashtags, links, images, and embedded events.

**Architecture:** Protocol-based generics with zero AnyView. Shared inline renderers between plain-text (NDKUIRichTextView) and markdown (NDKUIMarkdownView). Environment-based callbacks cascade through view hierarchy.

**Tech Stack:** Swift 6, SwiftUI, NDKSwiftCore

---

## Task 1: Renderer Protocols

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/RendererProtocols.swift`

**Step 1: Create the file with callback types and protocols**

```swift
import SwiftUI
import NDKSwiftCore

// MARK: - Callback Types

public typealias MentionTapHandler = (String) -> Void
public typealias HashtagTapHandler = (String) -> Void
public typealias LinkTapHandler = (URL) -> Void
public typealias ImageTapHandler = (URL) -> Void
public typealias EventTapHandler = (NDKEvent) -> Void

// MARK: - Renderer Protocols

public protocol MentionRenderer: View {
    init(pubkey: String, npub: String, onTap: MentionTapHandler?)
}

public protocol HashtagRenderer: View {
    init(tag: String, onTap: HashtagTapHandler?)
}

public protocol LinkRenderer: View {
    init(url: URL, onTap: LinkTapHandler?)
}

public protocol ImageRenderer: View {
    init(url: URL, onTap: ImageTapHandler?)
}

public protocol EventRenderer: View {
    init(event: NDKEvent, onTap: EventTapHandler?)
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds or shows only unrelated warnings

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/RendererProtocols.swift
git commit -m "feat(renderers): add renderer protocols and callback types"
```

---

## Task 2: Environment Keys for Callbacks

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/RendererEnvironment.swift`

**Step 1: Create environment keys and view modifiers**

```swift
import SwiftUI
import NDKSwiftCore

// MARK: - Environment Keys

private struct OnMentionTapKey: EnvironmentKey {
    static let defaultValue: MentionTapHandler? = nil
}

private struct OnHashtagTapKey: EnvironmentKey {
    static let defaultValue: HashtagTapHandler? = nil
}

private struct OnLinkTapKey: EnvironmentKey {
    static let defaultValue: LinkTapHandler? = nil
}

private struct OnImageTapKey: EnvironmentKey {
    static let defaultValue: ImageTapHandler? = nil
}

private struct OnEventTapKey: EnvironmentKey {
    static let defaultValue: EventTapHandler? = nil
}

// MARK: - EnvironmentValues Extension

extension EnvironmentValues {
    public var onMentionTap: MentionTapHandler? {
        get { self[OnMentionTapKey.self] }
        set { self[OnMentionTapKey.self] = newValue }
    }

    public var onHashtagTap: HashtagTapHandler? {
        get { self[OnHashtagTapKey.self] }
        set { self[OnHashtagTapKey.self] = newValue }
    }

    public var onLinkTap: LinkTapHandler? {
        get { self[OnLinkTapKey.self] }
        set { self[OnLinkTapKey.self] = newValue }
    }

    public var onImageTap: ImageTapHandler? {
        get { self[OnImageTapKey.self] }
        set { self[OnImageTapKey.self] = newValue }
    }

    public var onEventTap: EventTapHandler? {
        get { self[OnEventTapKey.self] }
        set { self[OnEventTapKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    public func onMentionTap(_ handler: @escaping MentionTapHandler) -> some View {
        environment(\.onMentionTap, handler)
    }

    public func onHashtagTap(_ handler: @escaping HashtagTapHandler) -> some View {
        environment(\.onHashtagTap, handler)
    }

    public func onLinkTap(_ handler: @escaping LinkTapHandler) -> some View {
        environment(\.onLinkTap, handler)
    }

    public func onImageTap(_ handler: @escaping ImageTapHandler) -> some View {
        environment(\.onImageTap, handler)
    }

    public func onEventTap(_ handler: @escaping EventTapHandler) -> some View {
        environment(\.onEventTap, handler)
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/RendererEnvironment.swift
git commit -m "feat(renderers): add environment keys and view modifiers for callbacks"
```

---

## Task 3: Default Mention Renderer

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/DefaultMentionView.swift`

**Step 1: Create default mention renderer**

```swift
import SwiftUI
import NDKSwiftCore

public struct DefaultMentionView: MentionRenderer {
    public let pubkey: String
    public let npub: String
    public let onTap: MentionTapHandler?

    @Environment(NDK.self) private var ndk
    @Environment(\.onMentionTap) private var envOnTap

    public init(pubkey: String, npub: String, onTap: MentionTapHandler? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.onTap = onTap
    }

    public var body: some View {
        NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
            .foregroundColor(.accentColor)
            .onTapGesture {
                (onTap ?? envOnTap)?(pubkey)
            }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/DefaultMentionView.swift
git commit -m "feat(renderers): add DefaultMentionView"
```

---

## Task 4: Default Hashtag Renderer

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/DefaultHashtagView.swift`

**Step 1: Create default hashtag renderer**

```swift
import SwiftUI

public struct DefaultHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .foregroundColor(.accentColor)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/DefaultHashtagView.swift
git commit -m "feat(renderers): add DefaultHashtagView"
```

---

## Task 5: Default Link Renderer

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/DefaultLinkView.swift`

**Step 1: Create default link renderer**

```swift
import SwiftUI

public struct DefaultLinkView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        Text(url.absoluteString)
            .foregroundColor(.accentColor)
            .underline()
            .onTapGesture {
                (onTap ?? envOnTap)?(url)
            }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/DefaultLinkView.swift
git commit -m "feat(renderers): add DefaultLinkView"
```

---

## Task 6: Default Image Renderer

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/DefaultImageView.swift`

**Step 1: Create default image renderer**

```swift
import SwiftUI

public struct DefaultImageView: ImageRenderer {
    public let url: URL
    public let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap

    public init(url: URL, onTap: ImageTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure:
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            @unknown default:
                EmptyView()
            }
        }
        .cornerRadius(8)
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/DefaultImageView.swift
git commit -m "feat(renderers): add DefaultImageView"
```

---

## Task 7: Default Event Renderer

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/DefaultEventView.swift`

**Step 1: Create default event renderer**

```swift
import SwiftUI
import NDKSwiftCore

public struct DefaultEventView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(NDK.self) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        NDKUIEventView(ndk: ndk, event: event, style: .embedded, showInteractions: false)
            .onTapGesture {
                (onTap ?? envOnTap)?(event)
            }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/DefaultEventView.swift
git commit -m "feat(renderers): add DefaultEventView"
```

---

## Task 8: Event Preview Loader

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/EventPreviewLoader.swift`

**Step 1: Create event preview loader helper**

```swift
import SwiftUI
import NDKSwiftCore

public struct EventPreviewLoader<Event: EventRenderer>: View {
    public enum Reference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
    }

    let reference: Reference
    let onTap: EventTapHandler?

    @Environment(NDK.self) private var ndk
    @State private var event: NDKEvent?
    @State private var isLoading = true

    public init(reference: Reference, onTap: EventTapHandler? = nil) {
        self.reference = reference
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let event {
                Event(event: event, onTap: onTap)
            } else if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading event...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
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
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .task {
            await loadEvent()
        }
    }

    private func loadEvent() async {
        guard let eventId = extractEventId() else {
            await MainActor.run { isLoading = false }
            return
        }

        let filter = NDKFilter(ids: [eventId])
        let dataSource = ndk.subscribe(filter: filter)

        for await fetchedEvent in dataSource.events {
            await MainActor.run {
                self.event = fetchedEvent
                self.isLoading = false
            }
            break
        }

        await MainActor.run {
            if self.event == nil {
                self.isLoading = false
            }
        }
    }

    private func extractEventId() -> String? {
        switch reference {
        case .eventId(let id):
            return id
        case .note(let note):
            return try? Bech32.eventId(from: note)
        case .nevent(let nevent):
            if let decoded = try? ContentTagger.decodeNostrEntity(nevent) {
                return decoded.eventId
            }
            return nil
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/EventPreviewLoader.swift
git commit -m "feat(renderers): add EventPreviewLoader helper"
```

---

## Task 9: Generic NDKUIRichTextView

**Files:**
- Modify: `Sources/NDKSwiftUI/Components/NDKUIRichTextView.swift`

**Step 1: Replace with generic implementation**

```swift
import NDKSwiftCore
import SwiftUI

// MARK: - Generic Rich Text View

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
    let showLinkPreviews: Bool

    @Environment(NDK.self) private var ndk
    @State private var parsedContent: NDKParsedContent?

    public init(
        content: String,
        tags: [Tag] = [],
        currentUserPubkey: PublicKey? = nil,
        showLinkPreviews: Bool = true
    ) {
        self.content = content
        self.tags = tags
        self.currentUserPubkey = currentUserPubkey
        self.showLinkPreviews = showLinkPreviews
    }

    public var body: some View {
        Group {
            if let parsed = parsedContent {
                VStack(alignment: .leading, spacing: 8) {
                    renderComponents(parsed.components)

                    if showLinkPreviews {
                        renderImagePreviews(from: parsed.components)
                        renderEventPreviews(from: parsed.components)
                    }
                }
            } else {
                Text(content)
                    .task {
                        await parseContent()
                    }
            }
        }
    }

    private func parseContent() async {
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
                if !showLinkPreviews {
                    Link(url: url, onTap: nil)
                }
                // Images rendered separately in preview section
            } else {
                Link(url: url, onTap: nil)
            }

        case .eventMention, .noteMention, .neventMention:
            // Event mentions rendered separately in preview section
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderImagePreviews(from components: [NDKParsedContent.Component]) -> some View {
        let imageURLs = components.compactMap { component -> URL? in
            if case .url(let url) = component, isImageURL(url) {
                return url
            }
            return nil
        }

        ForEach(Array(imageURLs.prefix(3).enumerated()), id: \.offset) { _, url in
            Image(url: url, onTap: nil)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func renderEventPreviews(from components: [NDKParsedContent.Component]) -> some View {
        let references = extractEventReferences(from: components)

        ForEach(Array(references.prefix(2).enumerated()), id: \.offset) { _, reference in
            EventPreviewLoader<Event>(reference: reference, onTap: nil)
                .padding(.top, 4)
        }
    }

    private func extractEventReferences(from components: [NDKParsedContent.Component]) -> [EventPreviewLoader<Event>.Reference] {
        components.compactMap { component -> EventPreviewLoader<Event>.Reference? in
            switch component {
            case .eventMention(let eventId):
                return .eventId(eventId)
            case .noteMention(let note):
                return .note(note)
            case .neventMention(let nevent):
                return .nevent(nevent)
            default:
                return nil
            }
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
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions, sizes)
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -30`
Expected: Build succeeds (may have warnings about unused old code)

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/NDKUIRichTextView.swift
git commit -m "feat(renderers): convert NDKUIRichTextView to generic with pluggable renderers"
```

---

## Task 10: Markdown Block Configuration

**Files:**
- Create: `Sources/NDKSwiftUI/Components/Renderers/MarkdownBlockConfig.swift`

**Step 1: Create block configuration struct**

```swift
import SwiftUI

public struct MarkdownBlockConfig {
    // Spacing
    public var blockSpacing: CGFloat
    public var listItemSpacing: CGFloat
    public var listIndent: CGFloat

    // Headings
    public var headingColor: Color
    public var headingFonts: [Int: Font]

    // Code blocks
    public var codeBackgroundColor: Color
    public var codeFont: Font
    public var codeCornerRadius: CGFloat
    public var codePadding: CGFloat

    // Blockquotes
    public var blockquoteBorderColor: Color
    public var blockquoteTextColor: Color

    public init(
        blockSpacing: CGFloat = 12,
        listItemSpacing: CGFloat = 4,
        listIndent: CGFloat = 20,
        headingColor: Color = .primary,
        headingFonts: [Int: Font] = [
            1: .largeTitle.bold(),
            2: .title.bold(),
            3: .title2.bold(),
            4: .title3.bold(),
            5: .headline,
            6: .subheadline.bold()
        ],
        codeBackgroundColor: Color = Color(.systemGray6),
        codeFont: Font = .system(.body, design: .monospaced),
        codeCornerRadius: CGFloat = 8,
        codePadding: CGFloat = 12,
        blockquoteBorderColor: Color = .accentColor,
        blockquoteTextColor: Color = .secondary
    ) {
        self.blockSpacing = blockSpacing
        self.listItemSpacing = listItemSpacing
        self.listIndent = listIndent
        self.headingColor = headingColor
        self.headingFonts = headingFonts
        self.codeBackgroundColor = codeBackgroundColor
        self.codeFont = codeFont
        self.codeCornerRadius = codeCornerRadius
        self.codePadding = codePadding
        self.blockquoteBorderColor = blockquoteBorderColor
        self.blockquoteTextColor = blockquoteTextColor
    }

    public func headingFont(for level: Int) -> Font {
        headingFonts[level] ?? .body
    }

    // MARK: - Presets

    public static let `default` = MarkdownBlockConfig()

    public static let minimal = MarkdownBlockConfig(
        blockSpacing: 8,
        codeBackgroundColor: .clear,
        codePadding: 0
    )

    public static let compact = MarkdownBlockConfig(
        blockSpacing: 6,
        listItemSpacing: 2
    )
}
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/Renderers/MarkdownBlockConfig.swift
git commit -m "feat(renderers): add MarkdownBlockConfig for block-level styling"
```

---

## Task 11: Generic NDKUIMarkdownView

**Files:**
- Create: `Sources/NDKSwiftUI/Components/NDKUIMarkdownView.swift`

**Step 1: Create generic markdown view**

```swift
import SwiftUI
import NDKSwiftCore

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

    @Environment(NDK.self) private var ndk
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
        .task {
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

    @ViewBuilder
    private func renderInlines(_ inlines: [MarkdownInline]) -> some View {
        FlowLayout(alignment: .leading, spacing: 0) {
            ForEach(Array(inlines.enumerated()), id: \.offset) { _, inline in
                renderInline(inline)
            }
        }
    }

    @ViewBuilder
    private func renderInline(_ inline: MarkdownInline) -> some View {
        switch inline {
        case .text(let text):
            Text(text)

        case .bold(let children):
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                renderInline(child)
                    .bold()
            }

        case .italic(let children):
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                renderInline(child)
                    .italic()
            }

        case .code(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .background(blockConfig.codeBackgroundColor)
                .cornerRadius(4)

        case .link(let text, let url):
            Link(url: url, onTap: nil)

        case .image(_, let url):
            Image(url: url, onTap: nil)

        case .nostrEntity(let entity):
            renderNostrEntity(entity)

        case .mention(let pubkey):
            Mention(pubkey: pubkey, npub: pubkey, onTap: nil)

        case .hashtag(let tag):
            Hashtag(tag: tag, onTap: nil)
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
            Text("naddr:\(String(naddr.prefix(16)))...")
                .foregroundColor(.accentColor)

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

public typealias NDKMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>
```

**Step 2: Verify it compiles**

Run: `swift build --target NDKSwiftUI 2>&1 | head -30`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/Components/NDKUIMarkdownView.swift
git commit -m "feat(renderers): add generic NDKUIMarkdownView with shared inline renderers"
```

---

## Task 12: Export Renderers in Module

**Files:**
- Modify: `Sources/NDKSwiftUI/NDKSwiftUI.swift`

**Step 1: Add exports for renderer types**

Add the following exports to the module file:

```swift
// MARK: - Renderers
@_exported import struct NDKSwiftUI.DefaultMentionView
@_exported import struct NDKSwiftUI.DefaultHashtagView
@_exported import struct NDKSwiftUI.DefaultLinkView
@_exported import struct NDKSwiftUI.DefaultImageView
@_exported import struct NDKSwiftUI.DefaultEventView
@_exported import struct NDKSwiftUI.MarkdownBlockConfig
@_exported import struct NDKSwiftUI.EventPreviewLoader
```

Or simply ensure the files are public and part of the module.

**Step 2: Verify full build**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/NDKSwiftUI/NDKSwiftUI.swift
git commit -m "feat(renderers): export renderer types from module"
```

---

## Task 13: Final Build and Test

**Step 1: Run full build**

Run: `swift build 2>&1`
Expected: Build succeeds with no errors

**Step 2: Run tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass

**Step 3: Create summary commit**

```bash
git log --oneline -10
```

---

## Summary

| Task | Component | File |
|------|-----------|------|
| 1 | Renderer Protocols | `Renderers/RendererProtocols.swift` |
| 2 | Environment Keys | `Renderers/RendererEnvironment.swift` |
| 3 | Default Mention | `Renderers/DefaultMentionView.swift` |
| 4 | Default Hashtag | `Renderers/DefaultHashtagView.swift` |
| 5 | Default Link | `Renderers/DefaultLinkView.swift` |
| 6 | Default Image | `Renderers/DefaultImageView.swift` |
| 7 | Default Event | `Renderers/DefaultEventView.swift` |
| 8 | Event Loader | `Renderers/EventPreviewLoader.swift` |
| 9 | Rich Text View | `NDKUIRichTextView.swift` |
| 10 | Block Config | `Renderers/MarkdownBlockConfig.swift` |
| 11 | Markdown View | `NDKUIMarkdownView.swift` |
| 12 | Module Exports | `NDKSwiftUI.swift` |
| 13 | Final Build | - |
