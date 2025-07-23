# NDKSwiftUI Example

This example demonstrates the usage of NDKSwiftUI components for building Nostr applications.

## Components Demonstrated

### Data Sources
- `NDKProfileDataSource` - Observable profile data with automatic loading
- `NDKEventDataSource` - Observable event streams with filtering
- `NDKContactsDataSource` - Contact list management

### UI Components
- `NDKProfilePicture` - User profile pictures with fallbacks
- `NDKDisplayName` - User display names with progressive loading
- `NDKUsername` - User usernames with fallback logic
- `NDKRelativeTime` - Relative timestamp formatting

### Event Components
- `NDKEventView` - Multi-kind event rendering
- `NDKTextNoteView` - Text note display (kind:1)
- `NDKPictureEventView` - Picture-first display (kind:20, NIP-68)
- `NDKLongFormArticleView` - Article previews (kind:30023)
- `NDKCashuTokenView` - Cashu token display (kind:9321)
- `NDKEventAuthorHeader` - Author information display
- `NDKEventInteractionBar` - Like/reply/zap buttons

### Action Components
- `NDKReactionButton` - Emoji reactions with real-time counts
- `NDKZapButton` - Lightning payment integration
- `NDKFollowButton` - Follow/unfollow with contact list management

### Utilities
- `NDKRichText` - Rich text parsing and rendering
- Color system with platform-specific adaptations

## Usage

```swift
import NDKSwiftUI

struct MyView: View {
    let ndk: NDK
    let event: NDKEvent
    
    var body: some View {
        VStack {
            // Profile components
            NDKProfilePicture(pubkey: event.pubkey)
            NDKDisplayName(pubkey: event.pubkey)
            NDKRelativeTime(event: event)
            
            // Event content
            NDKEventView(event: event, style: .feed)
            
            // Action buttons
            HStack {
                NDKReactionButton.like(event: event)
                NDKZapButton(event: event, amounts: [21, 100, 1000])
                NDKFollowButton(pubkey: event.pubkey)
            }
        }
        .environment(\.ndk, ndk)
    }
}
```

## Running the Example

```bash
cd Examples/NDKSwiftUI-Example
swift run
```

## Architecture

The NDKSwiftUI library follows these principles:

1. **Composable, not prescriptive** - Building blocks, not complete screens
2. **Data-driven** - Components react to NDK's data streams
3. **Progressive loading** - No blocking UI, shows fallbacks immediately
4. **Streaming data** - Real-time updates as data arrives
5. **Platform adaptive** - Works across iOS, macOS, tvOS, watchOS