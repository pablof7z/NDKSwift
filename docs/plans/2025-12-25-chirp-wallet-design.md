# Chirp Wallet Feature Design

## Overview

Add a wallet feature to Chirp reference client supporting NIP-60 (Cashu) and NIP-47 (Nostr Wallet Connect) with a sleek, flat CashApp-style UI and developer tools for wallet internals.

## Architecture

### Wallet Type Switching

```swift
enum WalletType: String, CaseIterable {
    case cashu   // NIP-60 Cashu wallet
    case nwc     // NIP-47 Nostr Wallet Connect
}
```

Users can switch between wallet types in Settings. Each type maintains independent connection/configuration state.

### State Management

**ChirpState** gets extended with:
- `walletType: WalletType` - Current wallet type (persisted to UserDefaults)
- `cashuWallet: NIP60Wallet?` - NIP-60 wallet instance (when using cashu)
- `nwcWallet: NDKNWCWallet?` - NIP-47 wallet instance (when using nwc)
- `nwcConnectionURI: String?` - Stored NWC connection (persisted to Keychain)

### File Structure

```
ChirpFeature/
├── Wallet/
│   ├── WalletView.swift              # Main wallet tab - routes to appropriate view
│   ├── WalletState.swift             # Wallet-specific state management
│   ├── Components/
│   │   ├── BalanceDisplay.swift      # Hero balance with animated updates
│   │   ├── ActionBar.swift           # Send/Receive/Scan buttons
│   │   └── TransactionRow.swift      # Transaction list item
│   ├── Cashu/
│   │   ├── CashuWalletView.swift     # NIP-60 wallet main view
│   │   ├── CashuSetupView.swift      # Cashu wallet setup flow
│   │   ├── MintBrowserView.swift     # NIP-87 mint discovery
│   │   └── MintRowView.swift         # Mint list item
│   ├── NWC/
│   │   ├── NWCWalletView.swift       # NIP-47 wallet main view
│   │   └── NWCConnectView.swift      # NWC pairing flow
│   ├── Send/
│   │   ├── SendView.swift            # Send flow
│   │   └── QRScannerView.swift       # QR code scanning
│   ├── Receive/
│   │   └── ReceiveView.swift         # Receive/deposit flow
│   └── DevTools/
│       └── WalletDevToolsView.swift  # Developer insights
├── Settings/
│   └── WalletSettingsView.swift      # Wallet type switching
```

## UI Design

### Main Wallet View

```
┌─────────────────────────────────────┐
│                                     │
│              ₿ 21,000               │  <- Hero balance (large, centered)
│               sats                  │
│         ≈ $21.00 USD               │  <- Optional fiat conversion
│                                     │
├─────────────────────────────────────┤
│                                     │
│   [Receive]    [Send]    [Scan]    │  <- Action bar (horizontal)
│                                     │
├─────────────────────────────────────┤
│  Transactions                       │
│  ─────────────────────────────────  │
│  ↓ Received from @alice   +500     │  <- Flat list, no cards
│  ↑ Sent to invoice        -1000    │
│  ↓ Nutzap from @bob       +100     │
│  ↓ Lightning deposit      +5000    │
│                                     │
└─────────────────────────────────────┘
```

### Design Principles

1. **Flat design** - No card shadows, subtle separators only
2. **Hero balance** - Large centered number, dominates the view
3. **Horizontal actions** - Send/Receive/Scan in a row
4. **Minimal chrome** - Let content breathe
5. **Monochrome with accent** - System colors, green for receive, red for send

### Cashu Setup Flow

1. **Welcome** - Explain what a Cashu wallet is
2. **Mint Selection** - Browse mints via NIP-87 or enter custom URL
3. **Confirm** - Show selected mints, create wallet

### NWC Connect Flow

1. **Scan/Paste** - QR code or paste connection URI
2. **Connecting** - Show connection progress
3. **Ready** - Show wallet info and balance

## Data Flow

### Cashu Wallet

```
User action → WalletState → NIP60Wallet (actor)
                                ↓
                        proofStateManager
                                ↓
                        wallet.events stream
                                ↓
                        WalletState updates
                                ↓
                        SwiftUI re-renders
```

### NWC Wallet

```
User action → WalletState → NDKNWCWallet (actor)
                                ↓
                        NWC request/response
                                ↓
                        WalletState updates
                                ↓
                        SwiftUI re-renders
```

## Developer Tools

The wallet dev tools view shows:

1. **Wallet State**
   - Current wallet type
   - Connection status
   - Balance breakdown

2. **Cashu Internals** (when using Cashu)
   - Configured mints with balances
   - Proof state (available/pending/spent counts)
   - Token events (7375) list
   - Quote events (7374) list
   - P2PK key info

3. **NWC Internals** (when using NWC)
   - Connection URI (masked)
   - Wallet info (supported methods)
   - Connected relays
   - Recent requests/responses

4. **Event Log**
   - Real-time wallet events stream
   - Balance changes
   - Transaction updates

## Implementation Notes

### Direct NDK Usage

Use NDK directly - no wrapper services:

```swift
// Cashu - use NIP60Wallet directly
let wallet = try NIP60Wallet(ndk: state.ndk)
try await wallet.load()

// NWC - use NDKNWCWallet directly
let wallet = try await NDKNWCWallet(ndk: state.ndk, connectionURI: uri)
try await wallet.connect()
```

### Keychain Storage

NWC connection URI stored in Keychain:
- Service: `com.chirp.nwc`
- Account: user's pubkey

### Transaction History

For Cashu: Use `wallet.getTransactionHistory()` from NIP60Wallet
For NWC: Use `wallet.listTransactions()` from NDKNWCWallet

### Mint Discovery (NIP-87)

Query for mint announcements (kind 38172) and recommendations (kind 38000):

```swift
// Announcements
NDKFilter(kinds: [38172], limit: 100)

// Recommendations
NDKFilter(kinds: [38000], tags: ["k": ["38172"]])
```

Score mints by recommendation count, filter to mainnet only.
