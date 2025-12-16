# Pluggable Content Renderers Design

## Overview

A pluggable component system for NDKSwiftUI that allows library consumers to choose which SwiftUI views render different content types (mentions, hashtags, links, images, embedded events).

## Goals

1. **Different app styles** - Apps can have different visual styles (Twitter-like vs Reddit-like mention rendering)
2. **Built-in options** - Library ships multiple renderers, users pick their favorite
3. **Third-party extensions** - Developers can create custom renderers without modifying library code

## Design Principles

- **Performance first** - No AnyView, full type safety
- **Explicit configuration** - Users select renderers explicitly via generic type parameters
- **SwiftUI-native** - Uses protocols, environment, and standard patterns
- **Sensible defaults** - Works out of the box with zero configuration

---

## Architecture

### Renderer Protocols

Each content type has a protocol defining the required initializer:

```swift
// MARK: - Callback Types

typealias MentionTapHandler = (String) -> Void      // pubkey
typealias HashtagTapHandler = (String) -> Void      // tag
typealias LinkTapHandler = (URL) -> Void
typealias ImageTapHandler = (URL) -> Void
typealias EventTapHandler = (NDKEvent) -> Void

// MARK: - Renderer Protocols

protocol MentionRenderer: View {
    init(pubkey: String, npub: String, onTap: MentionTapHandler?)
}

protocol HashtagRenderer: View {
    init(tag: String, onTap: HashtagTapHandler?)
}

protocol LinkRenderer: View {
    init(url: URL, onTap: LinkTapHandler?)
}

protocol ImageRenderer: View {
    init(url: URL, onTap: ImageTapHandler?)
}

protocol EventRenderer: View {
    init(event: NDKEvent, onTap: EventTapHandler?)
}
```

**Key points:**
- Raw parsed data as parameters
- Optional direct callback for per-instance overrides
- Implementations get NDK from `@Environment(NDK.self)`
- Implementations can fall back to environment callbacks

### Environment Keys for Callbacks

```swift
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
    var onMentionTap: MentionTapHandler? {
        get { self[OnMentionTapKey.self] }
        set { self[OnMentionTapKey.self] = newValue }
    }

    var onHashtagTap: HashtagTapHandler? {
        get { self[OnHashtagTapKey.self] }
        set { self[OnHashtagTapKey.self] = newValue }
    }

    var onLinkTap: LinkTapHandler? {
        get { self[OnLinkTapKey.self] }
        set { self[OnLinkTapKey.self] = newValue }
    }

    var onImageTap: ImageTapHandler? {
        get { self[OnImageTapKey.self] }
        set { self[OnImageTapKey.self] = newValue }
    }

    var onEventTap: EventTapHandler? {
        get { self[OnEventTapKey.self] }
        set { self[OnEventTapKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    func onMentionTap(_ handler: @escaping MentionTapHandler) -> some View {
        environment(\.onMentionTap, handler)
    }

    func onHashtagTap(_ handler: @escaping HashtagTapHandler) -> some View {
        environment(\.onHashtagTap, handler)
    }

    func onLinkTap(_ handler: @escaping LinkTapHandler) -> some View {
        environment(\.onLinkTap, handler)
    }

    func onImageTap(_ handler: @escaping ImageTapHandler) -> some View {
        environment(\.onImageTap, handler)
    }

    func onEventTap(_ handler: @escaping EventTapHandler) -> some View {
        environment(\.onEventTap, handler)
    }
}
```

### Default Renderer Implementations

```swift
// MARK: - Default Mention Renderer

struct DefaultMentionView: MentionRenderer {
    let pubkey: String
    let npub: String
    let onTap: MentionTapHandler?

    @Environment(NDK.self) private var ndk
    @Environment(\.onMentionTap) private var envOnTap

    var body: some View {
        NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
            .foregroundColor(.accentColor)
            .onTapGesture {
                (onTap ?? envOnTap)?(pubkey)
            }
    }
}

// MARK: - Default Hashtag Renderer

struct DefaultHashtagView: HashtagRenderer {
    let tag: String
    let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    var body: some View {
        Text("#\(tag)")
            .foregroundColor(.accentColor)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}

// MARK: - Default Link Renderer

struct DefaultLinkView: LinkRenderer {
    let url: URL
    let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    var body: some View {
        Text(url.absoluteString)
            .foregroundColor(.accentColor)
            .underline()
            .onTapGesture {
                (onTap ?? envOnTap)?(url)
            }
    }
}

// MARK: - Default Image Renderer

struct DefaultImageView: ImageRenderer {
    let url: URL
    let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
        }
        .cornerRadius(8)
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}

// MARK: - Default Event Renderer

struct DefaultEventView: EventRenderer {
    let event: NDKEvent
    let onTap: EventTapHandler?

    @Environment(NDK.self) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    var body: some View {
        Group {
            switch event.kind {
            case 1:
                NoteCardView(event: event)
            case 30023:
                ArticleCardView(event: event)
            case 1111:
                ReplyCardView(event: event)
            default:
                FallbackEventCard(event: event)
            }
        }
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
```

### Generic Content View

```swift
// MARK: - Generic Rich Text View

struct NDKUIRichTextView<
    Mention: MentionRenderer,
    Hashtag: HashtagRenderer,
    Link: LinkRenderer,
    Image: ImageRenderer,
    Event: EventRenderer
>: View {
    let content: String
    let tags: [Tag]

    @Environment(NDK.self) private var ndk
    @State private var parsedContent: NDKParsedContent?

    init(content: String, tags: [Tag] = []) {
        self.content = content
        self.tags = tags
    }

    var body: some View {
        Group {
            if let parsed = parsedContent {
                renderComponents(parsed.components)
            } else {
                Text(content)
            }
        }
        .task {
            parsedContent = await ndk.parseContent(content, tags: tags)
        }
    }

    @ViewBuilder
    private func renderComponents(_ components: [NDKParsedContent.Component]) -> some View {
        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
            renderComponent(component)
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
            if let pubkey = decodeNprofile(nprofile) {
                Mention(pubkey: pubkey, npub: nprofile, onTap: nil)
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
            EventPreviewLoader(eventId: eventId) { event in
                Event(event: event, onTap: nil)
            }

        case .noteMention(let note):
            EventPreviewLoader(bech32: note) { event in
                Event(event: event, onTap: nil)
            }

        case .neventMention(let nevent):
            EventPreviewLoader(bech32: nevent) { event in
                Event(event: event, onTap: nil)
            }
        }
    }
}

// MARK: - Default Typealias

typealias NDKRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>
```

### Event Preview Loader

```swift
struct EventPreviewLoader<Content: View>: View {
    let eventId: String?
    let bech32: String?
    @ViewBuilder let content: (NDKEvent) -> Content

    @Environment(NDK.self) private var ndk
    @State private var event: NDKEvent?
    @State private var isLoading = true

    init(eventId: String, @ViewBuilder content: @escaping (NDKEvent) -> Content) {
        self.eventId = eventId
        self.bech32 = nil
        self.content = content
    }

    init(bech32: String, @ViewBuilder content: @escaping (NDKEvent) -> Content) {
        self.eventId = nil
        self.bech32 = bech32
        self.content = content
    }

    var body: some View {
        Group {
            if let event {
                content(event)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("Event not found")
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await loadEvent()
        }
    }

    private func loadEvent() async {
        // Resolve eventId from bech32 if needed, then fetch
    }
}
```

---

## Usage Examples

### Simple - Use Defaults

```swift
NDKRichText(content: post.content, tags: post.tags)
```

### App-Wide Callbacks

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(NDK.self, ndk)
                .onMentionTap { pubkey in router.push(.profile(pubkey)) }
                .onHashtagTap { tag in router.push(.hashtag(tag)) }
                .onLinkTap { url in UIApplication.shared.open(url) }
                .onEventTap { event in router.push(.event(event.id)) }
        }
    }
}
```

### Custom Renderers - Define Once

```swift
// App defines their own typealias once
typealias MyAppRichText = NDKUIRichTextView<
    BrandedMentionView,
    ChipHashtagView,
    PreviewLinkView,
    GalleryImageView,
    CustomEventView
>

// Use throughout app
MyAppRichText(content: post.content, tags: post.tags)
```

### Demo App - Runtime Switching

```swift
struct RendererDemoView: View {
    @State private var selectedStyle = RenderStyle.default

    var body: some View {
        VStack {
            Picker("Style", selection: $selectedStyle) {
                ForEach(RenderStyle.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }

            // Switch creates _ConditionalContent - fully optimized
            switch selectedStyle {
            case .default:
                NDKRichText(content: content, tags: tags)
            case .branded:
                MyAppRichText(content: content, tags: tags)
            case .minimal:
                MinimalRichText(content: content, tags: tags)
            }
        }
    }
}
```

---

## Summary

| Component | Description |
|-----------|-------------|
| **Protocols** | `MentionRenderer`, `HashtagRenderer`, `LinkRenderer`, `ImageRenderer`, `EventRenderer` |
| **Default Implementations** | `DefaultMentionView`, `DefaultHashtagView`, `DefaultLinkView`, `DefaultImageView`, `DefaultEventView` |
| **Plain-Text View** | `NDKUIRichTextView<M, H, L, I, E>` |
| **Markdown View** | `NDKUIMarkdownView<M, H, L, I, E>` |
| **Block Config** | `MarkdownBlockConfig` (headings, code blocks, blockquotes, lists) |
| **Convenience Typealiases** | `NDKRichText`, `NDKMarkdown` (all defaults) |
| **Callbacks** | Both direct (init param) and environment-based |
| **Performance** | Zero AnyView - full type safety |

---

## Comparison to Svelte Registry

| Aspect | Svelte Registry | NDKSwiftUI |
|--------|-----------------|------------|
| Configuration | Runtime registration | Compile-time generics |
| Type Safety | Loose (JavaScript) | Full (Swift protocols) |
| Performance | Good | Optimal (no type erasure) |
| Flexibility | High (runtime swap) | High (demo can switch via ViewBuilder) |
| Cascading Callbacks | Context-based | Environment-based |
| Defaults | Auto-register on import | Typealias |

---

## Markdown Support

Both plain-text and markdown views share the same inline renderer protocols. The only difference is markdown has additional block-level structure.

### Rendering Paths

```
Plain-text (kind:1 notes):
    ContentParser → NDKParsedContent.Component → Inline Renderers

Markdown (kind:30023 articles):
    MarkdownParser → MarkdownBlock → Block Config (styling)
                                   → MarkdownInline → Inline Renderers (shared)
```

### Markdown View

```swift
// MARK: - Generic Markdown View

struct NDKUIMarkdownView<
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

    init(
        content: String,
        tags: [Tag] = [],
        blockConfig: MarkdownBlockConfig = .default
    ) {
        self.content = content
        self.tags = tags
        self.blockConfig = blockConfig
    }

    var body: some View {
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
            CodeBlockView(language: language, code: code, config: blockConfig)

        case .blockquote(let inlines):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(blockConfig.blockquoteBorderColor)
                    .frame(width: 3)
                renderInlines(inlines)
                    .padding(.leading, 12)
            }

        case .list(let items, let ordered):
            ListBlockView(items: items, ordered: ordered, config: blockConfig) { inlines in
                renderInlines(inlines)
            }

        case .horizontalRule:
            Divider()
        }
    }

    @ViewBuilder
    private func renderInlines(_ inlines: [MarkdownInline]) -> some View {
        // Renders inline content using the same generic renderers
        // Mention, Hashtag, Link, Image, Event
    }
}

// MARK: - Default Typealias

typealias NDKMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>
```

### Block Configuration

```swift
// MARK: - Markdown Block Configuration

struct MarkdownBlockConfig {
    // Spacing
    var blockSpacing: CGFloat = 12
    var listItemSpacing: CGFloat = 4
    var listIndent: CGFloat = 20

    // Headings
    var headingColor: Color = .primary
    func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.bold()
        case 2: return .title.bold()
        case 3: return .title2.bold()
        case 4: return .title3.bold()
        case 5: return .headline
        default: return .subheadline.bold()
        }
    }

    // Code blocks
    var codeBackgroundColor: Color = Color(.systemGray6)
    var codeFont: Font = .system(.body, design: .monospaced)
    var codeCornerRadius: CGFloat = 8
    var codePadding: CGFloat = 12

    // Blockquotes
    var blockquoteBorderColor: Color = .accentColor
    var blockquoteTextColor: Color = .secondary

    // Presets
    static let `default` = MarkdownBlockConfig()

    static let minimal = MarkdownBlockConfig(
        blockSpacing: 8,
        codeBackgroundColor: .clear,
        codePadding: 0
    )

    static let compact = MarkdownBlockConfig(
        blockSpacing: 6,
        listItemSpacing: 2
    )
}
```

### Usage Examples

```swift
// Simple markdown - use defaults
NDKMarkdown(content: article.content, tags: article.tags)

// Custom block styling
NDKMarkdown(
    content: article.content,
    tags: article.tags,
    blockConfig: .compact
)

// Custom inline renderers + block config
typealias MyAppMarkdown = NDKUIMarkdownView<
    BrandedMentionView,
    ChipHashtagView,
    PreviewLinkView,
    GalleryImageView,
    CustomEventView
>

MyAppMarkdown(
    content: article.content,
    tags: article.tags,
    blockConfig: MarkdownBlockConfig(
        headingColor: .brand,
        codeBackgroundColor: .codeBackground
    )
)
```

### Shared Renderer Typealiases

```swift
// For apps that want consistent rendering across both formats:
typealias MyAppRenderers = (
    Mention: BrandedMentionView,
    Hashtag: ChipHashtagView,
    Link: PreviewLinkView,
    Image: GalleryImageView,
    Event: CustomEventView
)

// Then define both:
typealias MyRichText = NDKUIRichTextView<
    BrandedMentionView, ChipHashtagView, PreviewLinkView, GalleryImageView, CustomEventView
>

typealias MyMarkdown = NDKUIMarkdownView<
    BrandedMentionView, ChipHashtagView, PreviewLinkView, GalleryImageView, CustomEventView
>
```

---

## Files to Create/Modify

### Core Renderer Infrastructure

1. **New: `Sources/NDKSwiftUI/Components/Renderers/RendererProtocols.swift`**
   - Callback type aliases
   - Renderer protocols (MentionRenderer, HashtagRenderer, etc.)

2. **New: `Sources/NDKSwiftUI/Components/Renderers/RendererEnvironment.swift`**
   - Environment keys for callbacks
   - View modifiers (onMentionTap, onHashtagTap, etc.)

3. **New: `Sources/NDKSwiftUI/Components/Renderers/DefaultRenderers.swift`**
   - DefaultMentionView
   - DefaultHashtagView
   - DefaultLinkView
   - DefaultImageView
   - DefaultEventView

4. **New: `Sources/NDKSwiftUI/Components/Renderers/EventPreviewLoader.swift`**
   - EventPreviewLoader helper for async event loading

### Plain-Text View

5. **New/Replace: `Sources/NDKSwiftUI/Components/NDKUIRichTextView.swift`**
   - Generic NDKUIRichTextView<M, H, L, I, E>
   - NDKRichText typealias

### Markdown View

6. **New: `Sources/NDKSwiftUI/Components/Renderers/MarkdownBlockConfig.swift`**
   - MarkdownBlockConfig struct
   - Presets (default, minimal, compact)

7. **New/Replace: `Sources/NDKSwiftUI/Components/NDKUIMarkdownView.swift`**
   - Generic NDKUIMarkdownView<M, H, L, I, E>
   - NDKMarkdown typealias
   - Block rendering with config
   - Inline rendering using shared renderer protocols

### Demo App

8. **Update: `Examples/Apps/MarkdownDemo/`**
   - Showcase runtime switching between renderer styles
   - Demo both plain-text and markdown rendering
   - Show custom renderer implementations
