# Article Card Renderers (Kind:30023)

Long-form article preview cards for inline display when articles are referenced in other events.

## Overview

Article card renderers are specialized `EventRenderer` implementations that display **preview cards** for kind:30023 long-form content, not the full article. When an event contains an inline reference like `nostr:naddr1...`, these renderers extract metadata (title, summary, cover image) and display a tappable card.

## Available Renderers

### ArticleCardCompact
**Use Case:** Feed and list views where space is limited

```
┌─────────────────────────────┐
│ [80x80     Title (2 lines)  │
│  Image]    Summary (2)      │
│            Author • Time    │
└─────────────────────────────┘
```

### ArticleCardHero
**Use Case:** Featured content, detail views, hero sections

```
┌─────────────────────────────┐
│                             │
│    Full-width Hero Image    │
│         (16:9 ratio)        │
│                             │
├─────────────────────────────┤
│ Title (2 lines, larger)     │
│ Summary (3 lines)           │
│ Author • Time • Read Time   │
└─────────────────────────────┘
```

### ArticleCardPortrait
**Use Case:** Grid layouts, card-based UIs, vertical scrolling

```
┌─────────────────┐
│                 │
│   Cover Image   │
│   (3:4 ratio)   │
│    240x320      │
│                 │
├─────────────────┤
│ Title (3 lines) │
│ Author          │
│ Time            │
└─────────────────┘
```

## Usage

### Custom EventRenderer with Kind Dispatch

Apps should create their own `EventRenderer` with compile-time kind dispatch:

```swift
struct AppEventRenderer: EventRenderer {
    let event: NDKEvent
    let onTap: EventTapHandler?

    @ViewBuilder
    var body: some View {
        switch event.kind {
        case 30023, 30024:
            ArticleCardCompact(event: event, onTap: onTap)
        case 39089:
            FollowPackCard(event: event, onTap: onTap)
        default:
            DefaultEventView(event: event, onTap: onTap)
        }
    }
}

// Use with RichText
typealias AppRichText = NDKUIRichTextView<
    AppMentionView,
    AppHashtagView,
    AppLinkView,
    AppImageView,
    AppEventRenderer
>
```

### Direct Usage

```swift
ArticleCardHero(event: articleEvent, onTap: { event in
    print("Tapped article: \(event.id)")
})
.environment(\.ndk, ndk)
```

## Metadata Extraction

All article cards have access to an `article` helper that wraps the event as `NDKArticle`:

```swift
// Inside ArticleCardRenderer implementations
let title = article.title
let summary = article.summary
let imageURL = article.imageURL
let readingTime = article.readingTime
```

## Creating Custom Variants

Implement `ArticleCardRenderer` protocol:

```swift
public struct ArticleCardCustom: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk

    public init(event: NDKEvent, onTap: EventTapHandler?) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        // Use the `article` helper from the protocol
        VStack {
            if let title = article.title {
                Text(title)
            }
            // ...
        }
    }
}
```

## See Also

- [EventRenderer Protocol](../Core/RendererProtocols.swift)
- [NIP-23: Long-form Content](https://github.com/nostr-protocol/nips/blob/master/23.md)
