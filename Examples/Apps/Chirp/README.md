# Chirp

A feature-rich Nostr client for iOS built with SwiftUI and [NDKSwift](https://github.com/pablof7z/NDKSwift).

**iOS 17.0+** | **Swift 6.0** | **SwiftUI**

## Features

### Core
- **Feed** with follow-based timeline, follow packs (NIP-39089/39092), and relay feeds
- **Explore** with full-text search across notes, profiles, and hashtags
- **Profiles** with posts, replies, and media tabs
- **Composer** with multi-image support, mention autocomplete, and draft persistence

### Authentication
- Private key login (nsec/hex)
- NIP-46 remote signer (bunker connections)
- Read-only mode (npub)
- Multi-account support with keychain storage

### Wallet
- **NIP-60 Cashu** ecash wallet (self-custodial)
- **NIP-47 Nostr Wallet Connect** (external wallet integration)
- Send/receive with QR scanning
- Transaction history and mint browser

### Relay Management
- Configurable app relays
- Discovery relays (purplepag.es)
- User relays (NIP-65)
- Search relays (relay.nostr.band)
- Live connection monitoring and stats

### Developer Tools
- NostrDB inspector (event counts, storage)
- Event and cache inspector
- Relay dashboard with live metrics
- Subscription monitor
- Outbox stats and log viewer

## Architecture

Feature-based organization with `@Observable` state management:

```
ChirpFeature/
├── App/           Core state, login, navigation
├── Composer/      Post creation
├── Feed/          Home feed, threading
├── Explore/       Discovery, search, packs
├── Profile/       User profiles
├── Wallet/        Cashu + NWC payments
├── Settings/      Configuration, relays
├── DevTools/      Debugging utilities
└── DesignSystem/  UI components and theming
```

### Dependencies

All from the NDKSwift monorepo:

- `NDKSwiftCore` -- core Nostr protocol
- `NDKSwiftUI` -- pre-built UI components
- `NDKSwiftNostrDB` -- event caching with NostrDB
- `NDKSwiftCashu` -- NIP-60 Cashu support

## Building

Open `Chirp.xcodeproj` in Xcode 15+ or generate the project from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd Examples/Apps/Chirp
xcodegen generate
```

Requires a development team for code signing.

## URL Schemes

```
chirp://nip46/      Remote signer callbacks
chirp://nwc?value=  Wallet Connect callbacks
```
