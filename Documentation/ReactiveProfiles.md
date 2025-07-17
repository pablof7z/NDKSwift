# Reactive Profile Fetching in NDKSwift

NDKSwift provides a reactive API for fetching and observing user profiles that automatically handles caching, network requests, and real-time updates.

## Overview

The `observeProfile` method returns an `AsyncStream<NDKUserProfile?>` that:
1. Immediately yields cached profile data (if available)
2. Fetches fresh data from relays
3. Continues to yield updates when the profile changes

This pattern ensures your UI always displays the most up-to-date profile information without manual refresh logic.

## Basic Usage

```swift
// Observe profile updates
let ndk = NDK(...)
let profileStream = await ndk.observeProfile(for: pubkey)

for await profile in profileStream {
    // Update UI with profile data
    // This will be called:
    // 1. Immediately with cached data (if any)
    // 2. When fresh data arrives from relays
    // 3. Whenever the profile is updated
}
```

## SwiftUI Integration

```swift
struct ProfileView: View {
    let pubkey: String
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            if let profile = profile {
                Text(profile.displayName ?? "Unknown")
                // ... rest of profile UI
            } else {
                // Show loading or placeholder UI
                ProgressView()
            }
        }
        .task {
            await observeProfile()
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
    
    private func observeProfile() async {
        guard let ndk = getNDK() else { return }
        
        profileTask = Task {
            let profileStream = await ndk.observeProfile(for: pubkey)
            
            for await profileUpdate in profileStream {
                await MainActor.run {
                    self.profile = profileUpdate
                }
            }
        }
    }
}
```

## Progressive Rendering vs Continuous Updates

The `observeProfile` method supports two modes:

### Progressive Rendering (closeOnEose: true)
Perfect for initial page loads where you want to render data as it arrives:

```swift
let profileStream = await ndk.observeProfile(for: pubkey, closeOnEose: true)

for await profile in profileStream {
    // Update UI immediately with whatever data is available
    // Stream closes automatically after initial data is received
}
```

### Continuous Updates (closeOnEose: false, default)
For keeping profiles in sync with real-time changes:

```swift
let profileStream = await ndk.observeProfile(for: pubkey)

for await profile in profileStream {
    // Handle initial profile and all future updates
}
```

## How It Works

1. **Cache Check**: When you call `observeProfile`, it first checks the in-memory cache
2. **Immediate Yield**: If a cached profile exists (and isn't stale), it's yielded immediately
3. **Network Request**: A subscription is created to fetch the latest profile from relays
4. **Progressive Updates**: Data is yielded as soon as it arrives from any relay
5. **Automatic Cleanup**: With `closeOnEose: true`, closes after initial data; otherwise continues monitoring
6. **Resource Efficient**: Shared subscriptions for multiple observers of the same profile

## Benefits

- **Responsive UI**: Users see cached data immediately while fresh data loads
- **Real-time Updates**: Profile changes are reflected automatically
- **Resource Efficient**: Shared subscriptions for multiple observers of the same profile
- **Simple API**: No manual subscription management needed

## When to Use Each Approach

### Use `observeProfile(closeOnEose: true)` when:
- Loading a profile page where you want progressive rendering
- You need profile data but don't need real-time updates
- Building responsive UIs that show data as it arrives
- Replacing `fetchProfile` for better UX

### Use `observeProfile(closeOnEose: false)` when:
- Displaying profiles that should update in real-time
- Building social features where profile changes matter
- Implementing live user status or presence features

### Use `fetchProfile` when:
- You need a simple boolean check (profile exists or not)
- Performing batch operations or data exports
- Working in non-UI contexts (background tasks, CLI)
- You specifically need to wait for the complete result

## Best Practices

1. **Cancel Tasks**: Always cancel the observation task when the view disappears
2. **Handle nil**: The stream may yield `nil` if no profile exists yet
3. **Error Handling**: Wrap iteration in do-catch for network error handling
4. **Shared State**: Consider using `@StateObject` or similar for profile data shared across views