# Posta - A Telegram-like iOS App

Posta is a basic iOS app that demonstrates how to build a Telegram-like interface using NDKSwift for Nostr protocol integration.

## Features

- **Authentication System**: Login with existing private key or register a new account
- **Clean SwiftUI Interface**: Modern iOS app design with tab navigation
- **NDKSwift Integration**: Ready for Nostr protocol communication
- **Home Screen Shell**: Prepared for kind:1 note fetching and display

## Architecture

The app follows clean architecture principles:

- `PostaApp.swift` - Main app entry point
- `AuthManager.swift` - Handles authentication and NDK instance management
- `AuthView.swift` - Login/Register interface
- `ContentView.swift` - Main app coordinator
- `HomeView.swift` - Home screen (ready for posts implementation)

## Building

1. Make sure you have Xcode installed
2. Generate the Xcode project:
   ```bash
   cd Examples/Posta
   xcodegen
   ```
3. Open `Posta.xcodeproj` in Xcode
4. Build and run on iOS Simulator

## Next Steps

The home screen is intentionally left empty. You can extend it to:

1. Fetch kind:1 notes from Nostr relays
2. Filter out notes with "e" tags (to show only root posts)
3. Display author avatars and message previews
4. Implement Telegram-like chat interface

## Dependencies

- **NDKSwift**: Nostr Development Kit for Swift
- **iOS 17.0+**: Minimum deployment target
- **SwiftUI**: Modern UI framework