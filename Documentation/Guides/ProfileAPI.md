# Profile API Guide

## Overview

The Profile API provides a simple, reactive way to access user profile data in NDKSwift. All profile data is automatically cached and updates in real-time.

## Quick Start

### Get a Profile (SwiftUI)

The primary API returns an `@Observable` profile that auto-updates:

```swift
import SwiftUI
import NDKSwiftCore

struct ProfileView: View {
    let ndk: NDK
    let pubkey: String

    var body: some View {
        let profile = ndk.profile(for: pubkey)

        VStack {
            Text(profile.name)
                .font(.title)

            Text(profile.about)
                .foregroundColor(.secondary)

            if let nip05 = profile.nip05 {
                Label(nip05, systemImage: "checkmark.seal")
            }
        }
    }
}
```

### Convenience via NDKUser

```swift
let user = ndk.user(pubkey: "npub...")
let profile = user.profile  // Same as ndk.profile(for: pubkey)

Text(profile.displayName)
```

### For Non-SwiftUI Code

Use `profileUpdates(for:)` to get an `AsyncStream`:

```swift
Task { @MainActor in
    for await metadata in ndk.profileUpdates(for: pubkey) {
        print("Profile updated: \(metadata?.name ?? "Unknown")")
    }
}
```

> **Note:** `profileUpdates(for:)` shares the same underlying subscription as `profile(for:)`.
> Multiple calls for the same pubkey will not create duplicate relay subscriptions.

## UI Components

### Display Name

Use the profile's `displayName` property directly - no wrapper component needed:

```swift
Text(ndk.profile(for: pubkey).displayName)
    .font(.headline)
```

### NDKUIProfilePicture

Displays a user's profile picture with automatic loading:

```swift
NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 50)
```

## How It Works

### Automatic Caching

All profile data is automatically cached in two tiers:
1. **In-memory LRU cache** - Fast access for recently viewed profiles
2. **SQLite database** - Persistent storage

When you call `ndk.profile(for:)`:
1. Returns immediately with cached data (if available)
2. Subscribes to network updates in the background
3. Auto-updates the profile as new data arrives from relays

### Deduplication

Multiple views requesting the same profile share a single instance:

```swift
// These all return the same NDKProfile instance
let profile1 = ndk.profile(for: pubkey)
let profile2 = ndk.profile(for: pubkey)
let profile3 = user.profile

assert(profile1 === profile2)  // true
assert(profile2 === profile3)  // true
```

This means:
- ✅ Efficient memory usage
- ✅ Shared network subscriptions
- ✅ Consistent state across your app

### SwiftUI Integration

`NDKProfile` is `@Observable`, so SwiftUI views automatically refresh when profile data changes:

```swift
struct UserCard: View {
    let ndk: NDK
    let pubkey: String

    var body: some View {
        let profile = ndk.profile(for: pubkey)

        // View auto-refreshes when profile updates!
        HStack {
            AsyncImage(url: profile.pictureURL)
            Text(profile.name)
        }
    }
}
```

## NDKProfile Properties

### Always Available (Non-Optional)

```swift
profile.name          // String (empty if no metadata)
profile.displayName   // String (smart fallback to truncated pubkey)
profile.about         // String (empty if no metadata)
```

### Optional Properties

```swift
profile.nip05         // String?
profile.lud16         // String?
profile.pictureURL    // URL?
profile.bannerURL     // URL?
profile.metadata      // NDKUserMetadata? (full metadata object)
```

## Best Practices

### ✅ Do This

```swift
// Direct property access in SwiftUI
let profile = ndk.profile(for: pubkey)
Text(profile.displayName)

// Use profile picture component
NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 40)

// AsyncStream for background tasks (requires MainActor)
for await metadata in ndk.profileUpdates(for: pubkey) {
    // Process updates
}
```

### ❌ Don't Do This

```swift
// ❌ Don't manually manage subscriptions
Task {
    let filter = NDKFilter(authors: [pubkey], kinds: [.metadata])
    let subscription = ndk.subscribe(filter: filter)
    // ... manual parsing
}

// ❌ Don't store profile in @State
@State private var profileName: String?  // Unnecessary

// Just use the profile directly:
let profile = ndk.profile(for: pubkey)
Text(profile.name)  // Auto-updates!
```

## Examples

### Feed View with Profiles

```swift
struct FeedView: View {
    let ndk: NDK
    let posts: [Post]

    var body: some View {
        List(posts) { post in
            HStack {
                NDKUIProfilePicture(ndk: ndk, pubkey: post.author, size: 40)

                VStack(alignment: .leading) {
                    Text(ndk.profile(for: post.author).displayName)
                        .font(.headline)

                    Text(post.content)
                        .font(.body)
                }
            }
        }
    }
}
```

### Profile Detail Page

```swift
struct ProfileDetailView: View {
    let ndk: NDK
    let pubkey: String

    var body: some View {
        let profile = ndk.profile(for: pubkey)

        ScrollView {
            VStack(spacing: 20) {
                // Header
                AsyncImage(url: profile.bannerURL)
                    .frame(height: 200)

                NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 100)
                    .offset(y: -50)

                // Info
                Text(profile.displayName)
                    .font(.title)

                if let nip05 = profile.nip05 {
                    Label(nip05, systemImage: "checkmark.seal")
                        .foregroundColor(.blue)
                }

                Text(profile.about)
                    .multilineTextAlignment(.center)
                    .padding()

                // Stats, follow button, etc.
            }
        }
    }
}
```

### Background Profile Processing

```swift
class ProfileAnalyzer {
    @MainActor
    func analyzeProfile(pubkey: String, ndk: NDK) async {
        for await metadata in ndk.profileUpdates(for: pubkey) {
            guard let metadata else { continue }

            // Process profile
            if let nip05 = metadata.nip05 {
                await verifyNIP05(nip05)
            }

            // Only need first result
            break
        }
    }
}
```

## Migration from Old API

### Before (NDKProfileManager)

```swift
// Old way
for await profile in await ndk.profileManager.subscribe(for: pubkey, maxAge: .hour) {
    self.profileName = profile?.name
    break
}
```

### After (New API)

```swift
// New way - simpler!
let profile = ndk.profile(for: pubkey)
Text(profile.name)  // Auto-updates
```

### Before (Data Sources)

```swift
// Old way
@StateObject private var profileDS = NDKProfileDataSource(ndk: ndk, pubkey: pubkey)

var body: some View {
    Text(profileDS.metadata?.name ?? "Unknown")
}
```

### After (Direct Profile)

```swift
// New way - much simpler!
var body: some View {
    let profile = ndk.profile(for: pubkey)
    Text(profile.name)
}
```

## Performance

- **Memory cache**: ~1000 profiles (LRU eviction)
- **Cache hit time**: < 1ms (in-memory lookup)
- **Cache miss + DB hit**: < 10ms (SQLite query)
- **Network fetch**: Variable (depends on relay response time)
- **Deduplication**: Same pubkey = same instance (efficient memory usage)

## Summary

**The Profile API follows a simple principle:**

> "Just ask for a profile and use it. Everything else happens automatically."

- ✅ Automatic caching
- ✅ Automatic updates
- ✅ Automatic deduplication
- ✅ Automatic cleanup
- ✅ Idiomatic Swift/SwiftUI

No manual subscription management. No @State boilerplate. Just profiles that work.
