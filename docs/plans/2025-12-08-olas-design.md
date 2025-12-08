# Olas — Design Document

**Date**: 2025-12-08
**Status**: Approved
**Summary**: Instagram-like photo sharing app built on Nostr using NDKSwift

---

## Overview

Olas is a photo-first social app for Nostr. The name means "waves" in Spanish. The app focuses on beautiful photo sharing with a premium glassmorphism UI featuring ocean-inspired colors.

### Core Principles
- Photo-first content (not video, not text)
- Creation experience matters (great editing tools, frictionless posting)
- Decentralized by default (Nostr + Blossom)
- No DMs, no Stories — focused scope

---

## Navigation

### Tab Bar (Bottom)
Dynamic tab bar with 4-5 tabs:

| Tab | Icon | Visible |
|-----|------|---------|
| Home | Wave | Always |
| Explore | Compass | Always |
| Create | Plus | Always |
| Notifications | Bell | Only when notifications exist |
| Profile | Person | Always |

### Behavior
- Swipe left/right between adjacent tabs
- Tap active tab to scroll-to-top
- Tab bar hides on scroll down, reappears on scroll up
- Glassmorphic background with frosted blur

---

## Screens

### Home Feed

Vertical scroll of posts from followed accounts (chronological).

**Post Card Anatomy**:
```
┌─────────────────────────────────┐
│ [Avatar] Username    • 2h       │  Header
├─────────────────────────────────┤
│                                 │
│         [ PHOTO ]               │  Double-tap to like
│                                 │
├─────────────────────────────────┤
│ ❤️ 🔥 😂  💬 12    ⚡ 2.1k sats │  Reactions/comments/zaps
├─────────────────────────────────┤
│ Caption with #hashtags...       │
│ View all 12 comments            │
└─────────────────────────────────┘
```

**Interactions**:
- Tap reaction bar → emoji picker
- Tap comment icon → half-sheet with comments
- Tap zap icon → amount selector
- Double-tap photo → heart burst animation
- Long-press → quick actions (copy link, share, report)

---

### Explore

Category-based discovery with horizontal scroll rows.

**Layout**:
```
┌─────────────────────────────────┐
│ 🔍 Search...                    │
├─────────────────────────────────┤
│ Trending Now                  → │
│ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ...    │  Horizontal scroll
├─────────────────────────────────┤
│ Photography                   → │
│ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ...    │
├─────────────────────────────────┤
│ Art & Illustration            → │
│ ...                             │
└─────────────────────────────────┘
```

**Categories**: Trending, Photography, Art, Travel, Nature, Food, Fashion, etc.

**Behavior**:
- Tap section header → full grid view
- Tap thumbnail → post detail modal
- Long-press → preview with quick reactions
- Search: users (with avatars) and hashtags (with counts)

---

### Create Flow

Three-step modal flow:

**Step 1: Photo Selection**
- Toggle between Camera and Gallery
- Recent photos in scrollable grid
- Large preview of selected photo

**Step 2: Edit**
- **Filters**: Ocean-themed presets (Ola, Marea, Coral, Reef, Tide)
- **Adjust**: Brightness, Contrast, Saturation, Warmth, Shadows, Highlights
- **Crop**: Free, Square, 4:5, 16:9 + rotate/flip
- **Text**: Overlays with fonts, colors, shadows

**Step 3: Share**
- Caption input
- Hashtag suggestions
- Optional: add to collection
- Post button with progress ring

**Post Flow**:
1. Compress image
2. Upload to Blossom server
3. Publish kind:20 event with image URL
4. Navigate to Home, post appears at top

---

### Profile

**Layout**:
```
┌─────────────────────────────────┐
│ ≡                        ⚙️     │
├─────────────────────────────────┤
│         [  AVATAR  ]            │
│         @username               │
│        Display Name             │
├─────────────────────────────────┤
│   42       128       1.2k       │
│  Posts  Following  Followers    │
├─────────────────────────────────┤
│ Bio text here...                │
├─────────────────────────────────┤
│ [Edit Profile] [Share]          │  Own profile
│ [  Follow   ] [ Zap ]           │  Other profile
├─────────────────────────────────┤
│   Posts    |   Collections      │
├─────────────────────────────────┤
│ [3-column grid or 2-col albums] │
└─────────────────────────────────┘
```

**Collections**: User-curated albums with cover image, name, and post count.

---

### Notifications

Shows reactions, comments, and zaps on your posts.

**Grouped by time**: Today, This Week, Earlier

**Types**:
- Reactions: "alice reacted ❤️ to your post"
- Zaps: "bob and 3 others ⚡ zapped your post (1.4k sats)"
- Comments: "carlos commented: 'Amazing shot!'"

**Behavior**:
- Tap → navigate to post
- Swipe left → dismiss
- Unread items have blue tint on left edge
- **Tab hidden when no notifications exist**

---

## Onboarding

### New User Flow
1. Choose username (real-time availability check)
2. Add profile photo (optional, skippable)
3. Pick topics to follow
4. Suggested accounts to follow
5. Keys generated silently → land on Home

### Existing Nostr User
1. Enter nsec (secure input)
2. "Paste from clipboard" quick action
3. Trust message: "Your key stays on device"
4. Validate → land on Home

### Key Storage
- iOS Keychain (secure enclave)
- Biometric unlock for returning users
- "Backup your key" prompt after first post

---

## Technical Architecture

### Stack
- **NDKSwift**: Core Nostr protocol
- **NostrDB**: High-performance event cache
- **Blossom**: Decentralized image hosting
- **CoreImage**: Photo filters and adjustments

### Event Kinds

| Feature | Kind | Notes |
|---------|------|-------|
| Posts | `20` | NIP-68 image events |
| Profiles | `0` | Metadata (name, bio, avatar) |
| Follows | `3` | Contact list |
| Reactions | `7` | Multi-emoji support |
| Comments | `1111` | Generic replies |
| Zaps | `9734` / `9735` | Request + receipt |
| Collections | `30001` | Parameterized list |
| Topics | `t` tag | Hashtag filtering |

### Image Pipeline
```
Camera/Gallery
    ↓
CoreImage Editing (filters, adjustments)
    ↓
JPEG Compression (quality: 0.85)
    ↓
Blossom Upload
    ↓
Receive URL
    ↓
Publish kind:20 event
```

### Offline Support
- Posts queued locally when offline
- Feed browsing from NostrDB cache
- Auto-sync on reconnect (NDKSwift handles this)

### Relay Strategy
- Default relays for new users
- Outbox model (NIP-65) for experienced users
- Smart relay selection via NDKSwift

---

## Visual Design

### Color Palette

**Primary Ocean**:
- Deep Teal: `#0D7377` (buttons, links)
- Ocean Blue: `#14919B` (accents)
- Seafoam: `#7ED7C1` (highlights)

**Light Mode Neutrals**:
- Background: `#F8FFFE`
- Card: `#FFFFFF` (with blur)
- Text: `#1A2B32`
- Secondary: `#6B8187`

**Dark Mode Neutrals**:
- Background: `#0A1215`
- Card: `#142125` (with blur)
- Text: `#E8F4F5`
- Secondary: `#7B9BA1`

**Feedback**:
- Zap Gold: `#FFB800`
- Heart Red: `#FF4757`
- Success: `#2ED573`

### Glassmorphism

Cards and tab bar use frosted glass effect:
- `.ultraThinMaterial` or `.regularMaterial`
- White overlay at 10% opacity
- 20px corner radius
- Soft shadow (black 10%, radius 20, y-offset 10)
- Subtle 1px white border at 20% opacity on top edge

### Typography

- **Headlines**: SF Pro Display, Semibold
- **Body**: SF Pro Text, Regular
- **Captions**: SF Pro Text, Medium
- **Usernames**: SF Pro Text, Semibold

**Sizes**: Large title 34pt, Title 28pt, Headline 17pt semibold, Body 17pt, Caption 13pt

### Iconography

- SF Symbols throughout
- Filled = selected, Outline = unselected
- Custom wave icon for Home tab

### Motion

- Spring animations (0.5s, bounce 0.3)
- Heart burst on double-tap like
- 0.3s screen transitions
- Wave animation on pull-to-refresh

---

## Social Features

### Reactions
Multiple emoji types: ❤️ 🔥 😂 😢 😮 👏
- Tap reaction bar → emoji picker slides up
- One reaction per user per post
- Grouped display: "❤️ 12  🔥 5  😂 3"

### Comments
- Half-sheet presentation
- Threaded display
- Kind 1111 (genericReply) events

### Zaps
- Preset amounts: 21, 100, 500, 1000, 5000 sats
- Custom amount option
- Gold ⚡ icon with total sats display

### Following
- Kind 3 contact list
- Follow/Unfollow button on profiles
- Following feed is chronological

### Hashtags/Topics
- Inline in captions: #photography
- Tap to view topic feed
- Follow topics from Explore
- `t` tags on events

---

## Not Included (By Design)

- Direct messages
- Stories / ephemeral content
- Creator monetization features (analytics, subscriptions)
- Video content
- Algorithmic feed ranking
- New follower notifications

---

## Next Steps

1. Create HTML/JS interactive storyboard
2. Implement SwiftUI screens
3. Wire up NDKSwift data layer
4. Build image editing pipeline
5. Test with real Nostr relays and Blossom servers
