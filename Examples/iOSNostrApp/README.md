# iOS Nostr App Example

A simple iOS app demonstrating Nostr account creation and message publishing using NDKSwift.

## Features

- Create a new Nostr account (generates private/public key pair)
- Display the user's nsec (private key) and npub (public key)
- Publish text messages (kind:1) to Nostr
- Connects to wss://relay.primal.net

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open the project in Xcode:
   ```bash
   cd Examples
   open iOSNostrApp.xcodeproj
   ```

2. Build and run the app on a simulator or device

## Usage

1. Launch the app
2. Tap "Create Account" to generate a new Nostr identity
3. Your private key (nsec) will be displayed - keep this secure!
4. Enter a message and tap "Publish to Nostr" to send it to the relay

## Security Note

This is a demo app. In production:
- Never display private keys in plain text
- Use secure storage (Keychain) for private keys
- Implement proper key backup mechanisms