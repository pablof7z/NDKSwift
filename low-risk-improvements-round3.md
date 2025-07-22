# Low-Risk Improvements Round 3

## 1. Extract Common Error Checking Patterns

### Signer Configuration Check
The pattern `guard let signer = signer/ndk.signer else { throw NDKError... }` appears in 14+ locations with slight variations:
- `NDKError.configurationError("No signer configured")` - 6 instances
- `NDKError.notConfigured("No signer configured")` - 8 instances

**Recommendation**: Create a helper method to standardize this check:
```swift
extension NDK {
    func requireSigner() throws -> NDKSigner {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        return signer
    }
}
```

### Connection Lost Errors
Multiple instances of connection lost errors with similar patterns:
- `NDKError.connectionLost(relay: url, message: "Not connected to relay")` 
- `NDKError.connectionLost(relay: url.absoluteString, message: StringConstants.ErrorMessages.notConnected)`

**Recommendation**: Standardize with a helper method in NDKRelayConnection.

### Network Error Handling
BlossomClient has 5 identical catch blocks:
```swift
} catch {
    throw NDKError.networkError(for: serverURL, operation: "Blossom request", error: error)
}
```

**Recommendation**: Extract to a method in BlossomClient.

## 2. Extract JSON Field Constants

Found hardcoded JSON field names throughout the codebase:
- `"id"`, `"pubkey"`, `"created_at"`, `"kind"`, `"content"`, `"tags"`, `"sig"`
- These appear in database queries, JSON parsing, and event serialization

**Recommendation**: Add these to NostrJSONConstants.swift:
```swift
public enum NostrJSONConstants {
    public enum EventFields {
        public static let id = "id"
        public static let pubkey = "pubkey"
        public static let createdAt = "created_at"
        public static let kind = "kind"
        public static let content = "content"
        public static let tags = "tags"
        public static let sig = "sig"
    }
}
```

## 3. Extract Magic Numbers for Event Kinds

While EventKind enum exists, there are still direct numeric references:
- Comments mention `10002` for relay lists
- Comments mention `30000-39999` for parameterized replaceable
- Comments mention `10000-19999` for replaceable events
- Direct comparisons like `event.kind != 10002`

**Recommendation**: Add range constants to EventKind:
```swift
public extension EventKind {
    static let replaceableRange = 10000..<20000
    static let parameterizedReplaceableRange = 30000..<40000
    static let ephemeralRange = 20000..<30000
}
```

## 4. Consolidate Validation Error Messages

Found multiple validation error patterns:
- `NDKError.invalidDataFormat("P2PK private key", details: "Invalid hex format")`
- `NDKError.validationError("Invalid secret for P2PK signing")`
- `DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown status type")`

**Recommendation**: Standardize validation error creation.

## 5. Extract Blossom Constants

Found hardcoded values in Blossom implementation:
- Error messages: "Blossom server", "Blossom request", "Blossom authorization failed"
- HTTP status codes checked directly (200, 401, 413, 415)

**Recommendation**: Create BlossomConstants:
```swift
enum BlossomConstants {
    static let serverName = "Blossom server"
    static let operationName = "Blossom request"
    
    enum HTTPStatus {
        static let ok = 200
        static let unauthorized = 401
        static let payloadTooLarge = 413
        static let unsupportedMediaType = 415
    }
}
```

## 6. Consolidate Cache Size Constants

Found magic number in NDKSignatureVerificationCache:
- `maxCacheSize: Int = 10000`

**Recommendation**: Move to a configuration constants file.

## 7. Extract Database Column Names

Database migrations use hardcoded column names:
- `"identifier"`, `"pubkey"`, `"created_at"`, `"kind"`, `"content"`

**Recommendation**: Create DatabaseConstants for column names to ensure consistency.

## 8. Standardize "Not Connected" Messaging

Multiple variations of "not connected" errors:
- Direct strings: "Not connected to relay"
- StringConstants.ErrorMessages.notConnected
- "No connection available"

**Recommendation**: Use StringConstants.ErrorMessages.notConnected consistently.

## 9. URL String Handling Patterns

Found repeated patterns for URL handling:
- `url.absoluteString` appears 15+ times in error messages
- URL validation and conversion patterns repeated

**Recommendation**: Create URL extension methods for common operations.

## 10. Test Helper Duplication

Found repeated test patterns:
- `UUID().uuidString` for generating unique test content (10+ instances)
- Similar test event creation patterns across multiple test files
- Repeated test relay URLs like "wss://test-relay.example.com"

**Recommendation**: Create TestHelpers module with:
```swift
enum TestHelpers {
    static func uniqueContent(_ prefix: String) -> String {
        "\(prefix) - \(UUID().uuidString)"
    }
    
    static func testRelayURL(_ index: Int = 1) -> String {
        "wss://test-relay\(index).example.com"
    }
}
```

## 11. Continuation Pattern Duplication

Found repeated `withCheckedThrowingContinuation` patterns in:
- NDKBunkerSigner (2 instances)
- NDKNostrRPC (2 instances)
- NDKRelayConnection

**Recommendation**: Consider extracting common continuation management patterns.

## 12. Cache Default Values

Found hardcoded cache sizes and timeouts:
- `maxCacheSize: Int = 10000` in NDKSignatureVerificationCache
- Various timeout values scattered throughout

**Recommendation**: Create CacheConstants for default values.

## Implementation Priority

1. **High Impact**: Extract common error checking patterns (reduces ~20+ duplications)
2. **High Impact**: Consolidate test helpers (improves test maintainability)
3. **Medium Impact**: Extract JSON field constants (improves maintainability)
4. **Medium Impact**: Consolidate Blossom constants
5. **Medium Impact**: Standardize URL handling patterns
6. **Low Impact**: Standardize validation errors
7. **Low Impact**: Extract database column names
8. **Low Impact**: Consolidate cache defaults

These improvements follow DRY principles without changing functionality and make the codebase more maintainable.