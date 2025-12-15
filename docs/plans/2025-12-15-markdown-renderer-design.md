# Markdown Renderer with Pluggable Components

**Date:** 2025-12-15
**Status:** Approved for implementation

## Overview

Rewrite `NDKUIMarkdownRenderer` to support pluggable component rendering for Nostr entities. When rendering markdown content, entities like mentions, hashtags, and event references can be rendered as custom SwiftUI components instead of styled text.

## Goals

1. **Pluggable**: Developers can swap rendering components for any entity type
2. **Performant**: Pre-parse markdown, avoid unnecessary re-renders
3. **Idiomatic**: Follow SwiftUI patterns (protocols, environment, modifiers)
4. **Consistent**: Match conceptual model of Svelte's ContentRenderer

## Architecture

### Parser: Apple's swift-markdown

Use Apple's `swift-markdown` library for parsing instead of our custom parser:
- Battle-tested CommonMark/GFM compliance
- Same parser used by MarkdownUI (3.5k stars)
- We focus on rendering, not parsing edge cases

### Renderer Protocols

Each entity type has a protocol defining how to render it:

```swift
public protocol MentionRenderer {
    associatedtype Body: View
    @ViewBuilder func body(ndk: NDK, pubkey: String) -> Body
}

public protocol HashtagRenderer {
    associatedtype Body: View
    @ViewBuilder func body(tag: String) -> Body
}

public protocol EventRenderer {
    associatedtype Body: View
    @ViewBuilder func body(ndk: NDK, eventId: String) -> Body
}

public protocol LinkRenderer {
    associatedtype Body: View
    @ViewBuilder func body(url: URL, text: String) -> Body
}

public protocol ImageRenderer {
    associatedtype Body: View
    @ViewBuilder func body(url: URL, altText: String?) -> Body
}
```

### Type-Erased Wrappers

For storage in the Theme object:

```swift
public struct AnyMentionRenderer: MentionRenderer {
    private let _body: (NDK, String) -> AnyView

    public init<R: MentionRenderer>(_ renderer: R) {
        _body = { ndk, pubkey in AnyView(renderer.body(ndk: ndk, pubkey: pubkey)) }
    }

    public func body(ndk: NDK, pubkey: String) -> some View {
        _body(ndk, pubkey)
    }
}
```

### Theme Object

Central configuration object holding all customizations:

```swift
public struct NDKMarkdownTheme {
    // Pluggable renderers (nil = use default text rendering)
    public var mention: AnyMentionRenderer?
    public var hashtag: AnyHashtagRenderer?
    public var event: AnyEventRenderer?
    public var link: AnyLinkRenderer?
    public var image: AnyImageRenderer?

    // Styling
    public var colors = NDKMarkdownColors()
    public var fonts = NDKMarkdownFonts()
    public var spacing = NDKMarkdownSpacing()

    // Tap handlers (for default text rendering)
    public var onMentionTap: ((String) -> Void)?
    public var onHashtagTap: ((String) -> Void)?
    public var onEventTap: ((String) -> Void)?
    public var onLinkTap: ((URL) -> Void)?

    public init() {}

    public static let `default` = NDKMarkdownTheme()
}
```

### Environment Integration

Pass theme through SwiftUI environment:

```swift
struct NDKMarkdownThemeKey: EnvironmentKey {
    static let defaultValue = NDKMarkdownTheme.default
}

extension EnvironmentValues {
    var ndkMarkdownTheme: NDKMarkdownTheme {
        get { self[NDKMarkdownThemeKey.self] }
        set { self[NDKMarkdownThemeKey.self] = newValue }
    }
}
```

### Main Renderer

```swift
public struct NDKUIMarkdownRenderer: View {
    let content: String
    let ndk: NDK

    @Environment(\.ndkMarkdownTheme) private var theme

    private let parsedDocument: Document  // From swift-markdown, parsed once

    public init(_ content: String, ndk: NDK) {
        self.content = content
        self.ndk = ndk
        self.parsedDocument = Document(parsing: content)
    }

    public var body: some View {
        // Walk AST, render blocks/inlines
        // Check theme for custom renderers
    }
}
```

### Modifier Convenience Methods

```swift
extension View {
    public func markdownTheme(_ theme: NDKMarkdownTheme) -> some View {
        environment(\.ndkMarkdownTheme, theme)
    }

    public func mentionRenderer<R: MentionRenderer>(_ renderer: R) -> some View {
        transformEnvironment(\.ndkMarkdownTheme) { theme in
            theme.mention = AnyMentionRenderer(renderer)
        }
    }
}
```

## Built-in Renderers

### Mentions
- `InlineMentionRenderer` - @username styled text (default)
- `CardMentionRenderer` - Profile card with avatar

### Hashtags
- `TextHashtagRenderer` - #tag styled text (default)
- `ChipHashtagRenderer` - Pill/chip style

### Events
- `ReferenceEventRenderer` - note1... link (default)
- `QuoteEventRenderer` - Embedded quote card

### Images
- `PlaceholderImageRenderer` - Emoji placeholder (default)
- `AsyncImageRenderer` - Actual async loaded image

## Demo App Usage

```swift
struct EntityRendererDemoView: View {
    @State private var mentionStyle = MentionStyleOption.card
    @State private var hashtagStyle = HashtagStyleOption.chip

    var theme: NDKMarkdownTheme {
        var theme = NDKMarkdownTheme()
        theme.mention = mentionStyle.renderer
        theme.hashtag = hashtagStyle.renderer
        return theme
    }

    var body: some View {
        NDKUIMarkdownRenderer(sampleContent, ndk: ndk)
            .markdownTheme(theme)
    }
}
```

## File Structure

```
Sources/NDKSwiftUI/
├── Markdown/
│   ├── NDKUIMarkdownRenderer.swift      # Main view
│   ├── NDKMarkdownTheme.swift           # Theme + colors/fonts/spacing
│   ├── Renderers/
│   │   ├── MentionRenderer.swift        # Protocol + AnyMentionRenderer
│   │   ├── HashtagRenderer.swift
│   │   ├── EventRenderer.swift
│   │   ├── LinkRenderer.swift
│   │   └── ImageRenderer.swift
│   ├── BuiltIn/
│   │   ├── InlineMentionRenderer.swift
│   │   ├── CardMentionRenderer.swift
│   │   ├── TextHashtagRenderer.swift
│   │   ├── ChipHashtagRenderer.swift
│   │   └── ...
│   └── Internal/
│       ├── MarkdownWalker.swift         # AST traversal
│       └── NostrEntityParser.swift      # Extract entities from text
```

## Dependencies

Add to Package.swift:
```swift
.package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0")
```

## Migration

The existing `NDKUIMarkdownRenderer` will be replaced. The new API is:
- Same initializer: `NDKUIMarkdownRenderer(content, ndk: ndk)`
- New theme system replaces `MarkdownConfiguration`
- New renderer protocols replace hardcoded rendering

## References

- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) - Design inspiration
- [swift-markdown](https://github.com/swiftlang/swift-markdown) - Apple's parser
- [Svelte ContentRenderer](../svelte/registry) - Conceptual model
