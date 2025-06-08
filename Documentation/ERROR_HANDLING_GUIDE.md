# Error Handling Guide

## Overview

NDKSwift uses a unified error handling system that provides consistent, informative, and actionable error messages across the entire library. This guide explains how to use the error system effectively.

## Error Structure

### NDKUnifiedError

The core error type that provides:
- **Category**: High-level grouping (validation, crypto, network, storage, protocol, configuration, runtime)
- **Specific Error**: Detailed error information with unique code
- **Context**: Additional key-value pairs providing error details
- **Underlying Error**: Original error if wrapped from another source

```swift
public struct NDKUnifiedError: NDKErrorProtocol {
    public let category: ErrorCategory
    public let specific: SpecificError
    public let context: [String: Any]
    public let underlying: Error?
}
```

## Error Categories

### Validation Errors
Issues with input data or parameters:
- `invalidPublicKey`: Malformed public key
- `invalidPrivateKey`: Malformed private key
- `invalidEventID`: Invalid event identifier
- `invalidSignature`: Signature verification failed
- `invalidInput`: Generic input validation failure
- `invalidFilter`: Invalid subscription filter

### Crypto Errors
Cryptographic operation failures:
- `signingFailed`: Unable to sign data
- `verificationFailed`: Signature verification failed
- `encryptionFailed`: Encryption operation failed
- `decryptionFailed`: Decryption operation failed
- `keyDerivationFailed`: Key derivation failed

### Network Errors
Network and communication issues:
- `connectionFailed`: Unable to establish connection
- `connectionLost`: Existing connection dropped
- `timeout`: Operation exceeded time limit
- `serverError`: Server returned an error
- `unauthorized`: Authentication/authorization failure

### Storage Errors
File system and cache issues:
- `cacheFailed`: Cache operation failed
- `diskFull`: Insufficient storage space
- `fileNotFound`: Requested file doesn't exist
- `corruptedData`: Data integrity check failed

### Protocol Errors
Nostr protocol violations:
- `invalidMessage`: Malformed protocol message
- `unsupportedVersion`: Protocol version mismatch
- `subscriptionFailed`: Unable to create subscription

### Configuration Errors
Missing or invalid configuration:
- `notConfigured`: Required configuration missing
- `invalidConfiguration`: Configuration validation failed

### Runtime Errors
General runtime issues:
- `notImplemented`: Feature not yet available
- `cancelled`: Operation was cancelled
- `unknown`: Unclassified error

## Usage Examples

### Basic Error Creation

```swift
// Simple validation error
let error = NDKUnifiedError.validation(.invalidPublicKey)

// Error with context
let error = NDKUnifiedError.network(
    .connectionFailed,
    context: ["relay": "wss://relay.example.com", "attempt": 3]
)

// Error with underlying cause
let error = NDKUnifiedError.crypto(
    .signingFailed,
    underlying: originalError
)
```

### Error Handling

```swift
do {
    let event = try await ndk.fetchEvent(id)
} catch let error as NDKUnifiedError {
    switch error.category {
    case .network:
        // Handle network errors (retry, fallback, etc.)
        print("Network error: \(error.errorDescription ?? "")")
    case .validation:
        // Handle validation errors (show user message)
        print("Invalid input: \(error.context)")
    default:
        // Handle other errors
        print("Error: \(error)")
    }
} catch {
    // Handle unexpected errors
    let unified = ErrorMigration.unify(error)
    print("Unexpected error: \(unified)")
}
```

### Recoverable Errors

```swift
let error = NDKUnifiedError.network(.connectionFailed)
    .withRecovery([
        ErrorRecovery(action: "Retry") {
            try await relay.reconnect()
        },
        ErrorRecovery(action: "Use different relay") {
            try await ndk.switchRelay()
        }
    ])

// Present recovery options to user
for (index, recovery) in error.recoverySuggestions.enumerated() {
    print("\(index + 1). \(recovery.action)")
}
```

### Adding Context

```swift
// Add context to existing error
let enrichedError = error
    .withContext("userId", user.id)
    .withContext("timestamp", Date())
    .withContext("operation", "profile_fetch")

// Use context providers
struct RequestContext: ErrorContextProvider {
    let requestId: String
    let endpoint: String
    
    var errorContext: [String: Any] {
        ["requestId": requestId, "endpoint": endpoint]
    }
}

let errorWithRequest = error.withContext(from: requestContext)
```

## Migration from Legacy Errors

### Automatic Conversion

The system automatically converts legacy errors:

```swift
// Old code throwing NDKError
throw NDKError.invalidPublicKey

// Automatically converted when caught
catch let error as NDKUnifiedError {
    // error.category == .validation
    // error.specific.code == "invalid_public_key"
}
```

### Manual Conversion

```swift
// Convert any error to unified
let unified = ErrorMigration.unify(anyError)

// Use throwUnified for automatic conversion
try NDKUnifiedError.throwUnified {
    // Code that might throw legacy errors
    try legacyFunction()
}
```

## Result Type Usage

```swift
// Define function returning Result
func fetchProfile(pubkey: String) -> NDKResult<NDKUserProfile> {
    guard isValidPubkey(pubkey) else {
        return .failure(.validation(.invalidPublicKey, context: ["pubkey": pubkey]))
    }
    // ... fetch logic
    return .success(profile)
}

// Chain operations
let result = fetchProfile(pubkey)
    .asyncMap { profile in
        // Transform profile
        return enrichedProfile
    }
    .recover(from: .network) {
        // Fallback for network errors
        return cachedProfile
    }
```

## Best Practices

1. **Use specific errors**: Choose the most specific error type available
2. **Add context**: Include relevant information in the context dictionary
3. **Preserve underlying errors**: Pass through original errors when wrapping
4. **Provide recovery options**: Add recovery suggestions for user-facing errors
5. **Log appropriately**: Use error categories to determine log levels
6. **Test error paths**: Write tests for error conditions
7. **Document throws**: Specify which errors methods can throw

## Error Monitoring

```swift
// Log errors with appropriate detail
func logError(_ error: NDKUnifiedError) {
    let level: LogLevel
    switch error.category {
    case .validation:
        level = .warning  // User error
    case .network:
        level = .error    // Transient error
    case .crypto, .storage:
        level = .critical // Serious error
    default:
        level = .error
    }
    
    logger.log(
        level: level,
        code: error.errorCode,
        context: error.errorContext,
        underlying: error.underlyingError
    )
}
```

## Future Improvements

The unified error system is designed to be extensible:
- Add new error categories as needed
- Extend specific errors for new features
- Add localization support
- Integrate with error reporting services
- Add error metrics and analytics