# Signature Verification Sampling in NDKSwift

## Overview

NDKSwift implements a sophisticated signature verification sampling system that balances security with performance. This feature allows developers to reduce the computational overhead of signature verification while maintaining the security guarantee that all relays must always provide valid signatures.

## Security Model

The security model is based on a simple but powerful principle:

> **All relays MUST always send valid signatures. A single invalid signature is sufficient evidence that a relay is malicious and should be blacklisted.**

This zero-tolerance approach to invalid signatures allows us to use statistical sampling:
- New relays start with full verification (100% of signatures checked)
- As relays prove trustworthy by consistently providing valid signatures, the sampling rate gradually decreases
- If a relay ever provides an invalid signature, it is immediately identified as malicious

## Architecture

### Core Components

1. **NDKSignatureVerificationConfig** - Configuration for the sampling system
2. **NDKSignatureVerificationSampler** - Main sampling logic and evil relay detection
3. **NDKSignatureVerificationCache** - LRU cache for already-verified event signatures
4. **NDKRelaySignatureStats** - Per-relay statistics tracking
5. **NDKSignatureVerificationDelegate** - Protocol for handling verification events

### How It Works

1. When an event is received from a relay, NDK checks if signature verification is needed
2. The signature cache is consulted first - if the event was already verified, no re-verification occurs
3. Based on the relay's trust level (validation ratio), the system decides whether to verify
4. If verification occurs and succeeds, the relay's trust increases and validation ratio decreases
5. If verification fails, the relay is immediately marked as malicious and optionally blacklisted

## Configuration

### Basic Configuration

```swift
// Default configuration - full security with gradual trust building
let ndk = NDK(signatureVerificationConfig: .default)

// Disabled verification - use with extreme caution!
let unsafeNDK = NDK(signatureVerificationConfig: .disabled)
```

### Custom Configuration

```swift
let config = NDKSignatureVerificationConfig(
    // Start by verifying 100% of signatures from new relays
    initialValidationRatio: 1.0,
    
    // Eventually drop to verifying only 5% of signatures from trusted relays
    lowestValidationRatio: 0.05,
    
    // Automatically disconnect and blacklist relays that send invalid signatures
    autoBlacklistInvalidRelays: true,
    
    // Optional: Custom function to determine validation ratio
    validationRatioFunction: { relay, validatedCount, nonValidatedCount in
        // Your custom logic here
        return customRatio
    }
)

let ndk = NDK(signatureVerificationConfig: config)
```

## Default Validation Ratio Algorithm

The default algorithm uses exponential decay to gradually reduce the validation ratio as a relay proves trustworthy:

```
ratio = initialRatio * e^(-0.01 * validatedCount)
```

This means:
- First 10 events: Always verified (100%)
- After 100 valid signatures: ~36.8% verification rate
- After 200 valid signatures: ~13.5% verification rate
- Never drops below the configured minimum (default 10%)

## Handling Invalid Signatures

### Delegate Pattern

```swift
class MySignatureDelegate: NDKSignatureVerificationDelegate {
    func signatureVerificationFailed(for event: NDKEvent, from relay: NDKRelay) {
        print("⚠️ Relay \(relay.url) sent invalid signature for event \(event.id ?? "unknown")")
        // Log to your monitoring system
        // Alert the user
        // Take custom action
    }
    
    func relayBlacklisted(_ relay: NDKRelay) {
        print("🚫 Relay \(relay.url) has been blacklisted")
        // Update UI
        // Persist blacklist
    }
}

// Set the delegate
let delegate = MySignatureDelegate()
Task {
    await ndk.setSignatureVerificationDelegate(delegate)
}
```

### Manual Blacklist Management

```swift
// Check if a relay is blacklisted
let isBlacklisted = await ndk.isRelayBlacklisted(relay)

// Get all blacklisted relay URLs
let blacklistedRelays = await ndk.getBlacklistedRelays()

// The blacklist persists for the lifetime of the NDK instance
// To persist across app launches, save the blacklist and restore it
```

## Statistics and Monitoring

### Global Statistics

```swift
// Get signature verification statistics
let stats = await ndk.getSignatureVerificationStats()
print("Total verifications: \(stats.totalVerifications)")
print("Failed verifications: \(stats.failedVerifications)")
print("Blacklisted relays: \(stats.blacklistedRelays)")
```

### Per-Relay Statistics

```swift
// Get statistics for a specific relay
let relayStats = relay.getSignatureStats()
print("Relay: \(relay.url)")
print("  Validated events: \(relayStats.validatedCount)")
print("  Non-validated events: \(relayStats.nonValidatedCount)")
print("  Current validation ratio: \(relayStats.currentValidationRatio)")
```

## Performance Benefits

With signature verification sampling, you can expect:

1. **Reduced CPU usage**: Only a fraction of signatures need cryptographic verification
2. **Faster event processing**: Events can be processed immediately when verification is skipped
3. **Better battery life**: Especially important for mobile applications
4. **Scalable to high-volume relays**: Can handle thousands of events per second

Example performance improvement:
- Without sampling: 1000 events = 1000 signature verifications
- With sampling (10% rate): 1000 events ≈ 100 signature verifications (90% reduction)

## Best Practices

### 1. Always Listen for Invalid Signatures

Even with `autoBlacklistInvalidRelays` enabled, implement the delegate to log and monitor:

```swift
class ProductionDelegate: NDKSignatureVerificationDelegate {
    func signatureVerificationFailed(for event: NDKEvent, from relay: NDKRelay) {
        // Log to your error tracking service
        ErrorTracker.shared.log(
            "Invalid signature detected",
            metadata: [
                "relay": relay.url,
                "eventId": event.id ?? "unknown"
            ]
        )
    }
}
```

### 2. Start Conservative

For new applications, start with conservative settings:

```swift
let config = NDKSignatureVerificationConfig(
    initialValidationRatio: 1.0,    // Verify everything initially
    lowestValidationRatio: 0.5,     // Never drop below 50%
    autoBlacklistInvalidRelays: true
)
```

As you gain confidence and understand your relay ecosystem, you can lower the minimum ratio.

### 3. Monitor Relay Behavior

Regularly review relay statistics to identify patterns:

```swift
for relay in ndk.relays {
    let stats = relay.getSignatureStats()
    if stats.totalEvents > 1000 && stats.validatedCount == stats.totalEvents {
        print("\(relay.url) has perfect validation record")
    }
}
```

### 4. Handle Cache Clearing

The signature cache improves performance but uses memory. Clear it periodically:

```swift
// Clear cache during low-memory situations
await ndk.clearSignatureCache()

// Or implement periodic clearing
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    Task {
        await ndk.clearSignatureCache()
    }
}
```

## Security Considerations

### When to Use Full Verification

Always use 100% verification (both initial and lowest ratio = 1.0) when:

1. **Testing new relays**: Before adding to production
2. **High-security contexts**: Financial transactions, private messages
3. **Debugging**: When investigating relay issues
4. **Small-scale applications**: When performance isn't critical

### Understanding the Risks

With sampling enabled:
- **First invalid signature is always caught**: But some invalid signatures might be processed before detection
- **Cache poisoning**: If an attacker can predict which events will be cached, they might try to get an invalid signature cached. Our implementation prevents this by only caching verified signatures.
- **Probabilistic detection**: With a 10% sampling rate, there's a 90% chance any single invalid signature goes undetected, but the probability of avoiding detection decreases exponentially with each event.

## Troubleshooting

### Issue: Relay Wrongly Blacklisted

If a relay is incorrectly blacklisted (e.g., due to a bug in the relay that's now fixed):

```swift
// Currently, you need to create a new NDK instance
// Future versions may support un-blacklisting
let newNDK = NDK(signatureVerificationConfig: config)
```

### Issue: High Memory Usage

If the signature cache grows too large:

```swift
// Use a smaller cache size
let config = NDKSignatureVerificationConfig(
    initialValidationRatio: 1.0,
    lowestValidationRatio: 0.1,
    autoBlacklistInvalidRelays: true,
    validationRatioFunction: nil
)

// Periodically clear the cache
await ndk.clearSignatureCache()
```

### Issue: Performance Still Too Slow

If verification is still impacting performance:

1. Lower the minimum validation ratio (with careful consideration)
2. Implement event filtering before verification
3. Use dedicated background queues for verification
4. Consider upgrading to more powerful hardware

## Migration Guide

If you're updating from a version without signature verification sampling:

1. **No changes required**: The default configuration maintains full security
2. **To enable sampling**: Explicitly configure lower validation ratios
3. **Monitor initially**: Use the delegate to ensure relays behave correctly
4. **Gradual rollout**: Start with a small subset of users

## Future Enhancements

Planned improvements for future versions:

1. **Persistent blacklist**: Save blacklist across app launches
2. **Relay reputation sharing**: Share relay reputation between NDK instances
3. **Adaptive algorithms**: Machine learning-based validation ratio adjustment
4. **Performance metrics**: Built-in performance monitoring
5. **Configurable cache size**: Per-instance cache size limits

## Conclusion

Signature verification sampling in NDKSwift provides a powerful way to improve performance while maintaining security. By following the principle that relays must never lie, we can safely reduce verification overhead and build more responsive Nostr applications.

Remember: **A single invalid signature means the relay is malicious.** This zero-tolerance approach is what makes sampling both safe and effective.