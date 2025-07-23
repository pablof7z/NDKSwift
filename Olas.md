# Olas: A Picture-First Nostr Experience

## Vision Statement

Olas represents the pinnacle of decentralized visual storytelling—a Nostr client that doesn't just display images, but creates an immersive, joyful experience around them. Every interaction, every animation, every pixel is crafted to spark delight. This is Instagram reimagined for the decentralized age, where beauty and freedom coexist.

### Core Principles

1. **Joy Through Motion**: Every interaction responds with fluid, purposeful animation
2. **Reactive First**: Content renders instantly as it arrives—never make users wait
3. **Pixel Perfect**: Every element aligned to an 8pt grid with mathematical precision
4. **Zero Compromises**: Ship complete features only—no placeholders, no "coming soon"
5. **Decentralized Beauty**: Prove that open protocols can create superior user experiences

## Visual Design System

### Color Philosophy
- **Primary**: Dynamic gradients that shift based on time of day
  - Dawn: `#FF6B6B` → `#4ECDC4` (warm coral to mint)
  - Day: `#667eea` → `#764ba2` (vibrant purple to violet)
  - Dusk: `#f093fb` → `#f5576c` (pink to rose)
  - Night: `#4facfe` → `#00f2fe` (deep blue to cyan)
- **Background**: Pure black (`#000000`) for OLED optimization
- **Surface**: Glass morphism with 8% white overlay
- **Text**: High contrast white with subtle shadows for depth

### Typography
- **Display**: SF Display Rounded for warmth
- **Body**: Inter for clarity
- **Monospace**: JetBrains Mono for keys/technical content
- **Scale**: 1.25 ratio (Musical fourth)

### Animation Language
- **Spring**: `stiffness: 260, damping: 20` for responsive feel
- **Easing**: Custom cubic-bezier `(0.34, 1.56, 0.64, 1)` for playful bounce
- **Duration**: 200ms for micro, 350ms for macro interactions
- **Performance**: Maintain 60fps using Metal acceleration

### Grid System
- **Base**: 8pt grid with 16pt/24pt/32pt rhythm
- **Gaps**: 1px hairlines for image grids
- **Safe Areas**: Dynamic adaptation for notches/islands
- **Breakpoints**: Fluid scaling from iPhone SE to iPad Pro

## Feature Specifications

### 1. Authentication & Onboarding

#### Account Creation Flow
- **Visual Key Generation**: Animated particles coalesce into key visualization
- **Mnemonic Display**: Words appear with staggered spring animation
- **Security Animation**: Locking animation when user confirms backup
- **Haptic Feedback**: Subtle taps for each interaction milestone

#### Login Experience
- **Key Entry**: Animated field with live validation
- **NIP-07 Detection**: Automatic browser extension discovery
- **Profile Loading**: Skeleton screens with shimmer effect
- **Success State**: Confetti burst transitioning to main feed

### 2. Picture Feed

#### Feed Architecture
```swift
// Reactive subscription pattern
for await event in ndk.subscribe(NDKFilter(kinds: [20])) {
    feedItems.append(FeedItem(from: event))
    // Render immediately, don't wait for profile
}
```

#### Image Loading Pipeline
1. **Immediate**: Display blurhash placeholder
2. **Progressive**: Load image in increasing quality tiers
3. **Optimization**: Cache with intelligent prefetching
4. **Fallbacks**: Seamless transition between URLs

#### Multi-Image Layouts
- **Single**: Full-width with 4:5 aspect ratio
- **Double**: Side-by-side with 8:9 each
- **Triple**: Hero left (8:9), two stacked right (1:1)
- **Quad**: Perfect 2x2 grid with 1px gaps

#### Scroll Performance
- **Virtualization**: Render only visible + 2 buffer items
- **Recycling**: Aggressive view reuse for memory efficiency
- **Preloading**: Intelligent direction-based prefetch
- **Momentum**: Physics-based deceleration

#### Advanced Interactions
- **Pinch to Zoom**: Seamless zoom on feed images
  - Smooth gesture recognition without entering full screen
  - Double-tap to quick zoom/reset
  - Momentum-based pan when zoomed
- **3D Touch/Haptic Feedback**:
  - Peek: Light press for image preview
  - Pop: Deeper press to enter full view
  - Haptic menus: Force touch for quick actions
  - Impact feedback on all interactions
- **Swipe Gestures**:
  - Left: Quick share sheet
  - Right: Save to collection
  - Up: View user profile
  - Down: Dismiss if in preview
- **Pull-to-Create**:
  - Elastic pull animation on feed top
  - Camera icon grows as you pull
  - Haptic trigger at activation threshold
  - Smooth transition to camera mode
- **Photo Tagging** (NIP-68 annotate-user):
  - Tap to add user tags on image coordinates
  - Tags follow pinch/zoom transformations
  - Floating name labels with glassmorphism
  - Profile preview on tag tap

### 3. Content Creation

#### Camera Integration
- **Custom UI**: Full-screen capture with gesture controls
- **Live Filters**: Real-time Metal shaders for preview
- **Multi-Select**: Gallery with numbered selection badges
- **Crop/Rotate**: Gesture-based with snapping guides

#### Advanced Camera Features
- **Portrait Mode**: Depth-based blur using Core ML for professional bokeh
  - Real-time depth map visualization
  - Adjustable blur intensity post-capture
  - Edge detection refinement
- **Night Mode**: Enhanced low-light capture with AI
  - Automatic exposure stacking
  - Noise reduction without detail loss
  - Handheld stability compensation
- **Burst Mode**: Hold shutter for rapid capture
  - 10fps burst with best shot suggestions
  - Animated preview scrubber
  - Smart selection based on sharpness/faces
- **Timer Options**: 
  - 3s/10s countdown with full-screen numeric display
  - Audio countdown in final 3 seconds
  - Hand gesture detection to start timer
- **Composition Helpers**:
  - Rule of thirds grid with golden ratio option
  - Electronic level for horizon alignment
  - Leading lines detection overlay
- **Flash Control**:
  - Auto: Scene-based intelligent flash
  - On: Forced flash with intensity slider
  - Off: Natural light only
  - Torch: Continuous light for video

#### Filter Collection (12 Total)
1. **Olas Classic**: Subtle contrast boost with warmth
2. **Neon Tokyo**: Cyberpunk-inspired color grading
3. **Golden Hour**: Warm highlights, cool shadows
4. **Nordic Frost**: Desaturated with blue undertones
5. **Vintage Film**: Grain, vignette, color shift
6. **Black Pearl**: Rich black and white conversion
7. **Coral Dream**: Peachy tones with soft highlights
8. **Electric Blue**: High contrast with blue accent
9. **Autumn Maple**: Warm oranges and deep reds
10. **Mint Fresh**: Cool greens with brightness
11. **Purple Haze**: Moody purples with fade
12. **No Filter**: Original with slight optimization

#### Editing Tools
- **Brightness**: Circular slider with live preview
- **Contrast**: Dual-thumb range control
- **Saturation**: Color wheel visualization
- **Crop**: Aspect ratio presets with free transform
- **Straighten**: Accelerometer-assisted level

#### Caption Composer
- **Rich Text**: @ mentions with autocomplete
- **Hashtags**: Trending suggestions based on content
- **Location**: MapKit integration with privacy controls
- **Drafts**: Local storage with expiration

#### Rich Text Rendering
- **Embedded Entities**: Support for Nostr's embedded content types
  - User mentions (@npub, @nprofile) with reactive profile loading
  - Event references (note1, nevent) with inline previews
  - Hashtags with tap-to-explore functionality
  - URLs with automatic link previews
- **Reactive Loading**: Profile names load as they arrive, never blocking render
- **Visual Formatting**:
  - User mentions in accent color with displayName resolution
  - Hashtags in accent color with tap gesture
  - Links underlined with preview cards below
  - Event references with inline preview cards
- **Performance**: Efficient text component merging for smooth rendering

### 4. Blossom Integration

#### Server Management
- **Discovery**: NIP-89 based server finding
- **Health Monitoring**: Real-time status indicators
- **Preferences**: Drag-to-reorder priority list
- **Auth**: Per-server key management

#### Upload Flow
```swift
// Multi-server parallel upload
let servers = blossomServers.sorted(by: .priority)
let uploads = servers.map { server in
    blossomClient.upload(image, to: server)
}
let results = await withTaskGroup(of: UploadResult.self) { group in
    // Parallel uploads with fallback
}
```

#### Smart Distribution
- **Redundancy**: Minimum 3 server copies
- **Geographic**: CDN-like distribution
- **Fallback**: Automatic retry on failure
- **Progress**: Combined upload indicator

### 5. Engagement Features

#### Like Animation
- **Tap**: Heart scales with spring physics
- **Double Tap**: Particle burst from touch point
- **Long Press**: Emoji reaction picker
- **Zap**: Lightning animation with satoshi rain

#### Reply System
```swift
// Using NDK reply builder
let replyBuilder = event.reply()
replyBuilder.content(userText)
replyBuilder.addImageReferences(selectedImages)
let replyEvent = try await replyBuilder.publish()
```

#### Reply Threading
- **Inline Preview**: First reply visible on feed
- **Expansion**: Smooth accordion with comment tree
- **Navigation**: Swipe between thread levels
- **Context**: Parent post stays visible at top
- **Rich Comments**: Full embedded entity support in replies
  - User mentions become tappable profiles
  - Hashtags link to discovery
  - Quoted events show preview cards
  - Image URLs render as inline images

### 6. Profile Experience

#### Profile Header
- **Parallax**: Banner image with scroll-based zoom
- **Avatar**: Circular with subtle 3D rotation on scroll
- **Stats**: Animated number counting on appear
- **Actions**: Floating follow button with state animation

#### Content Grid
- **Layout**: 3 columns with consistent gaps
- **Loading**: Progressive from center outward
- **Interaction**: Pinch to zoom preview
- **Navigation**: Smooth transition to full post

#### Following System
- **Animation**: User cards flip when following
- **Suggestions**: ML-based recommendation cards
- **Categories**: Content-based follow lists
- **Import**: Contact list from other platforms

### 7. Discovery Features

#### Explore Tab
- **Masonry**: Pinterest-style responsive grid
- **Categories**: Horizontally scrollable pills
- **Trending**: Real-time hashtag velocity
- **Search**: Instant results with highlighting

#### Hashtag Pages
- **Header**: Animated usage graph
- **Filter**: Time range and engagement sort
- **Related**: Suggested similar tags
- **Subscribe**: Follow hashtags like users

### 8. Gamification & Achievements

#### Achievement System
- **Visual Badges**: Collectible achievements with unique animations
  - First Post: "Pioneer" - Animated seedling growing
  - 100 Followers: "Rising Star" - Constellation formation
  - Perfect Week: "Consistent Creator" - 7-day streak flame
  - Viral Post: "Lightning Strike" - Electric surge animation
  - Early Adopter: "OG" - Holographic shimmer effect
- **Progress Tracking**:
  - Circular progress rings for each achievement
  - Milestone notifications with confetti
  - Statistics dashboard with charts
  - Shareable achievement cards
- **Reward Mechanics**:
  - Unlock exclusive filters/effects
  - Special profile badges
  - Priority in discovery algorithms
  - Beta feature access
- **Social Achievements**:
  - Collaboration badges for joint posts
  - Community helper for quality replies
  - Trend setter for starting viral hashtags
  - Ambassador for bringing new users

### 9. Settings & Preferences

#### Account Management
- **Key Backup**: Visual QR with animation
- **Security**: Biometric lock options
- **Sessions**: Device management list
- **Export**: Full data download

#### Relay Configuration
- **Status**: Real-time connection health
- **Performance**: Latency measurements
- **Selection**: Geographic preferences
- **Custom**: Add relay with validation

#### Privacy Controls
- **Visibility**: Granular sharing options
- **Blocks**: Mute with expiration
- **Reports**: NIP-69 moderation
- **Data**: Local-first with sync options

## Technical Architecture

### Core Stack
```swift
// Foundation
import SwiftUI
import NDKSwift
import PhotosUI
import CoreImage
import Metal

// Architecture
@MainActor
class FeedViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    private var subscription: NDKSubscription?
    
    func startFeed() async {
        let filter = NDKFilter(kinds: [20])
        
        for await event in ndk.subscribe(filter) {
            // Reactive pattern: render immediately
            items.append(FeedItem(from: event))
            
            // Fetch profile asynchronously
            Task {
                let profile = await ndk.fetchProfile(event.pubkey)
                updateItem(event.id, with: profile)
            }
        }
    }
}
```

### Image Pipeline
```swift
struct OptimizedImageView: View {
    let imeta: ImageMetadata
    @State private var phase: ImagePhase = .blurhash
    
    var body: some View {
        ZStack {
            // Layer 1: Blurhash
            if let blurhash = imeta.blurhash {
                BlurhashView(hash: blurhash)
                    .opacity(phase == .blurhash ? 1 : 0)
            }
            
            // Layer 2: Progressive image
            CachedAsyncImage(url: imeta.url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear { 
                        withAnimation(.spring()) {
                            phase = .loaded
                        }
                    }
            }
        }
    }
}
```

### Reactive Subscriptions
```swift
// Profile updates
class ProfileObserver: ObservableObject {
    @Published var profile: NDKUserProfile?
    
    func observe(_ pubkey: String) async {
        // Subscribe to profile updates
        let filter = NDKFilter(
            kinds: [0], // metadata
            authors: [pubkey]
        )
        
        for await event in ndk.subscribe(filter) {
            profile = try? await event.decodeMetadata()
        }
    }
}
```

### Rich Text Components
```swift
// Reactive rich text rendering
struct OlasRichText: View {
    let content: String
    let tags: [Tag]
    @State private var parsedContent: NDKParsedContent?
    @State private var profileCache: [String: NDKUserProfile] = [:]
    
    var body: some View {
        if let parsed = parsedContent {
            parsed.components.reduce(Text("")) { result, component in
                result + renderComponent(component)
            }
            .task {
                // Load profiles reactively as mentions appear
                for component in parsed.components {
                    if case .userMention(let pubkey, _) = component {
                        loadProfile(pubkey)
                    }
                }
            }
        }
    }
    
    func renderComponent(_ component: NDKParsedContent.Component) -> Text {
        switch component {
        case .text(let text):
            return Text(text)
        case .userMention(let pubkey, _):
            let name = profileCache[pubkey]?.displayName ?? "Loading..."
            return Text("@\(name)")
                .foregroundStyle(LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .bold()
        case .hashtag(let tag):
            return Text("#\(tag)")
                .foregroundStyle(.accent)
                .underline()
        default:
            return Text("")
        }
    }
}
```

## Performance Metrics

### Target Performance
- **Launch**: < 1s to first paint
- **Feed Scroll**: Consistent 60fps
- **Image Load**: < 200ms to blurhash
- **Post Create**: < 2s including upload
- **Memory**: < 150MB in typical use

### Optimization Strategies
1. **Lazy Loading**: ViewBuilder with on-demand creation
2. **Image Cache**: 100MB disk, 50MB memory limits
3. **Prefetching**: 2 screens ahead/behind
4. **Compression**: WebP with quality tiers
5. **Threading**: Background queues for heavy ops

## Implementation Milestones

### Phase 1: Foundation (Weeks 1-3)
1. **Project Setup**: Create Xcode project with NDKSwift integration
2. **Authentication**: Complete key generation, storage, and login flows
3. **Design System**: Implement colors, typography, and base components

### Phase 2: Core Feed (Weeks 4-6)
4. **Feed Architecture**: Reactive subscription and data flow
5. **Image Pipeline**: Blurhash, progressive loading, caching
6. **Multi-Image Layout**: Grid system with gesture support

### Phase 3: Content Creation (Weeks 7-9)
7. **Camera Integration**: Custom capture with live preview
8. **Filter Engine**: Metal shaders for all 12 filters
9. **Blossom Upload**: Multi-server distribution system

### Phase 4: Engagement (Weeks 10-12)
10. **Like System**: Animations and zap integration
11. **Reply Threading**: Nested comment system
12. **Profile Pages**: Complete user profile experience

### Phase 5: Discovery (Weeks 13-15)
13. **Explore Tab**: Masonry grid with categories
14. **Search**: Full-text with instant results
15. **Hashtags**: Trending system and pages

### Phase 6: Polish (Weeks 16-18)
16. **Animations**: Micro-interactions throughout
17. **Performance**: Optimization and profiling
18. **Accessibility**: VoiceOver and Dynamic Type

### Phase 7: Extended Features (Weeks 19-21)
19. **Stories**: 24-hour ephemeral content
20. **Direct Messages**: NIP-04 encrypted chat
21. **Creator Tools**: Analytics and insights

## Testing Strategy

### Unit Tests
- View models with reactive scenarios
- Image pipeline edge cases
- Nostr event validation
- Blossom server selection

### UI Tests
- Critical user flows
- Gesture interactions
- Performance benchmarks
- Accessibility validation

### Beta Program
- TestFlight with 100 initial users
- Feedback integrated weekly
- Performance monitoring
- Crash reporting

## Launch Strategy

### Soft Launch
- Onboard 10 influencers
- Create showcase content
- Gather testimonials
- Refine based on feedback

### Public Launch
- App Store optimization
- Press kit with assets
- Social media campaign
- Community building

## Success Metrics

### User Experience
- Time to first post < 2 minutes
- Daily active usage > 5 minutes
- User retention > 40% at 30 days
- App Store rating > 4.5 stars

### Technical
- Crash rate < 0.1%
- Feed render < 16ms/frame
- Upload success > 95%
- Memory usage < 150MB

## Conclusion

Olas will prove that decentralized protocols can deliver experiences that exceed centralized platforms. By focusing obsessively on performance, beauty, and joy, we create not just an app, but a movement toward a more open, beautiful internet.

Every pixel matters. Every animation delights. Every interaction sparks joy.

This is Olas. This is the future of visual storytelling on Nostr.