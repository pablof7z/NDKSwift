# Cashu Mint Retry Mechanism

NDKSwift implements a robust retry mechanism for Cashu mint operations to handle temporary failures and network issues gracefully.

## Overview

When performing cross-mint transfers or Lightning deposits, mints may temporarily fail to issue tokens even after receiving payment. NDKSwift automatically retries these operations with a linear backoff strategy before requiring user intervention.

## Retry Configuration

The retry mechanism uses the following configuration:

- **Base delay**: 5 seconds
- **Linear increment**: 5 seconds per retry
- **Maximum retries**: 6 attempts
- **Maximum delay**: 30 seconds between retries
- **Total wait time**: ~105 seconds (5+10+15+20+25+30)

## How It Works

### 1. Automatic Retry Phase

When a mint operation fails, the system automatically retries with increasing delays:

```swift
// Example: Cross-mint transfer with automatic retry
let result = try await Payment.transferBetweenMints(
    wallet: wallet,
    from: sourceMintURL,
    to: destinationMintURL,
    amount: amount,
    // ... other parameters
)
// If successful, proofs are returned immediately
```

The retry sequence:
1. **Attempt 1**: Immediate
2. **Attempt 2**: Wait 5 seconds
3. **Attempt 3**: Wait 10 seconds
4. **Attempt 4**: Wait 15 seconds
5. **Attempt 5**: Wait 20 seconds
6. **Attempt 6**: Wait 25 seconds
7. **Attempt 7**: Wait 30 seconds

### 2. User Intervention Phase

After exhausting automatic retries, the system throws a specific error requiring user intervention:

```swift
do {
    let result = try await Payment.transferBetweenMints(...)
} catch MintFailureError.requiresUserIntervention(let operation, _, _, _, let paymentProof) {
    // Present options to user
    let decision = await showUserAlert(operation)
    
    switch decision {
    case .retry:
        // Manual retry attempt
        let proofs = try await retryHandler.retryPendingMint(operation, mint: mint)
        
    case .blacklistMint:
        // Add mint to blacklist
        await wallet.blacklistMint(operation.mintURL)
        
    case .cancel:
        // Log for manual recovery with payment proof
        logFailedOperation(operation, paymentProof: paymentProof)
    }
}
```

## Error Types

### Recoverable Errors (Automatic Retry)
- Network timeouts
- Connection failures
- Temporary mint unavailability
- HTTP 5xx errors

### Non-Recoverable Errors (Immediate Failure)
- Invalid proofs
- Insufficient balance
- Authentication failures
- Invalid mint responses

## Implementation Example

### Using the Retry Handler Directly

```swift
let retryHandler = MintRetryHandler()

let (proofs, wasUserNotified) = try await retryHandler.retryMintWithBackoff(
    mintQuote: mintQuote,
    mint: mint,
    amount: amount,
    paymentProof: preimage,
    onRetryAttempt: { attemptNumber, delay in
        print("Retry attempt \(attemptNumber) in \(Int(delay)) seconds...")
    }
)

if wasUserNotified && proofs.isEmpty {
    // User intervention required
    // Present UI for user decision
}
```

### Handling Failed Mint Operations

```swift
// Example implementation of a mint failure handler
actor MintFailureHandler {
    func handlePaymentError(_ error: Error) async throws {
        if case MintFailureError.requiresUserIntervention(let operation, _, _, _, let proof) = error {
            // Get user decision
            let decision = await delegate.handleMintFailure(operation: operation, error: error)
            
            switch decision {
            case .retry:
                // Retry the operation
                let proofs = try await retryHandler.retryPendingMint(operation, mint: mint)
                
            case .blacklistMint:
                // Blacklist the mint
                await wallet.blacklistMint(operation.mintURL)
                logFailedOperation(operation, paymentProof: proof)
                
            case .cancel:
                // Just log for potential manual recovery
                logFailedOperation(operation, paymentProof: proof)
            }
        }
    }
}
```

## Persistent Operations

Failed mint operations are represented by `PendingMintOperation`:

```swift
public struct PendingMintOperation: Codable {
    public let quoteId: String      // Mint quote ID
    public let mintURL: String      // Mint URL
    public let amount: Int64        // Amount in sats
    public let invoice: String      // Lightning invoice
    public let paymentProof: String? // Payment preimage (for cross-mint)
    public let createdAt: Date
    public let lastAttemptAt: Date
}
```

These can be persisted to handle app restarts:

```swift
// Save pending operations
let pendingOps = await retryHandler.getPendingMints()
// Persist to storage...

// After app restart, retry pending operations
for operation in loadedPendingOps {
    let proofs = try await retryHandler.retryPendingMint(operation, mint: mint)
}
```

## Best Practices

1. **Always preserve payment proofs**: These are critical for manual recovery
2. **Implement proper UI feedback**: Show retry progress to users
3. **Log all failures**: Include quote IDs and payment proofs for support
4. **Consider mint reputation**: Track mint reliability over time
5. **Implement blacklist persistence**: Save blacklisted mints across sessions

## Integration with SwiftUI

```swift
struct MintFailureAlert: View {
    let operation: PendingMintOperation
    @State private var decision: MintFailureUserDecision?
    
    var body: some View {
        Alert(
            title: Text("Mint Failed to Issue Tokens"),
            message: Text("""
                The mint at \(operation.mintURL) received your payment but failed to issue tokens.
                
                Amount: \(operation.amount) sats
                Quote ID: \(operation.quoteId)
                
                What would you like to do?
                """),
            primaryButton: .default(Text("Retry")) {
                decision = .retry
            },
            secondaryButton: .destructive(Text("Blacklist Mint")) {
                decision = .blacklistMint
            }
        )
    }
}
```

## Security Considerations

1. **Payment Proof Storage**: Always store payment proofs securely for dispute resolution
2. **Mint Blacklisting**: Implement proper blacklist management to prevent repeated failures
3. **Rate Limiting**: The linear backoff prevents overwhelming mints with requests
4. **User Education**: Clearly explain risks and recovery options to users

## Troubleshooting

### Common Issues

1. **Mint consistently fails after payment**
   - Solution: Blacklist the mint and contact operator with payment proof

2. **Network timeouts during retry**
   - Solution: Check internet connection, retry mechanism will handle temporary issues

3. **App crashes during retry**
   - Solution: Implement persistent operations to resume after restart

### Debug Logging

Enable debug logging to track retry attempts:

```swift
NDKLogger.log(.debug, category: .wallet, "Mint retry attempt \(attemptNumber) for quote \(quoteId)")
```

## Future Improvements

- Exponential backoff option for different failure patterns
- Reputation-based retry strategies
- Automatic mint switching based on success rates
- Integration with mint monitoring services