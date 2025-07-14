# CLI-Nutsack

A command-line NIP-60 Cashu wallet calculator built with NDKSwift.

## Features

- ⚡ Full NIP-60 wallet implementation
- 💰 Balance tracking across multiple mints
- 🏦 Mint management (add/remove/view)
- 📤 Send ecash via nutzaps (NIP-61)
- 📥 Receive nutzaps automatically
- 📊 Transaction history with table view
- 🎯 Navigatable menu with arrow keys
- 🔑 Secure key management

## Usage

### Build and Run

```bash
cd Examples/CLI-Nutsack
swift build
swift run
```

### Running with existing key

```bash
# Using environment variable
NOSTR_NSEC=your_nsec_or_hex_key swift run

# Or enter interactively when prompted
swift run
```

### Menu Navigation

- **↑/↓** or **j/k** - Navigate menu items
- **Enter** or **Space** - Select item
- **ESC** or **q** - Go back
- **Ctrl+C** - Exit

## Main Features

### Balance & Tokens
View your total balance and breakdown by mint.

### Manage Mints
- Add new mints
- Remove existing mints
- Add test mints for experimentation
- View mint balances

### Send Tokens
Send ecash to other users via nutzaps. The recipient must have published their nutzap preferences (NIP-61).

### Receive & Claim
- View your P2PK pubkey for receiving
- Automatically publishes nutzap preferences if not already done
- Monitors for incoming nutzaps in the background

### Transaction History
View all your wallet transactions in a formatted table with:
- Date and time
- Transaction type and direction
- Amount (positive/negative)
- Description
- Summary statistics

### Settings
- View wallet information
- Consolidate proofs
- Clean spent proofs
- View proof statistics

## Architecture

The CLI uses NDKSwift's `NDKCashuWallet` which implements:
- NIP-60 for wallet state management
- NIP-61 for nutzap sending/receiving
- Automatic encryption of wallet data
- Multi-mint support
- Proof state management

## Test Mints

Default test mints are available for experimentation:
- https://testnut.cashu.space
- https://nofees.testnut.cashu.space

These are test mints that automatically pay Lightning invoices for testing.