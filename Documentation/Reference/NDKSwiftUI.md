# NDKSwiftUI Reference

Complete API documentation for NDKSwiftUI components and features.

## Table of Contents

- [Overview](#overview)
- [Environment Setup](#environment-setup)
- [Core Components](#core-components)
  - [NDKProfilePicture](#ndkprofilepicture)
  - [NDKDisplayName](#ndkdisplayname)
  - [NDKEventView](#ndkeventview)
  - [NDKRichText](#ndkrichtext)
  - [NDKMarkdownRenderer](#ndkmarkdownrenderer)
  - [NDKRelativeTime](#ndkrelativetime)
- [Interactive Components](#interactive-components)
  - [NDKFollowButton](#ndkfollowbutton)
  - [NDKReactionButton](#ndkreactionbutton)
  - [NDKZapButton](#ndkzapbutton)
- [Data Sources](#data-sources)
  - [NDKProfileDataSource](#ndkprofiledatasource)
  - [NDKEventDataSource](#ndkeventdatasource)
  - [NDKContactsDataSource](#ndkcontactsdatasource)
- [Utilities](#utilities)

## Overview

NDKSwiftUI provides a comprehensive set of SwiftUI components for building Nostr applications. It follows a composable, data-driven architecture that integrates seamlessly with NDKSwift's core functionality.

### Key Principles

1. **Composable** - Small, focused components that can be combined
2. **Reactive** - Automatically updates when underlying data changes
3. **Customizable** - Extensive styling and configuration options
4. **Progressive Disclosure** - Simple defaults with advanced customization available

## Environment Setup

NDKSwiftUI components expect an NDK instance to be available in the SwiftUI environment:

```swift
import NDKSwift
import NDKSwiftUI

@main
struct MyApp: App {
    @StateObject private var ndk = NDK()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ndk)
        }
    }
}
```

## Core Components

### NDKProfilePicture

Displays a user's profile picture with automatic loading and caching.

```swift
NDKProfilePicture(pubkey: userPubkey)
    .size(50)
    .rounded()
```

#### Modifiers

- `.size(_ size: CGFloat)` - Set the size (default: 40)
- `.rounded()` - Apply circular clipping
- `.bordered(color: Color, width: CGFloat)` - Add border
- `.fallbackImage(_ image: Image)` - Custom fallback image

### NDKDisplayName

Shows a user's display name with automatic profile fetching.

```swift
NDKDisplayName(pubkey: userPubkey)
    .font(.headline)
    .foregroundColor(.primary)
```

#### Features

- Automatically fetches profile metadata
- Falls back to shortened pubkey if no name available
- Supports custom formatting

### NDKEventView

A complete event display component with author info, content, and interactions.

```swift
NDKEventView(event: ndkEvent)
    .padding()
```

#### Customization

```swift
NDKEventView(event: ndkEvent)
    .showAuthor(true)
    .showTimestamp(true)
    .showInteractions(true)
    .contentRenderer { content in
        // Custom content rendering
    }
```

### NDKRichText

Renders text content with clickable links, mentions, and hashtags.

```swift
NDKRichText(event.content)
    .onLinkTap { url in
        // Handle link tap
    }
    .onMentionTap { pubkey in
        // Handle mention tap
    }
    .onHashtagTap { tag in
        // Handle hashtag tap
    }
```

### NDKMarkdownRenderer

A comprehensive markdown renderer with full Nostr entity support.

```swift
NDKMarkdownRenderer(content, ndk: ndk)
    .markdownStyle(.nostr)
    .onMentionTap { pubkey in
        // Handle @mention tap
    }
    .onHashtagTap { tag in
        // Handle #hashtag tap
    }
    .onNostrEntityTap { entity in
        // Handle nostr: entity tap
    }
```

#### Features

- **Complete Markdown Support**
  - Headings (H1-H6)
  - Bold and italic text
  - Code blocks with syntax highlighting
  - Inline code
  - Blockquotes
  - Ordered and unordered lists
  - Horizontal rules
  - Links and images

- **Nostr Entity Parsing**
  - npub/nprofile mentions
  - note/nevent references
  - naddr references
  - Hashtags
  - @mentions

- **Styling Options**

```swift
// Predefined styles
NDKMarkdownRenderer(content, ndk: ndk)
    .markdownStyle(.minimal)    // Clean, minimal styling
    .markdownStyle(.dark)       // Dark mode optimized
    .markdownStyle(.nostr)      // Nostr-themed styling
    .markdownStyle(.compact)    // Reduced spacing

// Custom configuration
var customStyle = MarkdownConfiguration()
customStyle.headingColor = .purple
customStyle.linkColor = .green
customStyle.codeBackgroundColor = .yellow.opacity(0.1)

NDKMarkdownRenderer(content, ndk: ndk)
    .markdownStyle(customStyle)
```

- **Image Rendering**

```swift
// Enable inline image rendering
NDKMarkdownRenderer(content, ndk: ndk)
    .renderImages()
    .onImageTap { url in
        // Handle image tap
    }
```

- **Preview Mode**

```swift
// Show truncated preview with "Show More" button
NDKMarkdownPreview(content, ndk: ndk, previewLines: 5)
    .markdownStyle(.minimal)
```

#### Markdown Configuration Properties

```swift
public struct MarkdownConfiguration {
    // Colors
    var textColor: Color
    var headingColor: Color
    var linkColor: Color
    var codeColor: Color
    var codeBackgroundColor: Color
    var mentionColor: Color
    var hashtagColor: Color
    var nostrEntityColor: Color
    
    // Fonts
    var bodyFont: Font
    var h1Font through h6Font: Font
    var codeFont: Font
    var blockquoteFont: Font
    
    // Spacing
    var paragraphSpacing: CGFloat
    var headingSpacing: CGFloat
    var listItemSpacing: CGFloat
    
    // Dimensions
    var codeBlockPadding: CGFloat
    var codeBlockCornerRadius: CGFloat
    var contentPadding: EdgeInsets
}
```

### NDKRelativeTime

Displays timestamps in relative format (e.g., "5 minutes ago").

```swift
NDKRelativeTime(date: event.createdAt)
    .font(.caption)
    .foregroundColor(.secondary)
```

## Interactive Components

### NDKFollowButton

A button that handles follow/unfollow actions.

```swift
NDKFollowButton(pubkey: userPubkey)
    .buttonStyle(.borderedProminent)
```

#### States

- Shows "Follow" or "Following" based on current state
- Automatically updates when follow list changes
- Handles loading and error states

### NDKReactionButton

Handles event reactions (likes).

```swift
NDKReactionButton(event: ndkEvent)
    .reactionContent("+")  // Custom reaction content
```

### NDKZapButton

Enables Lightning zaps on events.

```swift
NDKZapButton(event: ndkEvent)
    .defaultAmount(1000)  // Default zap amount in sats
    .onZap { success in
        // Handle zap completion
    }
```

## Data Sources

### NDKProfileDataSource

Observable data source for user profiles.

```swift
@StateObject private var profileData = NDKProfileDataSource(
    pubkey: userPubkey,
    ndk: ndk
)

var body: some View {
    if let profile = profileData.profile {
        Text(profile.name ?? "Unknown")
    }
}
```

### NDKEventDataSource

Observable data source for events.

```swift
@StateObject private var eventData = NDKEventDataSource(
    filter: NDKFilter(authors: [pubkey], kinds: [.text]),
    ndk: ndk
)

var body: some View {
    List(eventData.events) { event in
        NDKEventView(event: event)
    }
}
```

### NDKContactsDataSource

Observable data source for contact lists.

```swift
@StateObject private var contacts = NDKContactsDataSource(
    pubkey: userPubkey,
    ndk: ndk
)

var body: some View {
    List(contacts.following) { contact in
        HStack {
            NDKProfilePicture(pubkey: contact.pubkey)
            NDKDisplayName(pubkey: contact.pubkey)
        }
    }
}
```

## Utilities

### Environment Values

```swift
// Access NDK instance from environment
@Environment(\.ndk) var ndk

// Access current user
@Environment(\.currentUser) var currentUser
```

### View Extensions

```swift
// Apply Nostr-specific styling
View()
    .nostrStyle()

// Add Nostr entity parsing to any text
Text(content)
    .parseNostrEntities()
```

### Color Palette

```swift
// Predefined Nostr colors
Color.nostrPurple
Color.nostrOrange
Color.nostrBlue
```

## Best Practices

1. **Always provide NDK in environment** - Components expect NDK to be available
2. **Use data sources for reactive updates** - Don't manually fetch data
3. **Compose smaller components** - Build complex UIs from simple building blocks
4. **Customize thoughtfully** - Start with defaults, customize when needed
5. **Handle loading states** - Components provide loading indicators

## Example: Building a Simple Feed

```swift
struct NostrFeedView: View {
    @EnvironmentObject var ndk: NDK
    @StateObject private var feedData = NDKEventDataSource(
        filter: NDKFilter(kinds: [.text], limit: 50),
        ndk: NDK.shared // Will be replaced by environment object
    )
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(feedData.events) { event in
                    VStack(alignment: .leading, spacing: 12) {
                        // Author header
                        HStack {
                            NDKProfilePicture(pubkey: event.author)
                                .size(40)
                            
                            VStack(alignment: .leading) {
                                NDKDisplayName(pubkey: event.author)
                                    .font(.headline)
                                NDKRelativeTime(date: event.createdAt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        // Content with markdown rendering
                        NDKMarkdownRenderer(event: event, ndk: ndk)
                            .markdownStyle(.minimal)
                        
                        // Interaction bar
                        HStack(spacing: 20) {
                            NDKReactionButton(event: event)
                            NDKZapButton(event: event)
                            Button(action: { /* reply */ }) {
                                Label("Reply", systemImage: "bubble.left")
                            }
                        }
                        .font(.callout)
                    }
                    .padding()
                    
                    Divider()
                }
            }
        }
        .onAppear {
            feedData.ndk = ndk // Update with environment NDK
        }
    }
}
```

## Migration from UIKit

If migrating from UIKit-based Nostr apps:

1. Replace manual API calls with data sources
2. Use NDKSwiftUI components instead of custom views
3. Leverage SwiftUI's declarative updates
4. Let NDK handle caching and updates

## Performance Tips

1. Use `LazyVStack`/`LazyHStack` for large lists
2. Implement proper view identifiers
3. Limit concurrent image downloads
4. Use appropriate cache policies
5. Profile with Instruments for bottlenecks

## Troubleshooting

### Components not updating
- Ensure NDK is in environment
- Check that data sources are properly initialized
- Verify relay connections

### Images not loading
- Check network connectivity
- Verify image URLs are valid
- Ensure proper permissions

### Markdown rendering issues
- Validate markdown syntax
- Check for unsupported markdown features
- Verify Nostr entity formats