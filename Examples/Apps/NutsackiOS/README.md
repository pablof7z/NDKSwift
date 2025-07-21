# Nutsack iOS

A modern Cashu ecash wallet for iOS that integrates seamlessly with Nostr, implementing NIP-60 (wallet backup) and NIP-61 (nutzaps).

## Features

### Core Wallet Features
- 🏦 **Multi-Wallet Support**: Manage multiple Cashu wallets backed up to Nostr
- ⚡ **Lightning Integration**: Mint ecash from Lightning invoices and melt back to Lightning
- 💸 **Send & Receive**: Share ecash tokens via QR codes or text
- 🔄 **Real-time Balance**: Live fiat conversion (USD, EUR, BTC)
- 📊 **Transaction History**: Track all your ecash movements

### Nostr Integration
- 🔑 **Nostr Authentication**: Login with nsec or create new Nostr account
- 💾 **NIP-60 Backup**: Automatic wallet backup to Nostr relays
- ⚡ **NIP-61 Nutzaps**: Zap other Nostr users with ecash
- 👥 **Contact Integration**: See your Nostr follows and zap them easily
- 🌐 **Multi-Relay Support**: Connect to multiple Nostr relays

### UI/UX Features
- 🎨 **Beautiful Dark Theme**: Inspired by macademia wallet's elegant design
- 📱 **Native iOS Feel**: Built with SwiftUI for smooth, native performance
- 🔍 **QR Code Scanner**: Scan ecash tokens and Lightning invoices
- 🎯 **Intuitive Navigation**: Tab-based interface with clear actions

## Architecture

The app is built using:
- **SwiftUI** for the UI layer
- **SwiftData** for local persistence
- **NDKSwift** for Nostr integration
- **CashuSwift** for Cashu protocol operations

### Key Components

1. **NostrManager**: Handles all Nostr operations including authentication, relay connections, and event publishing
2. **AppState**: Global app state including user preferences and active account
3. **Data Models**: SwiftData models for accounts, wallets, tokens, and transactions
4. **NIP-60 Integration**: Wallet events are published to Nostr for backup
5. **NIP-61 Implementation**: Nutzaps are created as Nostr events with embedded ecash tokens

## Building

1. Install Xcode 15 or later
2. Clone the repository
3. Open the project in Xcode
4. Build and run

```bash
cd Examples/NutsackiOS
swift build
```

## Future Enhancements

- [ ] Full CashuSwift integration for real token operations
- [ ] NIP-05 resolution for recipient lookup
- [ ] Custom relay management
- [ ] Mint discovery via NIP-38000 events
- [ ] P2PK (pay-to-public-key) support
- [ ] Multi-language support
- [ ] Backup/restore from seed phrase
- [ ] Push notifications for received payments
- [ ] Widget support for balance display

## Design Inspiration

The UI/UX is heavily inspired by the macademia wallet, incorporating:
- Gradient backgrounds and card-based layouts
- Clean typography and spacing
- Intuitive menu-based actions for send/receive
- Smooth animations and transitions
- Dark theme with orange accent colors

## Security Considerations

- Private keys are stored locally (should be encrypted in production)
- All Nostr communications use standard encryption
- Ecash tokens are validated before acceptance
- Mint trust is explicit and user-controlled

## Contributing

This is an example app demonstrating NDKSwift capabilities. Feel free to fork and enhance!