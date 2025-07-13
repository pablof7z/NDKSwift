# Redundant Code Patterns in NDKSwift

## 1. Hex String Conversion
**Location**: `Sources/NDKSwift/Utils/DataExtensions.swift`
- `Data.hexString` property (line 25)
- `Data.toHexString()` method (line 33)
- Both do exactly the same thing: `map { String(format: "%02x", $0) }.joined()`

**Recommendation**: Remove `toHexString()` and keep only the property `hexString`

## 2. JSON Encoder/Decoder Instances
Multiple files create their own JSONEncoder/JSONDecoder instances instead of using the centralized `JSONCoding` utility:

**Files creating new instances**:
- `Sources/NDKSwift/Cache/NDKSQLiteCache.swift` - Creates 7 separate encoder/decoder instances
- `Sources/NDKSwift/Wallets/NWC/NWCRequestBuilder.swift` - Creates its own encoder

**Recommendation**: Use `JSONCoding.encoder`/`JSONCoding.decoder` throughout the codebase

## 3. Transaction Type Definitions
Multiple transaction type enums exist:

**Location 1**: `Examples/NutsackiOS/Sources/NutsackiOS/Models/DataModels.swift`
```swift
enum TransactionType: String, Codable {
    case mint      // Lightning -> Ecash
    case melt      // Ecash -> Lightning
    case send      // Send ecash token
    case receive   // Receive ecash token
    case nutzap    // NIP-61 zap
}
```

**Location 2**: `Examples/iOSNostrApp/WalletViewModel.swift`
```swift
enum TransactionType {
    case sent
    case received
}
```

**Recommendation**: Create a shared transaction type model or use the more comprehensive one from DataModels.swift

## 4. Timestamp Generation Pattern
The pattern `Timestamp(Date().timeIntervalSince1970)` or `Int64(Date().timeIntervalSince1970)` appears in 18 different files.

**Recommendation**: Create a utility method like:
```swift
extension Timestamp {
    static var now: Timestamp {
        return Timestamp(Date().timeIntervalSince1970)
    }
}
```

## 5. Random Bytes Generation
The random bytes generation pattern is duplicated in `Crypto.swift`:
- `generatePrivateKey()` method (lines 40-50)
- `randomBytes(count:)` method (lines 103-114)

Both use the same pattern with `SecRandomCopyBytes` and fallback.

**Recommendation**: Have `generatePrivateKey()` call `randomBytes(count: 32)`

## 6. Error Type Proliferation
81 files define their own error types. While some domain-specific errors are necessary, there may be opportunities to consolidate common error patterns.

**Common patterns**:
- Invalid input/data errors
- Network/connection errors
- Encoding/decoding errors

**Recommendation**: Create a base set of common errors that can be extended by specific modules

## 7. URL Normalization
URL normalization logic is centralized in `URLNormalizer.swift`, but there are 11 files that reference URL normalization patterns, suggesting potential for missed usage of the centralized utility.

**Recommendation**: Audit all URL handling code to ensure consistent use of `URLNormalizer`

## 8. SHA256 Hashing
SHA256 is used in 12 files. The centralized method exists in `Crypto.sha256()` but usage should be verified.

**Recommendation**: Ensure all SHA256 operations use the centralized `Crypto.sha256()` method

## Summary
The main areas for consolidation are:
1. Data extension methods (hex conversion)
2. JSON encoding/decoding instances
3. Transaction type definitions in examples
4. Timestamp generation utilities
5. Random bytes generation
6. Common error patterns
7. Consistent use of centralized utilities (URL normalization, SHA256)