# Profile Management in NDKSwift

NDKSwift provides a dedicated `NDKProfileManager` class for efficient profile fetching with built-in caching and real-time updates.

## Overview

The `NDKProfileManager` provides:
- **In-memory LRU cache** for instant profile access
- **Automatic synchronization** with persistent storage
- **Real-time updates** when profiles change
- **Resource efficiency** through shared subscriptions
- **Progressive loading** for responsive UIs

## Basic Usage

### Accessing the Profile Manager

```swift
import NDKSwift

// The profile manager is automatically available through NDK
let profileManager = ndk.profileManager

// Profile manager is created with the NDK instance and manages profile metadata
```

### Fetching Profiles

#### One-time Profile Fetch

For displaying profiles in a list or feed where you don't need real-time updates:

```swift
// Returns cached data immediately if available, then fetches fresh data
for await profile in await profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
    if let profile = profile {
        // Use profile data
        displayName = profile.displayName ?? profile.name ?? "Anonymous"
        avatarURL = profile.picture
    }
    break  // Exit after first value if you don't need updates
}
```

#### Real-time Profile Updates

For profile pages where you want to show changes as they happen:

```swift
// maxAge: 0 keeps the subscription open for real-time updates
for await profile in await profileManager.observe(for: pubkey, maxAge: 0) {
    if let profile = profile {
        // Update UI with latest profile data
        updateProfileView(with: profile)
    }
    // Don't break - continue listening for updates
}
```

### SwiftUI Integration

```swift
struct ProfileView: View {
    let pubkey: String
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    @EnvironmentObject private var profileManager: NDKProfileManager
    
    var body: some View {
        VStack {
            if let profile = profile {
                AsyncImage(url: URL(string: profile.picture ?? ""))
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                
                Text(profile.displayName ?? profile.name ?? "Anonymous")
                    .font(.title)
                
                Text(profile.about ?? "")
                    .font(.body)
            } else {
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
        profileTask = Task {
            // Use hour cache for feed views, 0 for profile pages
            let maxAge = isProfilePage ? 0 : TimeConstants.hour
            
            for await profile in await profileManager.observe(for: pubkey, maxAge: maxAge) {
                await MainActor.run {
                    if let profile = profile {
                        self.profile = profile
                    }
                }
                
                // Only break if we don't need real-time updates
                if maxAge > 0 {
                    break
                }
            }
        }
    }
}
```

### Batch Profile Loading

For efficiently loading multiple profiles:

```swift
// Load multiple profiles at once (e.g., for a contact list)
let pubkeys = ["pubkey1", "pubkey2", "pubkey3"]

// Option 1: Using loadProfiles for immediate cache check
let cachedProfiles = await profileManager.loadProfiles(for: pubkeys)
for (pubkey, profile) in cachedProfiles {
    // Use cached profiles immediately
}

// Option 2: Using concurrent tasks for cache + network
await withTaskGroup(of: Void.self) { group in
    for pubkey in pubkeys {
        group.addTask {
            for await profile in await profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
                await updateUI(pubkey: pubkey, profile: profile)
                break  // Only need first value
            }
        }
    }
}
```

## Understanding maxAge

The `maxAge` parameter controls caching and subscription behavior:

- **`maxAge: 0`** - Always keep subscription open for real-time updates
- **`maxAge: > 0`** - Use cache if data is newer than maxAge, close subscription after initial fetch
- **`maxAge: TimeConstants.hour`** - Common for feed views (1 hour cache)
- **`maxAge: TimeConstants.day`** - For less critical profile data

## Performance Tips

### 1. Use Appropriate maxAge Values

```swift
// Feed/List views - use cache, don't need real-time
maxAge: TimeConstants.hour

// Profile pages - want real-time updates
maxAge: 0

// Background operations - use longer cache
maxAge: TimeConstants.day
```

### 2. Cancel Tasks When Not Needed

```swift
class ProfileViewModel: ObservableObject {
    private var profileTask: Task<Void, Never>?
    
    func loadProfile(pubkey: String) {
        // Cancel previous task
        profileTask?.cancel()
        
        profileTask = Task {
            for await profile in await profileManager.observe(for: pubkey) {
                // Update UI
            }
        }
    }
    
    deinit {
        profileTask?.cancel()
    }
}
```

### 3. Share Profile Manager Instance

```swift
// In your app's main structure
@StateObject private var profileManager = NDKProfileManager(ndk: ndk)

// Pass it through environment
ContentView()
    .environmentObject(profileManager)
```

## Common Patterns

### Profile Picture with Fallback

```swift
struct ProfilePicture: View {
    let pubkey: String
    @State private var profile: NDKUserProfile?
    @EnvironmentObject private var profileManager: NDKProfileManager
    
    var body: some View {
        Group {
            if let picture = profile?.picture, let url = URL(string: picture) {
                AsyncImage(url: url)
            } else {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .task {
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
                if let profile = profile {
                    self.profile = profile
                }
                break
            }
        }
    }
}
```

### Display Name with Loading State

```swift
struct DisplayName: View {
    let pubkey: String
    @State private var displayName: String = "Loading..."
    @EnvironmentObject private var profileManager: NDKProfileManager
    
    var body: some View {
        Text(displayName)
            .task {
                for await profile in await profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
                    displayName = profile?.displayName 
                        ?? profile?.name 
                        ?? String(pubkey.prefix(8))
                    break
                }
            }
    }
}
```

## Migration from Direct Event Fetching

If you're currently fetching profiles manually:

### Before (Manual Approach)
```swift
// Don't do this
let profileSource = ndk.observe(
    filter: NDKFilter(
        authors: [pubkey],
        kinds: [0]
    ),
    maxAge: 3600
)

for await event in profileSource.events {
    if let profileData = event.content.data(using: .utf8),
       let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
        // Use profile
    }
}
```

### After (Using ProfileManager)
```swift
// Do this instead
for await profile in await profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
    if let profile = profile {
        // Use profile directly - no manual JSON decoding needed
    }
    break  // If you only need one value
}
```

## Benefits of Using NDKProfileManager

1. **No Manual JSON Decoding** - Profiles are automatically parsed
2. **In-Memory Caching** - Previously loaded profiles are served instantly
3. **Automatic Updates** - Profile changes are reflected in real-time
4. **Resource Efficient** - Shared subscriptions for the same profiles
5. **Progressive Loading** - Show cached data while fetching updates

## Error Handling

```swift
do {
    for await profile in await profileManager.observe(for: pubkey) {
        // Handle profile
    }
} catch {
    // Handle network or decoding errors
    print("Failed to load profile: \(error)")
}
```

## Cache Management

```swift
// Clear all cached profiles
await profileManager.clearCache()

// Get cache statistics
let stats = await profileManager.getCacheStats()
print("Cache size: \(stats.size)")
```