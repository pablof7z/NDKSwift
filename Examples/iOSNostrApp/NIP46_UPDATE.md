# iOS Nostr App - NIP-46 Bunker Support Update

## Overview

The iOS Nostr App has been updated to support NIP-46 remote signing via bunker:// URLs. Users can now choose between creating a local account or logging in with a remote bunker.

## Changes Made

### 1. ContentView.swift
- Added bunker login UI with a dedicated button
- Added a sheet for entering bunker:// URLs
- Added auth URL alert for bunker authorization
- Updated account info section to show bunker connection status
- Disabled private key display when connected via bunker

### 2. NostrViewModel.swift
- Added NIP-46 related properties:
  - `isConnectedViaBunker`: Tracks if user is connected via bunker
  - `isBunkerConnecting`: Shows connection progress
  - `showingAuthUrl` & `authUrl`: For auth URL handling
- Added `connectWithBunker(_:)` method for bunker connections
- Added support for both NDKSigner protocol and NDKBunkerSigner
- Added Combine publisher handling for auth URLs

## Usage

### For Users

1. **Local Account Creation** (existing flow):
   - Tap "Create Account"
   - Save the displayed nsec securely
   - Start publishing messages

2. **Bunker Login** (new):
   - Tap "Login with Bunker"
   - Paste your bunker:// connection string
   - Example: `bunker://pubkey?relay=wss://relay.nsec.app&secret=abc123`
   - Tap "Connect"
   - If authorization is required, open the provided URL
   - Once connected, you can publish messages via remote signing

### For Developers

To test with the provided bunker connection string:

```swift
let testBunker = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"
```

The app will:
1. Parse the bunker URL
2. Connect to the specified relay
3. Establish encrypted communication with the bunker
4. Handle authorization if required
5. Use the bunker for all signing operations

## Features

- ✅ Bunker URL parsing and connection
- ✅ Auth URL handling with browser opening
- ✅ Remote event signing
- ✅ UI updates showing bunker connection status
- ✅ Seamless integration with existing NDK architecture

## Security Notes

- Private keys never leave the bunker when using NIP-46
- All communication is encrypted (NIP-04/NIP-44)
- The "Show Private Key" button is hidden when using bunker
- Auth URLs should be opened in a trusted browser

## Demo

A standalone demo (`iOSBunkerDemo.swift`) is also provided that shows a minimal implementation of NIP-46 bunker support in a SwiftUI app.

## Building

The iOS app can be built using Xcode:
1. Open `iOSNostrApp.xcodeproj`
2. Select a simulator or device
3. Build and run

The app requires iOS 15.0+ and includes all necessary NDKSwift dependencies.