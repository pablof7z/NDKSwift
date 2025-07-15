# NDKSwift Authentication Guide

This guide covers the authentication system in NDKSwift, including session management, multi-account support, and biometric authentication.

## Overview

NDKSwift provides a comprehensive authentication system built around two main components:

- **NDKAuthManager**: The core authentication manager that handles session management, secure storage, and biometric authentication
- **NDKAuthView**: A SwiftUI view that provides a complete authentication flow UI

## Key Features

- 🔐 **Secure Session Management**: Sessions are stored securely in the iOS Keychain
- 👤 **Multi-Account Support**: Manage multiple Nostr accounts with easy switching
- 🔑 **Multiple Signer Types**: Support for private key signers and NIP-46 remote signers
- 📱 **Biometric Authentication**: Face ID/Touch ID protection for sensitive accounts
- 🔄 **Automatic Session Restoration**: Sessions persist across app launches
- 🎨 **Customizable UI**: Provide your own authentication UI or use the defaults

## Quick Start

### Basic Implementation

```swift
import SwiftUI
import NDKSwift

@main
struct MyApp: App {
    @State private var authManager = NDKAuthManager.shared
    @State private var ndk = NDK(relayUrls: ["wss://relay.damus.io"])
    
    var body: some Scene {
        WindowGroup {
            NDKAuthView(authManager: authManager, ndk: ndk) {
                // Your authenticated content
                MainAppView()
            } authenticationContent: {
                // Your custom login UI
                LoginView()
            }
        }
    }
}
```

### Using Default Authentication UI

If you don't need custom authentication UI, NDKAuthView provides a default:

```swift
NDKAuthView(authManager: authManager, ndk: ndk) {
    // Your authenticated content
    MainAppView()
}
// The default UI includes session selection and "Add Account" functionality
```

## NDKAuthManager

The authentication manager is a singleton that manages all authentication state:

### Accessing the Manager

```swift
// Get the shared instance
let authManager = NDKAuthManager.shared

// Check authentication status
if authManager.isAuthenticated {
    // User is logged in
}

// Access current session
if let session = authManager.activeSession {
    print("Logged in as: \(session.displayName)")
}
```

### Creating Sessions

#### Create New Account

```swift
// Generate a new private key
let signer = try NDKPrivateKeySigner.generate()

// Create session
let session = try await authManager.createSession(
    with: signer,
    displayName: "Alice",
    requiresBiometric: true,  // Enable Face ID/Touch ID
    isHardwareBacked: false
)

// The session is automatically activated
```

#### Import Existing Account

```swift
// From nsec
let signer = try NDKPrivateKeySigner(nsec: "nsec1...")

// From hex private key
let signer = try NDKPrivateKeySigner(privateKey: "hex_private_key")

// Create session
let session = try await authManager.createSession(
    with: signer,
    displayName: displayName
)
```

### Managing Sessions

#### Switch Between Accounts

```swift
// Get available sessions
let sessions = authManager.availableSessions

// Switch to a different session
try await authManager.switchToSession(sessions[1])
```

#### Update Session Profile

```swift
// Update the profile for the active session
let profile = NDKUserProfile(
    name: "Alice",
    displayName: "Alice in Nostrland",
    about: "Building cool stuff",
    picture: "https://example.com/avatar.jpg"
)

try await authManager.updateActiveSessionProfile(profile)
```

#### Delete Session

```swift
// Remove a session
try await authManager.deleteSession(session)

// Or logout and clear active session
authManager.logout()
```

### Authentication States

The manager tracks authentication state:

```swift
switch authManager.authenticationState {
case .unauthenticated:
    // Show login UI
case .authenticating:
    // Show loading indicator
case .authenticated:
    // Show main app
case .biometricRequired:
    // Prompt for Face ID/Touch ID
case .authenticationFailed(let error):
    // Show error message
case .sessionExpired:
    // Session needs refresh
}
```

## NDKAuthView

NDKAuthView provides a complete authentication flow UI that automatically handles all authentication states.

### Custom Authentication Content

```swift
struct ContentView: View {
    @State private var authManager = NDKAuthManager.shared
    
    var body: some View {
        NDKAuthView(authManager: authManager) {
            // Authenticated content
            MainAppView()
        } authenticationContent: {
            // Your custom login/signup UI
            CustomLoginView()
        }
    }
}
```

### Authentication Flow States

NDKAuthView automatically handles these states:

1. **Session Selection**: When multiple accounts exist, shows account picker
2. **Biometric Prompt**: Requests Face ID/Touch ID when required
3. **Loading States**: Shows progress during authentication
4. **Error Handling**: Displays authentication errors with retry options
5. **Session Expired**: Prompts to re-authenticate

## Building Custom Authentication UI

Here's an example of building your own authentication UI:

```swift
struct CustomLoginView: View {
    @Environment(NDKAuthManager.self) private var authManager
    @State private var nsecInput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to MyApp")
                .font(.largeTitle)
            
            TextField("Enter your nsec...", text: $nsecInput)
                .textFieldStyle(.roundedBorder)
            
            Button("Login") {
                Task {
                    do {
                        let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                        _ = try await authManager.createSession(
                            with: signer,
                            displayName: "Nostr User"
                        )
                    } catch {
                        // Handle error
                    }
                }
            }
            
            Button("Create New Account") {
                Task {
                    do {
                        let signer = try NDKPrivateKeySigner.generate()
                        _ = try await authManager.createSession(
                            with: signer,
                            displayName: "New User"
                        )
                    } catch {
                        // Handle error
                    }
                }
            }
        }
        .padding()
    }
}
```

## Biometric Authentication

### Enabling Biometric Protection

When creating a session, enable biometric authentication:

```swift
let session = try await authManager.createSession(
    with: signer,
    displayName: "Alice",
    requiresBiometric: true  // Enable Face ID/Touch ID
)
```

### Checking Biometric Availability

```swift
if authManager.biometricAuthAvailable {
    switch authManager.biometricType {
    case .faceID:
        print("Face ID available")
    case .touchID:
        print("Touch ID available")
    default:
        print("No biometric authentication")
    }
}
```

## Security Best Practices

1. **Always Enable Biometric Authentication** for accounts with sensitive data
2. **Use Hardware-Backed Keys** when available (future support)
3. **Validate Sessions** on app launch to ensure they're still valid
4. **Clear Sessions** on logout to prevent unauthorized access
5. **Handle Session Expiry** gracefully with re-authentication prompts

## Advanced Usage

### Custom Session Storage

While NDKAuthManager uses Keychain by default, you can implement custom storage:

```swift
// Future API - not yet available
authManager.setCustomStorage(MyCustomStorage())
```

### Remote Signer Support (NIP-46)

```swift
// Create a remote signer
let bunkerSigner = NDKBunkerSigner(
    remotePubkey: "bunker_service_pubkey",
    relayUrls: ["wss://relay.nsecbunker.com"]
)

// Create session with remote signer
let session = try await authManager.createSession(
    with: bunkerSigner,
    displayName: "Alice"
)
```

### Handling Multiple NDK Instances

```swift
// Set NDK instance on auth manager
authManager.setNDK(myNDKInstance)

// Auth manager will automatically configure the signer
```

## Troubleshooting

### Session Not Persisting

If sessions aren't persisting across app launches:

1. Ensure you're not creating a new `NDKAuthManager` instance each time
2. Use the shared instance: `NDKAuthManager.shared`
3. Check for Keychain access errors in logs

### Biometric Authentication Fails

1. Check if biometric authentication is available on the device
2. Ensure the app has Face ID/Touch ID permissions in Info.plist
3. Handle biometric errors gracefully:

```swift
if case .authenticationFailed(let error) = authManager.authenticationState {
    // Check if it's a biometric error
    if (error as NSError).code == LAError.biometryNotAvailable.rawValue {
        // Biometrics not available
    }
}
```

### Account Switching Issues

1. Ensure you're using `switchToSession()` instead of creating new sessions
2. Check for profile data loading errors
3. Verify the session hasn't expired

## Example: Complete Authentication Flow

Here's a complete example showing account creation, login, and session management:

```swift
import SwiftUI
import NDKSwift

@main
struct NostrApp: App {
    @State private var authManager = NDKAuthManager.shared
    @State private var ndk = NDK(relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.primal.net"
    ])
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .onAppear {
                    authManager.setNDK(ndk)
                }
        }
    }
}

struct ContentView: View {
    @Environment(NDKAuthManager.self) private var authManager
    
    var body: some View {
        NDKAuthView(authManager: authManager) {
            // Authenticated content
            AuthenticatedView()
        } authenticationContent: {
            // Custom authentication UI
            AuthenticationView()
        }
    }
}

struct AuthenticatedView: View {
    @Environment(NDKAuthManager.self) private var authManager
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
            
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct AuthenticationView: View {
    @State private var showCreateAccount = false
    @State private var showImportAccount = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Welcome to Nostr")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    Button("Create New Account") {
                        showCreateAccount = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Import Existing Account") {
                        showImportAccount = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationDestination(isPresented: $showCreateAccount) {
                CreateAccountView()
            }
            .navigationDestination(isPresented: $showImportAccount) {
                ImportAccountView()
            }
        }
    }
}
```

## Migration Guide

If you're migrating from a custom authentication system:

1. **Migrate User Data**: Convert existing user data to NDKSession format
2. **Update UI**: Replace custom auth UI with NDKAuthView
3. **Handle Legacy Sessions**: Provide migration path for old session formats
4. **Test Thoroughly**: Ensure biometric authentication works as expected

## Next Steps

- Learn about [NDK Signers](API_REFERENCE.md#signers) for different authentication methods
- Explore [Profile Management](API_REFERENCE.md#ndkuser) for user profiles
- See [Examples](EXAMPLES.md) for more authentication patterns