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
| **Generic View** | `NDKUIRichTextView<M, H, L, I, E>` |
| **Convenience Typealias** | `NDKRichText` (all defaults) |
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

## Files to Create/Modify

1. **New: `Sources/NDKSwiftUI/Components/Renderers/RendererProtocols.swift`**
   - Callback type aliases
   - Renderer protocols

2. **New: `Sources/NDKSwiftUI/Components/Renderers/RendererEnvironment.swift`**
   - Environment keys
   - View modifiers

3. **New: `Sources/NDKSwiftUI/Components/Renderers/DefaultRenderers.swift`**
   - DefaultMentionView
   - DefaultHashtagView
   - DefaultLinkView
   - DefaultImageView
   - DefaultEventView

4. **New: `Sources/NDKSwiftUI/Components/Renderers/EventPreviewLoader.swift`**
   - EventPreviewLoader helper

5. **New/Replace: `Sources/NDKSwiftUI/Components/NDKUIRichTextView.swift`**
   - Generic NDKUIRichTextView
   - NDKRichText typealias

6. **Update: Demo app**
   - Showcase runtime switching between renderer styles
