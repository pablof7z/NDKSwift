# NDKSwift Authentication Guide

This guide provides the standardized approach for handling authentication in NDKSwift applications.

## Core Concepts

### Authentication Components

1. **NDKAuthManager** - The central authentication manager
   - Manages sessions (login state)
   - Handles keychain persistence
   - Provides observable authentication state
   - Accessed via: `ndk.auth`

2. **NDKSession** - Represents an authenticated session
   - Contains user's pubkey
   - Stores signer type and security settings
   - Can be read-only (no signer) or read-write (with signer)

3. **NDKUser** - Represents any Nostr user
   - Just a wrapper around a pubkey
   - Not necessarily the authenticated user

4. **NDKSigner** - Handles event signing
   - Private key signer for local keys
   - Can be extended for remote signing (NIP-46)

## Standard Implementation Pattern

### 1. Basic Setup

```swift
@MainActor
@Observable
class AppModel {
    // NDK instance
    let ndk: NDK
    
    // Convenience computed properties
    var isAuthenticated: Bool { ndk.auth.isAuthenticated }
    var currentPubkey: String? { ndk.auth.activePubkey }
    var currentUser: NDKUser? { ndk.auth.currentUser }
    
    init() {
        // Setup NDK with cache
        let cache = try? NDKSQLiteCache()
        self.ndk = NDK(relayUrls: defaultRelays, cache: cache)
    }
    
    func initialize() async {
        // 1. Connect to relays
        await ndk.connect()
        
        // 2. Initialize auth (restores sessions)
        await ndk.auth.initialize()
        
        // 3. If authenticated, start session data
        if ndk.auth.isAuthenticated, let signer = ndk.auth.activeSigner {
            try? await ndk.startSession(signer: signer)
        }
    }
}
```

### 2. In Your Views

```swift
struct ContentView: View {
    @Environment(AppModel.self) var app
    
    var body: some View {
        if app.isAuthenticated {
            MainView()
        } else {
            LoginView()
        }
    }
}
```

### 3. Login Methods

```swift
// Login with existing private key
func login(nsec: String) async throws {
    let signer = try NDKPrivateKeySigner(nsec: nsec)
    _ = try await auth.addSession(signer, requiresBiometric: true)
    
    // Start NDK session
    if let ndk = ndk {
        try await ndk.startSession(signer: signer)
    }
}

// Create new account
func createAccount() async throws {
    let signer = try NDKPrivateKeySigner.generate()
    _ = try await auth.addSession(signer, requiresBiometric: true)
    
    // Start NDK session
    if let ndk = ndk {
        try await ndk.startSession(signer: signer)
    }
    
    // Publish initial profile
    let profile = NDKUserProfile(
        name: "New User",
        about: "Just joined Nostr!"
    )
    try await ndk!.publish(profile: profile)
}

// Logout
func logout() async {
    auth.logout()
    // Note: This only clears active session, saved sessions remain
}

// Complete logout (remove all saved sessions)
func completeLogout() async throws {
    try await auth.removeAllSessions()
}
```

### 4. Observing Current User's Profile

```swift
struct ProfileView: View {
    @Environment(AppModel.self) var app
    @State private var profile: NDKUserProfile?
    
    var body: some View {
        VStack {
            if let profile = profile {
                Text(profile.name ?? "Anonymous")
                Text(profile.about ?? "")
            }
        }
        .task {
            guard let user = app.currentUser else { return }
            
            // Observe profile updates
            for await profile in await app.ndk!.profileManager.observe(for: user.pubkey) {
                self.profile = profile
            }
        }
    }
}
```

## Key Properties Reference

### NDKAuthManager Properties

- `isAuthenticated: Bool` - Whether user is logged in
- `activePubkey: String?` - Current user's public key
- `currentUser: NDKUser?` - Current user as NDKUser instance
- `activeSigner: NDKSigner?` - Current signer (for advanced use)
- `activeSession: NDKSession?` - Current session details
- `availableSessions: [NDKSession]` - All saved sessions (multi-account)
- `isLoading: Bool` - Whether auth state is being loaded

### NDKSession Properties

- `pubkey: String` - User's public key
- `isReadOnly: Bool` - Whether this is a read-only session
- `canSign: Bool` - Whether this session can sign events
- `profileName: String?` - Cached display name
- `avatarURL: URL?` - Cached avatar URL

## Best Practices

1. **Access auth through NDK instance** - Use `ndk.auth` instead of creating your own
2. **Check isAuthenticated before using signer** - Not all sessions can sign
3. **Use computed properties** - Reference auth state through your app model
4. **Handle biometric failures gracefully** - Sessions may require Face ID/Touch ID
5. **Don't store pubkeys separately** - Use `ndk.auth.activePubkey` or `ndk.auth.currentUser`

## Common Patterns

### Multi-Account Support

```swift
// Show account switcher
struct AccountSwitcher: View {
    @Environment(AppModel.self) var app
    
    var body: some View {
        List(app.auth.availableSessions) { session in
            Button(action: {
                Task {
                    try await app.auth.switchToSession(session)
                    if let signer = app.auth.activeSigner {
                        try await app.ndk!.startSession(signer: signer)
                    }
                }
            }) {
                HStack {
                    Text(session.profileName ?? session.shortIdentifier)
                    if session.isActive {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}
```

### Read-Only Mode

```swift
// Browse as a specific user without logging in
func browseAsUser(npub: String) async throws {
    let pubkey = try Bech32.decode(npub).data.hexString
    let user = NDKUser(pubkey: pubkey)
    
    // Create read-only session
    _ = try await auth.addSession(user: user)
}
```

### Checking Authentication State

```swift
// In any view
struct SomeView: View {
    @Environment(AppModel.self) var app
    
    var body: some View {
        Group {
            if app.isAuthenticated {
                Text("Logged in as: \(app.currentUser?.npub ?? "")")
            } else {
                Text("Not logged in")
            }
        }
    }
}
```

## Migration from Legacy Patterns

If your app was using custom authentication:

1. Replace custom auth state with `ndk.auth`
2. Remove redundant pubkey storage
3. Use `ndk.auth.currentUser` instead of creating NDKUser instances
4. Let NDKAuthManager handle session persistence

## Reacting to Authentication Changes

### SwiftUI (Automatic with @Observable)

Since `NDKAuthManager` uses `@Observable`, SwiftUI views automatically update when authentication state changes:

```swift
struct ContentView: View {
    @Environment(AppModel.self) var app
    
    // This view automatically re-renders when isAuthenticated changes
    var body: some View {
        if app.ndk.auth.isAuthenticated {
            MainView()
        } else {
            LoginView()
        }
    }
}

// Or with the app model pattern:
struct ContentView: View {
    @Environment(AppModel.self) var app
    
    var body: some View {
        if app.auth.isAuthenticated {
            MainView()
                .environment(\.currentUser, app.auth.currentUser)
        } else {
            LoginView()
        }
    }
}
```

### Non-SwiftUI Contexts

For code outside of SwiftUI views, use `withObservationTracking`:

```swift
@MainActor
class SomeService {
    let ndk: NDK
    private var observationTask: Task<Void, Never>?
    
    init(ndk: NDK) {
        self.ndk = ndk
        startObserving()
    }
    
    func startObserving() {
        observationTask = Task {
            while !Task.isCancelled {
                _ = withObservationTracking {
                    // Access the properties you want to observe
                    _ = ndk.auth.isAuthenticated
                } onChange: {
                    // This runs when any observed property changes
                    Task { @MainActor in
                        self.handleAuthChange()
                    }
                }
                
                // Small delay to prevent busy loop
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
    }
    
    func handleAuthChange() {
        if auth.isAuthenticated {
            print("User logged in: \(auth.currentUser?.npub ?? "")")
            // Start services
        } else {
            print("User logged out")
            // Stop services
        }
    }
    
    deinit {
        observationTask?.cancel()
    }
}
```

### Observing Multiple Properties

```swift
// Observe multiple auth properties at once
_ = withObservationTracking {
    _ = auth.isAuthenticated
    _ = auth.sessionState
    _ = auth.currentUser
    _ = auth.availableSessions.count
} onChange: {
    // This runs when ANY of the observed properties change
    print("Auth state updated:")
    print("- Authenticated: \(auth.isAuthenticated)")
    print("- State: \(auth.sessionState)")
    print("- Sessions: \(auth.availableSessions.count)")
}
```

## Troubleshooting

### Session not persisting across app launches
- Ensure you call `auth.setNDK()` early in app lifecycle
- Check that keychain access is properly configured in your app

### Biometric authentication failing
- Check `auth.biometricAuthAvailable` before requiring biometrics
- Provide fallback options for devices without biometrics

### Multiple sessions showing as active
- Only one session can be active at a time
- Use `auth.switchToSession()` to properly switch between accounts

### Auth state not updating in views
- Ensure you're accessing auth properties in the view body
- For non-SwiftUI code, use `withObservationTracking`
- Check that you're not storing auth state in @State variables (use computed properties instead)