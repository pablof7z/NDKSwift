# NDKSwift Examples

This directory contains examples demonstrating how to use NDKSwift.

## Directory Structure

- **GettingStarted/**: Step-by-step examples for beginners
  - `01-ConnectToRelay.swift`: Basic relay connection
  - `02-PublishEvent.swift`: Publishing your first event
  - `03-Subscribe.swift`: Subscribing to events
  - `04-UserProfile.swift`: Working with user profiles
  - `05-EncryptedMessages.swift`: Sending encrypted direct messages

- **Features/**: Advanced feature demonstrations
  - Various demos showing specific NDKSwift capabilities
  - Wallet integration examples
  - Protocol implementations

- **Apps/**: Full example applications
  - `NutsackiOS/`: Complete iOS wallet application
  - `Posta/`: Social client iOS application

## Running Examples

### Standalone Scripts
```bash
# Run directly without compilation
swift Examples/GettingStarted/01-ConnectToRelay.swift
```

### Compiled Examples
```bash
# From the Examples directory
cd Examples
swift run RelayCollectionDemo
```

### iOS Apps
Open the `.xcodeproj` file in Xcode:
```bash
open Examples/Apps/NutsackiOS/NutsackiOS.xcodeproj
```

## Learning Path

1. Start with `GettingStarted` examples in order
2. Explore `Features` for specific use cases
3. Study the full apps for complete implementations