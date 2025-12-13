# Zaps and Wallets in NDKSwift

NDKSwift provides a robust, modular architecture for handling Zaps (Lightning payments on Nostr). The architecture is designed to support multiple wallet implementations (Cashu, NWC, Spark, etc.) and seamlessly route payments between them.

## 🏗 Architecture

The Zap system is built on two main pillars:

1.  **Zap Protocols**: Define *how* a zap is constructed and communicated over Nostr.
    *   **Lightning (NIP-57)**: Uses LNURL and Lightning Invoices.
    *   **Nutzap (NIP-61)**: Uses Cashu tokens sent directly as event tags.
2.  **Payment Providers (Wallets)**: Define *how* the payment is funded.
    *   **NWC (NIP-47)**: Nostr Wallet Connect (e.g., Alby, Mutiny).
    *   **NIP-60 Wallet**: Built-in Cashu wallet.
    *   **WebLN**: Web-based lightning provider (if applicable).
    *   **Spark/Greenlight**: Direct node connection (via NWC or adapter).

### `NDKZapManager`

The `NDKZapManager` (in `NDKSwiftCore`) orchestrates the process. It:

1.  Fetches recipient information (LNURL, Nutzap preferences).
2.  Selects the best **Zap Protocol** (e.g., prefers Nutzaps for privacy if both parties support it).
3.  Prepares the zap request (Invoice or Token request).
4.  Finds a **Payment Provider** that can fulfill the request.
5.  Executes the payment and publishes the necessary Nostr events.

## 🚀 Setting Up Wallets

You can register multiple wallets. NDKSwift will use the first one that can fulfill a request, or you can specify a preferred one.

### 1. Nostr Wallet Connect (NWC)

Use NWC to connect to remote wallets like Alby, Mutiny, or your own node (via a bridge).

```swift
// Initialize NWC Wallet
let nwcWallet = try NDKNWCWallet(
    connectionURI: "nostr+walletconnect://..."
)
try await nwcWallet.connect()

// Register with Zap Manager
ndk.zapManager.register(provider: nwcWallet)
```

### 2. Cashu Wallet (NIP-60)

The built-in Cashu wallet offers privacy and offline capabilities.

```swift
// Initialize NIP-60 Wallet
let cashuWallet = try NIP60Wallet(ndk: ndk)
try await cashuWallet.load()  // Automatically registers fallback handler

// Register with Zap Manager
ndk.zapManager.register(provider: cashuWallet)

// Register Nutzap Protocol (required for NIP-61 support)
ndk.zapManager.register(protocol: NDKNutzapProtocol(ndk: ndk))
```

**Note:** The `load()` method automatically registers a `CashuZapFallbackHandler` that enables Lightning-to-Nutzap conversions. If you have a Lightning wallet but the recipient only accepts Nutzaps, the fallback handler will automatically mint Cashu tokens via a Lightning payment.

### 3. Spark Wallet / Greenlight

To use Spark Wallet or Blockstream Greenlight, the recommended approach is to use their **NWC bridge** or implement a custom `NDKPaymentProvider`.

If using NWC:
```swift
let sparkNWC = try NDKNWCWallet(connectionURI: sparkConnectionURI)
ndk.zapManager.register(provider: sparkNWC)
```

## ⚡ Sending Zaps

### Using `NDKUIZapButton` (SwiftUI)

The easiest way to add zap support is using the UI component.

```swift
NDKUIZapButton(
    ndk: ndk,
    event: event,
    amounts: [21, 100, 1000],
    preferredProvider: "nip60" // Optional: Force specific wallet
)
```

### Programmatic Zapping

You can send zaps directly from your code.

```swift
// Zap a user
try await ndk.zapManager.zap(
    to: recipientUser,
    amountSats: 100,
    comment: "Awesome work! ⚡"
)

// Zap an event
try await event.zap(
    with: ndk,
    amountSats: 21,
    comment: "Love this!"
)
```

### Selecting a Specific Wallet

If a user has multiple wallets configured, you can specify which one to use.

```swift
// Get available providers
let providers = await ndk.zapManager.getRegisteredProviders()

// Zap using a specific provider ID
try await event.zap(
    with: ndk,
    amountSats: 100,
    preferredProvider: "nwc_wallet" // or provider.id
)
```

## 🔄 Cross-Protocol Zaps

NDKSwift handles cross-protocol complexity for you through the **Fallback Handler** system.

*   **Lightning to Lightning**: Standard NIP-57.
*   **Cashu to Cashu**: NIP-61 Nutzap (Instant, private, no fees).
*   **Lightning to Cashu**: If you have a Lightning wallet but the recipient wants Nutzaps, the `CashuZapFallbackHandler` automatically mints tokens via Lightning invoice.
*   **Cashu to Lightning**: Use the Cashu wallet to pay the Lightning invoice (melt).

### How Fallback Handlers Work

When a direct zap fails (e.g., you want to send a Nutzap but only have a Lightning wallet), NDKSwift tries registered fallback handlers in order. The `CashuZapFallbackHandler`:

1. Detects when a Nutzap payment request can't be fulfilled directly
2. Creates a mint quote at one of the recipient's accepted mints
3. Pays the mint's Lightning invoice using your Lightning wallet (NWC, etc.)
4. Mints P2PK-locked Cashu tokens for the recipient
5. Publishes the Nutzap event with the minted tokens

This happens **automatically** when you call `cashuWallet.load()` - no manual configuration needed.

## 🛠 Implementing a Custom Wallet

To add support for a new wallet type, implement the `NDKPaymentProvider` protocol.

```swift
class MyCustomWallet: NDKPaymentProvider {
    let id = "my_wallet"
    let displayName = "My Wallet"

    func isAvailable() async -> Bool {
        return true
    }

    func canFulfill(_ request: PaymentRequest) async -> Bool {
        return request is LightningInvoiceRequest
    }

    func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        guard let lnRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }

        // Logic to pay invoice...
        let preimage = try await myWalletLib.pay(lnRequest.invoice)

        return LightningPaymentConfirmation(
            amountSats: lnRequest.amountSats,
            timestamp: Date(),
            preimage: preimage
        )
    }

    // ...
}
```
