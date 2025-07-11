# NDKCashuWallet E2E Test

This example demonstrates the NIP-60 Cashu wallet implementation in NDKSwift with the new payment monitoring system.

## Running the Test

### 1. First Run (Generate New Key)

```bash
# From the NDKSwift root directory
./.build/debug/CashuWallet
```

This will:
- Generate a new Nostr private key
- Display the nsec (SAVE THIS!)
- Create a NIP-60 wallet
- Test the payment flow with requestMint() and monitorPayment()
- Save the wallet to Nostr relays
- Show raw JSON of published events

### 2. Subsequent Runs (Use Existing Key)

```bash
# Use the nsec from the first run
./.build/debug/CashuWallet nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
```

This will:
- Load the existing wallet from Nostr
- Show current balance
- Allow testing with an existing wallet that may have funds

## Payment Flow API

### 1. Request Mint Quote

```swift
let quote = try await wallet.requestMint(
    amount: 100,
    mintURL: "https://testnut.cashu.space",
    persistQuote: true  // Optional - saves as kind 7374
)
```

Returns `CashuMintQuote`:
- `id`: Quote ID from mint
- `mintURL`: Mint URL
- `invoice`: Lightning invoice to pay
- `amount`: Amount in sats
- `createdAt`: Timestamp
- `eventId`: Optional Nostr event ID if persisted

### 2. Monitor Payment

```swift
let monitorTask = Task {
    for try await status in wallet.monitorPayment(quote: quote) {
        switch status {
        case .pending:
            print("Waiting for payment...")
        case .paid(let proofs):
            print("Payment received! Got \(proofs.count) proofs")
            // Proofs are automatically saved to wallet
            break
        case .expired:
            print("Payment expired")
            // Quote is automatically persisted
            break
        case .cancelled:
            print("Payment cancelled")
            break
        }
    }
}

// Cancel monitoring
monitorTask.cancel()  // Automatically deletes quote event
```

## What This Tests

1. **NIP-60 Implementation**:
   - Wallet events (kind 17375) - replaceable by kind
   - Token events (kind 7375) - created when proofs received
   - Quote events (kind 7374) - optional, with auto-deletion
   - NIP-44 encryption for all wallet data
   - No d-tag needed for replaceable events

2. **Payment Monitoring**:
   - AsyncSequence-based monitoring (Swift idiomatic)
   - Natural cancellation with Task.cancel()
   - Automatic quote persistence on timeout
   - Automatic cleanup on payment/cancellation
   - Configurable polling (default 5s) and timeout (default 10m)

3. **Event Publishing**:
   - Raw JSON logging for all published events
   - Delete events (kind 5) for quote cleanup
   - Proper event lifecycle management

## Testing with Real Balance

To test with actual balance:

1. Run the test and save the nsec
2. Copy the Lightning invoice from the output
3. Pay the invoice (testnut auto-settles)
4. The monitoring will detect payment and issue tokens
5. Run the test again with the same nsec to see the balance

## Implementation Notes

- Each user has exactly one wallet per pubkey (NIP-60)
- Wallet events are replaceable by kind (17375)
- Quote events use NIP-40 expiration tags
- All wallet data is encrypted with NIP-44
- The system follows NIP-09 for event deletion
- Polling interval: 5 seconds (configurable)
- Timeout: 10 minutes (configurable)