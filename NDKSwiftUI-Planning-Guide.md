# NDKSwiftUI Module Planning Guide

## High-Level Plan for NDKSwiftUI Module

### Architectural Philosophy

Think of this as creating a **UI toolkit layer** on top of the protocol layer:

```
┌─────────────────────┐
│   Your Nostr App    │  (Olas, Posta, etc.)
├─────────────────────┤
│    NDKSwiftUI       │  ← New module (SwiftUI components)
├─────────────────────┤
│     NDKSwift        │  ← Core library (protocol & data)
├─────────────────────┤
│   Nostr Protocol    │  (NIPs, relays, events)
└─────────────────────┘
```

### Core Principles

1. **Composable, not prescriptive** - Provide building blocks, not complete screens
2. **Data-driven** - Components react to NDK's data streams
3. **Customizable** - Easy to style and extend
4. **Progressive disclosure** - Simple defaults, advanced customization available

### Implementation Phases

#### Phase 1: Foundation (Week 1-2)
- Create `NDKSwiftUI` module structure
- Implement observable data source wrappers
- Build `NDKRichText` for content rendering
- Add basic profile components (avatar, name)

#### Phase 2: Core Components (Week 3-4)
- Post/note display components
- Engagement bar (likes, replies, zaps)
- Thread visualization
- Image galleries with Blossom support

#### Phase 3: Advanced Features (Week 5-6)
- Relay status UI
- Subscription management views
- NIP-05 verification badges
- Wallet integration components

### How to Think About This

**It's like Bootstrap for Nostr apps** - Just as Bootstrap provides UI components for web apps, NDKSwiftUI provides Nostr-specific UI components for SwiftUI apps.

**Key Mental Models:**

1. **Separation of Concerns**
   - NDKSwift: "How do I talk to Nostr?"
   - NDKSwiftUI: "How do I show Nostr data?"

2. **80/20 Rule**
   - Build components that solve 80% of use cases
   - Leave room for the 20% custom implementations

3. **Progressive Enhancement**
   ```swift
   // Simple usage
   NDKProfilePicture(pubkey: user.pubkey)
   
   // Advanced usage
   NDKProfilePicture(pubkey: user.pubkey)
       .size(100)
       .fallbackImage(customImage)
       .onTap { /* custom action */ }
   ```

4. **Data Flow First**
   - Components subscribe to NDK data streams
   - UI automatically updates when data changes
   - No manual state management needed

### Success Metrics

- **Adoption**: Can build a basic Nostr client in < 100 lines of code
- **Flexibility**: Complex apps can still customize everything
- **Performance**: Components handle 1000+ events smoothly
- **Developer Experience**: Clear documentation, intuitive APIs

### What This Enables

Developers can focus on their app's unique features instead of reimplementing:
- Rich text parsing and rendering
- Profile picture loading and caching
- Thread organization and display
- Real-time engagement updates
- Relay connection status

This transforms NDKSwift from "a way to talk to Nostr" into "everything you need to build a Nostr app on Apple platforms."