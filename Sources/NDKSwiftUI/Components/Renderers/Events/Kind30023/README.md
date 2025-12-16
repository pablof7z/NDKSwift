# Article Card Renderers (Kind:30023)

Long-form article preview cards for inline display when articles are referenced in other events.

## Overview

Article card renderers are specialized `EventRenderer` implementations that display **preview cards** for kind:30023 long-form content, not the full article. When an event contains an inline reference like `nostr:naddr1...`, these renderers extract metadata (title, summary, cover image) and display a tappable card.

## Available Renderers

### ArticleCardCompact
**Priority:** 5
**Use Case:** Feed and list views where space is limited

**Layout:**
```
┌─────────────────────────────┐
│ [80x80     Title (2 lines)  │
│  Image]    Summary (2)      │
│            Author • Time    │
└─────────────────────────────┘
```

**Features:**
- Small 80x80 thumbnail on left
- Title (2 lines, headline font)
- Summary (2 lines, secondary color)
- Author name and relative time

### ArticleCardHero
**Priority:** 10
**Use Case:** Featured content, detail views, hero sections

**Layout:**
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

**Features:**
- Large hero image (200px height, 16:9 aspect)
- Gradient overlay on image
- Prominent title (title2 font)
- Extended summary (3 lines)
- Author with profile picture
- Reading time estimate

### ArticleCardPortrait
**Priority:** 6
**Use Case:** Grid layouts, card-based UIs, vertical scrolling

**Layout:**
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

**Features:**
- Vertical/portrait layout
- Tall cover image (3:4 aspect)
- Fixed 240px width for grids
- Minimal metadata

## Usage

### In RichText Views

```swift
import NDKSwiftUI

// Define type alias with article card renderer
typealias ArticleRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    ArticleCardHero  // Use hero variant for articles
>

// Use in view
ArticleRichText(content: "Check out this article: nostr:naddr1...")
    .ndk(ndk)
    .onEventTap { event in
        // Handle article tap
    }
```

### In Markdown Views

```swift
typealias ArticleMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    ArticleCardCompact  // Use compact variant for markdown
>

ArticleMarkdown(content: markdownWithArticles)
    .ndk(ndk)
```

### Direct Usage

```swift
// Render a specific article
ArticleCardHero(event: articleEvent, onTap: { event in
    print("Tapped article: \(event.id)")
})
.environment(\.ndk, ndk)
```

## Metadata Extraction

All article card renderers extract metadata from NIP-23 tags:

| Tag | Method | Description |
|-----|--------|-------------|
| `title` | `extractTitle(from:)` | Article title |
| `summary` | `extractSummary(from:)` | Article summary/description |
| `image` | `extractImage(from:)` | Cover image URL |
| `published_at` | `extractPublishedAt(from:)` | Publication date |
| (content) | `estimateReadingTime(from:)` | Estimated reading time (200 WPM) |

### Example Event Tags

```json
{
  "kind": 30023,
  "tags": [
    ["title", "Understanding Nostr"],
    ["summary", "A deep dive into the Nostr protocol"],
    ["image", "https://example.com/cover.jpg"],
    ["published_at", "1703001600"]
  ],
  "content": "# Article Content Here..."
}
```

## Renderer Selection

The renderers have different priorities for progressive enhancement:

- **ArticleCardHero** (priority 10) - Most feature-rich
- **ArticleCardPortrait** (priority 6) - Vertical layouts
- **ArticleCardCompact** (priority 5) - Space-efficient

When multiple renderers are available, higher priority wins. In practice, you choose explicitly via type aliases.

## Customization

### Creating Custom Variants

Implement `ArticleCardRenderer` protocol:

```swift
import SwiftUI
import NDKSwiftCore

public struct ArticleCardCustom: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk

    // Metadata
    public static var supportedKinds: [Int] { [30023] }
    public static var variant: String { "custom" }
    public static var category: String { "article" }
    public static var priority: Int { 7 }

    public init(event: NDKEvent, onTap: EventTapHandler?) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        // Custom layout using protocol helpers:
        // - extractTitle(from:)
        // - extractSummary(from:)
        // - extractImage(from:)
        // - extractPublishedAt(from:)
        // - estimateReadingTime(from:)
    }
}
```

### Styling

Article cards use system colors and respect dark mode automatically:

- Background: `Color(.secondarySystemBackground)`
- Text: `.primary` (title), `.secondary` (metadata)
- Corner radius: 12pt (compact), 12pt (hero), 12pt (portrait)

## Best Practices

1. **Choose appropriate variant** based on context:
   - Lists/feeds → Compact
   - Featured content → Hero
   - Grids → Portrait

2. **Always provide tap handling** to navigate to full article

3. **Respect missing metadata** - All extraction methods return optional values

4. **Use NDK environment** - Article cards need NDK for author info:
   ```swift
   .environment(\.ndk, ndk)
   ```

5. **Handle loading states** - Images load asynchronously with placeholders

## See Also

- [EventRenderer Protocol](../Core/RendererProtocols.swift)
- [EventRendererMetadata](../Core/EventRendererMetadata.swift)
- [NIP-23: Long-form Content](https://github.com/nostr-protocol/nips/blob/master/23.md)
