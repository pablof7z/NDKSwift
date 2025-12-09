# Short Video Support Design

## Overview

Add support for NIP-71 kind 22 (short-form vertical videos) to Olas, with user-configurable settings to show/hide videos and control autoplay behavior.

## Scope

- **In scope**: Display kind 22 videos in feed, settings toggles, autoplay with mute
- **Out of scope**: Video posting/upload, kind 21 (long-form videos), separate Reels tab

## Data Model

### NDKVideo (new)

```swift
// Sources/NDKSwift/Models/Kinds/NDKVideo.swift
public class NDKVideo: NDKEvent {
    static let kind: UInt32 = 22  // Short-form video (NIP-71)

    // Parsed from imeta tags (NIP-92):
    var primaryVideoURL: URL?      // First video URL from imeta
    var thumbnailURL: URL?         // image field from imeta (preview frame)
    var primaryBlurhash: String?   // For thumbnail placeholder
    var duration: TimeInterval?    // seconds (from imeta duration field)
    var dimensions: (Int, Int)?    // width x height (from imeta dim field)
    var mimeType: String?          // video/mp4, video/webm, etc.
}
```

Mirrors existing `NDKImage` pattern - wraps NDKEvent, parses imeta tags for video-specific metadata.

## Settings System

### SettingsManager (new)

```swift
// Olas/Sources/Olas/Utilities/SettingsManager.swift
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("showVideos") var showVideos: Bool = true
    @AppStorage("autoplayVideos") var autoplayVideos: Bool = true
}
```

Uses native `@AppStorage` for UserDefaults persistence. Singleton for app-wide access.

### SettingsView Changes

Add "Video" section under "App":
- Toggle: "Show videos in feed" → `showVideos`
- Toggle: "Autoplay videos" → `autoplayVideos` (disabled when showVideos is off)

## Feed Integration

### FeedViewModel Changes

```swift
// Dynamic filter based on settings
var kinds: [UInt32] {
    var k: [UInt32] = [20]  // Always include images
    if SettingsManager.shared.showVideos {
        k.append(22)
    }
    return k
}

// Filter: NDKFilter(kinds: kinds, limit: 50)
```

Videos and images mixed in single `posts` array, sorted by `createdAt`.

### PostCard Changes

Detect content type and render appropriately:

```swift
var body: some View {
    if event.kind == 22 {
        VideoPostCard(event: event)
    } else {
        // Existing image rendering
    }
}
```

## Video Playback Component

### VideoPostCard (new)

```swift
// Olas/Sources/Olas/Views/Components/VideoPostCard.swift
struct VideoPostCard: View {
    let event: NDKEvent
    @EnvironmentObject var settings: SettingsManager
    @State private var player: AVPlayer?
    @State private var isVisible = false

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if settings.autoplayVideos {
                    player?.play()
                    player?.isMuted = true
                }
            }
            .onDisappear {
                player?.pause()
            }
            .onTapGesture {
                // Toggle mute on tap
                player?.isMuted.toggle()
            }
    }
}
```

Key behaviors:
- Autoplay muted when visible (if setting enabled)
- Pause when scrolled off screen
- Tap to unmute/mute
- Double-tap to like (same as images)
- Shows thumbnail with blurhash while loading

### Visibility Detection

Use SwiftUI's `onAppear`/`onDisappear` for basic visibility. Videos pause when not visible to save resources.

## UI/UX Details

### Visual Indicators

- Small play icon overlay on video thumbnails in grid views (Explore, Profile)
- Duration badge in bottom-right corner (e.g., "0:15")
- Mute/unmute icon visible during playback
- Progress bar at bottom of video

### Interactions

- Single tap: Toggle mute
- Double tap: Like (with existing animation)
- Long press: Options menu (same as images)
- Swipe: Scroll to next post (standard feed behavior)

## Files to Create

1. `Sources/NDKSwift/Models/Kinds/NDKVideo.swift` - Video event model
2. `Olas/Sources/Olas/Utilities/SettingsManager.swift` - Settings singleton
3. `Olas/Sources/Olas/Views/Components/VideoPostCard.swift` - Video playback component

## Files to Modify

1. `Olas/Sources/Olas/Views/Components/PostCard.swift` - Dispatch to VideoPostCard for kind 22
2. `Olas/Sources/Olas/ViewModels/FeedViewModel.swift` - Include kind 22 in filter
3. `Olas/Sources/Olas/Views/Settings/SettingsView.swift` - Add video toggles
4. `Olas/Sources/Olas/Views/Explore/ExploreView.swift` - Handle kind 22 in grid
5. `Olas/Sources/Olas/Views/Profile/ProfileView.swift` - Handle kind 22 in grid
6. `Olas/Package.swift` - No changes needed (AVKit is system framework)

## Testing

Manual testing:
1. Videos appear in feed when "Show videos" is on
2. Videos hidden when "Show videos" is off
3. Videos autoplay muted when "Autoplay videos" is on
4. Videos show thumbnail only when "Autoplay videos" is off
5. Tap to play works when autoplay is off
6. Tap toggles mute during playback
7. Double-tap likes video
8. Videos pause when scrolled off screen
9. Settings persist across app restarts
