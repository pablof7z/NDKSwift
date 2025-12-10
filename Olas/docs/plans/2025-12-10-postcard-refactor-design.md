# PostCard/VideoPostCard Refactoring Design

## Problem

`PostCard.swift` (526 lines) and `VideoPostCard.swift` (445 lines) share ~70% identical code. Any bug fix or feature requires changes in both files.

## Solution

Unified `PostCard` component with extracted subcomponents. Single source of truth for all interaction logic.

## Architecture

```
Views/Components/Post/
├── PostCard.swift              # Main entry point, owns state and logic
├── PostHeader.swift            # Author avatar, name, time, overflow menu
├── PostActions.swift           # Like, Comment, Zap, Share row
├── PostCaption.swift           # Inline username + content + like count
├── ImageMediaView.swift        # Image rendering, double-tap, fullscreen
├── VideoMediaView.swift        # Video player, mute, thumbnail, duration
└── FullscreenImageViewer.swift # Fullscreen image with zoom/pan
```

## Component Design

### PostCard.swift (~180 lines)

The main component that:
- Detects media type from `event.kind`
- Owns all `@State`: isLiked, showLikeAnimation, likeCount, commentCount, showComments, showReportSheet, showAddToCollection, showFullscreenImage
- Contains all async logic: loadReactions(), loadReactionCount(), loadCommentCount(), publishReaction(), toggleLike(), muteAuthor()
- Composes subcomponents
- Attaches all sheets

```swift
struct PostCard: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?

    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var showComments = false
    @State private var showReportSheet = false
    @State private var showAddToCollection = false
    @State private var showFullscreenImage = false

    @EnvironmentObject private var muteListManager: MuteListManager

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostHeader(
                event: event,
                ndk: ndk,
                onProfileTap: onProfileTap,
                onCopyId: copyEventId,
                onReport: { showReportSheet = true },
                onMute: { Task { await muteAuthor() } }
            )

            mediaContent

            PostActions(
                event: event,
                ndk: ndk,
                isLiked: $isLiked,
                likeCount: likeCount,
                commentCount: commentCount,
                onLikeTap: { Task { await toggleLike() } },
                onCommentTap: { showComments = true },
                onAddToCollection: { showAddToCollection = true },
                onShare: sharePost
            )

            PostCaption(
                ndk: ndk,
                pubkey: event.pubkey,
                content: event.content,
                likeCount: likeCount
            )
        }
        .task { await loadReactions() }
        .sheet(isPresented: $showComments) { CommentsSheet(event: event, ndk: ndk) }
        .sheet(isPresented: $showReportSheet) { ReportSheet(event: event, ndk: ndk) }
        .sheet(isPresented: $showAddToCollection) { AddToCollectionSheet(pictureEvent: event) }
        .fullScreenCover(isPresented: $showFullscreenImage) { fullscreenViewer }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if isVideo {
            VideoMediaView(
                event: event,
                showLikeAnimation: $showLikeAnimation,
                onDoubleTap: handleDoubleTap
            )
        } else {
            ImageMediaView(
                event: event,
                showLikeAnimation: $showLikeAnimation,
                onDoubleTap: handleDoubleTap,
                onTap: { showFullscreenImage = true }
            )
        }
    }

    // ... interaction methods (handleDoubleTap, toggleLike, publishReaction, etc.)
}
```

### PostHeader.swift (~60 lines)

Displays author info and overflow menu.

```swift
struct PostHeader: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?
    let onCopyId: () -> Void
    let onReport: () -> Void
    let onMute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture button
            // Name + timestamp
            // Overflow menu (Copy ID, Report, Mute)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

### PostActions.swift (~50 lines)

Action bar with like, comment, zap, share.

```swift
struct PostActions: View {
    let event: NDKEvent
    let ndk: NDK
    @Binding var isLiked: Bool
    let likeCount: Int
    let commentCount: Int
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onAddToCollection: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            LikeButton(isLiked: $isLiked, likeCount: likeCount, action: onLikeTap)
            CommentButton(commentCount: commentCount, action: onCommentTap)
            ZapButton(event: event, ndk: ndk)
            Spacer()
            // Share menu with Add to Collection + Share
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

### PostCaption.swift (~70 lines)

Caption with inline username and like count.

```swift
struct PostCaption: View {
    let ndk: NDK
    let pubkey: String
    let content: String
    let likeCount: Int

    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    var body: some View {
        // Username (bold) + content
        // Like count if > 0
    }
}
```

### ImageMediaView.swift (~80 lines)

Image display with gestures.

```swift
struct ImageMediaView: View {
    let event: NDKEvent
    @Binding var showLikeAnimation: Bool
    let onDoubleTap: () -> Void
    let onTap: () -> Void

    private var image: NDKImage { NDKImage(event: event) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // CachedAsyncImage with blurhash
                // Gesture handlers
                LikeAnimation(isAnimating: $showLikeAnimation)
            }
        }
        .frame(height: calculatedHeight)
    }
}
```

### VideoMediaView.swift (~120 lines)

Video player with controls.

```swift
struct VideoMediaView: View {
    let event: NDKEvent
    @Binding var showLikeAnimation: Bool
    let onDoubleTap: () -> Void

    @State private var player: AVPlayer?
    @State private var isMuted = true

    private var video: NDKVideo { NDKVideo(event: event) }

    var body: some View {
        ZStack {
            // VideoPlayer or thumbnail
            // Mute indicator overlay
            // Duration badge
            LikeAnimation(isAnimating: $showLikeAnimation)
        }
        .onTapGesture { toggleMute() }
        .onTapGesture(count: 2) { onDoubleTap() }
        .task { setupPlayer() }
        .onDisappear { player?.pause() }
    }
}
```

### FullscreenImageViewer.swift (~90 lines)

Already exists embedded in PostCard. Extract as-is with zoom/pan gestures.

## Data Flow

```
PostCard (owns state)
    │
    ├── PostHeader
    │   └── callbacks: onCopyId, onReport, onMute, onProfileTap
    │
    ├── ImageMediaView / VideoMediaView
    │   └── bindings: showLikeAnimation
    │   └── callbacks: onDoubleTap, onTap (image only)
    │
    ├── PostActions
    │   └── bindings: isLiked
    │   └── values: likeCount, commentCount
    │   └── callbacks: onLikeTap, onCommentTap, onAddToCollection, onShare
    │
    └── PostCaption
        └── values: content, likeCount
```

## Unification Decisions

1. **Add to Collection**: Available for both image and video posts
2. **Share**: Uses working implementation from image post for both
3. **Fullscreen**: Only for images (video plays inline with controls)
4. **NotificationCenter leak fix**: VideoMediaView will properly remove observer on disappear

## Migration

1. Create `Views/Components/Post/` directory
2. Create all new component files
3. Update imports in FeedView, ProfileView, etc. (they just use `PostCard`)
4. Delete old `VideoPostCard.swift`
5. Old `PostCard.swift` becomes the new unified version

## Testing

After refactoring:
- Image posts render correctly with all interactions
- Video posts render correctly with player, mute, autoplay
- Double-tap like works on both
- All sheets (comments, report, add to collection) work
- Fullscreen image viewer works
- Video looping works
- Mute toggle works
