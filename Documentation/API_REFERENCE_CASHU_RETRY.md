# Cashu Retry API Reference

## MintRetryHandler

An actor that handles retry logic for failed mint operations with linear backoff.

### Properties

```swift
public actor MintRetryHandler {
    private let config = MintRetryConfig()
    private var pendingMints: [String: PendingMintOperation] = [:]
}
```

### Methods

#### retryMintWithBackoff

Retry minting tokens with linear backoff strategy.

```swift
public func retryMintWithBackoff(
    mintQuote: CashuSwift.Bolt11.MintQuote,
    mint: CashuSwift.Mint,
    amount: Int64,
    paymentProof: String? = nil,
    onRetryAttempt: ((Int, TimeInterval) -> Void)? = nil
) async throws -> (proofs: [CashuSwift.Proof], wasUserNotified: Bool)
```

**Parameters:**
- `mintQuote`: The mint quote from the Cashu mint
- `mint`: The Cashu mint instance
- `amount`: Amount in satoshis
- `paymentProof`: Optional payment proof (preimage) for cross-mint transfers
- `onRetryAttempt`: Optional callback for retry progress

**Returns:**
- `proofs`: Array of minted proofs (empty if all retries failed)
- `wasUserNotified`: Whether retry limit was reached and user intervention is required

**Throws:**
- Non-recoverable errors (invalid proofs, insufficient balance)

#### retryPendingMint

Retry a specific pending mint operation.

```swift
public func retryPendingMint(
    _ operation: PendingMintOperation,
    mint: CashuSwift.Mint
) async throws -> [CashuSwift.Proof]
```

**Parameters:**
- `operation`: The pending mint operation to retry
- `mint`: The Cashu mint instance

**Returns:**
- Array of minted proofs

**Throws:**
- `MintRetryError.userNotificationRequired` if retry limit reached

#### getPendingMints

Get all pending mint operations for recovery after app restart.

```swift
public func getPendingMints() -> [PendingMintOperation]
```

## MintRetryConfig

Configuration for mint retry behavior.

```swift
public struct MintRetryConfig {
    let baseDelay: TimeInterval = 5.0           // Base delay between retries
    let delayIncrement: TimeInterval = 5.0      // Linear increment per retry
    let maxRetries: Int = 6                     // Maximum retry attempts
    let maxDelay: TimeInterval = 30.0           // Maximum delay cap
}
```

## PendingMintOperation

Represents a pending mint operation that needs to be completed.

```swift
public struct PendingMintOperation: Codable, Identifiable {
    public let id: String              // Same as quoteId
    public let quoteId: String         // Mint quote identifier
    public let mintURL: String         // Mint URL
    public let amount: Int64           // Amount in satoshis
    public let invoice: String         // Lightning invoice
    public let paymentProof: String?   // Payment preimage (optional)
    public let createdAt: Date         // When operation was created
    public let lastAttemptAt: Date     // Last retry attempt
}
```

## Error Types

### MintRetryError

```swift
public enum MintRetryError: LocalizedError {
    case userNotificationRequired(PendingMintOperation)
}
```

### MintFailureError

```swift
public enum MintFailureError: LocalizedError {
    case requiresUserIntervention(
        pendingOperation: PendingMintOperation,
        sourceMint: String,
        destinationMint: String,
        amount: Int64,
        paymentProof: String
    )
}
```

### DepositMintError

```swift
public enum DepositMintError: LocalizedError {
    case requiresUserIntervention(
        pendingOperation: PendingMintOperation,
        invoice: String
    )
}
```

## MintFailureHandlerDelegate

Protocol for UI-level handling of mint failures.

```swift
public protocol MintFailureHandlerDelegate: AnyObject {
    func handleMintFailure(
        operation: PendingMintOperation,
        error: Error
    ) async -> MintFailureUserDecision
}
```

## MintFailureUserDecision

User's decision on how to handle a mint failure.

```swift
public enum MintFailureUserDecision {
    case retry           // Retry the mint operation
    case blacklistMint   // Blacklist mint and don't retry
    case cancel          // Cancel without blacklisting
}
```

## Usage Examples

### Basic Retry with Progress Callback

```swift
let retryHandler = MintRetryHandler()

let (proofs, wasUserNotified) = try await retryHandler.retryMintWithBackoff(
    mintQuote: mintQuote,
    mint: mint,
    amount: 1000,
    paymentProof: "abc123...",
    onRetryAttempt: { attemptNumber, delay in
        print("Retry #\(attemptNumber) in \(delay) seconds...")
    }
)

if wasUserNotified {
    // Show UI for user decision
    presentMintFailureAlert()
}
```

### Handling Cross-Mint Transfer Failures

```swift
do {
    let result = try await Payment.transferBetweenMints(
        wallet: wallet,
        from: sourceMintURL,
        to: destinationMintURL,
        amount: amount,
        mints: mints,
        proofStateManager: proofStateManager,
        eventManager: eventManager,
        signer: signer
    )
} catch MintFailureError.requiresUserIntervention(let op, _, _, _, let proof) {
    // Handle user intervention
    let handler = MintFailureHandler(wallet: wallet, mints: mints)
    try await handler.handlePaymentError(error)
}
```

### Persisting and Recovering Operations

```swift
// Save pending operations before app terminates
let pendingOps = await retryHandler.getPendingMints()
UserDefaults.standard.set(
    try? JSONEncoder().encode(pendingOps),
    forKey: "pendingMintOperations"
)

// Recover after app restart
if let data = UserDefaults.standard.data(forKey: "pendingMintOperations"),
   let pendingOps = try? JSONDecoder().decode([PendingMintOperation].self, from: data) {
    
    for operation in pendingOps {
        if let mint = await mints.getMint(url: operation.mintURL) {
            do {
                let proofs = try await retryHandler.retryPendingMint(operation, mint: mint)
                print("Recovered \(proofs.count) proofs")
            } catch {
                print("Failed to recover: \(error)")
            }
        }
    }
}
```

### Custom Error Recovery

```swift
extension MintRetryHandler {
    /// Check if an error is recoverable
    func isRecoverableError(_ error: Error) -> Bool {
        if let ndkError = error as? NDKError {
            switch ndkError {
            case .timeout, .connectionFailed:
                return true
            case .insufficientBalance, .walletError:
                return false
            default:
                return true
            }
        }
        return true
    }
}
```