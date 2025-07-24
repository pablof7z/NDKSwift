# AMBULANDO

A beautiful iOS app for voice-based conversations on Nostr. Share wisdom through voice messages with a focus on meaningful interactions.

## Features

- 🎙️ **Voice Messages**: Record and share up to 60-second voice messages
- 🔊 **Audio Playback**: Smooth playback with waveform visualization
- 🌐 **Web of Trust**: Content sorted by your social graph proximity
- ⚡ **Negentropy Sync**: Efficient syncing of follow lists
- 🎨 **Beautiful Animations**: Carefully crafted UI with attention to detail
- 🔐 **Secure Login**: Support for nsec private key login (NIP-46 coming soon)

## Architecture

Built with:
- SwiftUI for modern, declarative UI
- NDKSwift for Nostr protocol implementation
- AVFoundation for audio recording and playback
- Swift Concurrency for efficient network operations

## Voice Event Types

- **Kind 1222**: Root voice messages
- **Kind 1244**: Voice message replies

## Building

1. Generate Xcode project:
```bash
cd Examples/Apps/Ambulando
xcodegen generate
```

2. Open in Xcode:
```bash
open Ambulando.xcodeproj
```

3. Build and run on simulator or device

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Status

This is an example app demonstrating NDKSwift capabilities with a focus on audio content and beautiful UI/UX.