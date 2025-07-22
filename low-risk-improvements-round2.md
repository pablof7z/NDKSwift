# Low-Risk Improvements Round 2 - NDKSwift

## 1. Extract JSON Constants (Highest Impact)

### Problem
Multiple JSON-related strings are hardcoded throughout the codebase, especially for Cashu/NIP-60 operations:
- "proof", "mint", "unit", "amount", "secret", "C" appear in many files
- These are part of the Cashu protocol and should be constants

### Files affected:
- Sources/NDKSwift/Wallets/NIP60/Nutzap.swift:402
- Sources/NDKSwift/Models/Kinds/NDKCashuEvents.swift (multiple occurrences)
- Sources/NDKSwift/Wallets/NIP60/WalletTransaction.swift:149
- Sources/NDKSwift/Models/Kinds/NDKZapRequest.swift:29,65
- Sources/NDKSwift/Models/Kinds/NDKNutzap.swift:36,39,146,183,190
- Sources/NDKSwift/Models/Kinds/NDKMintAnnouncement.swift:105

### Solution
Create a new file `Sources/NDKSwift/Utils/NostrJSONConstants.swift`:
```swift
public enum NostrJSONConstants {
    public enum Cashu {
        public static let proof = "proof"
        public static let mint = "mint"
        public static let unit = "unit"
        public static let amount = "amount"
        public static let secret = "secret"
        public static let C = "C"
    }
}
```

## 2. Extract Hex Validation Constants

### Problem
Magic numbers 32 and 64 appear frequently for hex string validation:
- 64 characters = 32 bytes hex-encoded (for event IDs, pubkeys)
- 32 bytes = raw data size
- These validations are repeated in many places

### Files affected:
- Sources/NDKSwift/Utils/Bech32.swift:183,191
- Sources/NDKSwift/Models/NDKEventBuilder.swift:417,467,475,531
- Sources/NDKSwift/Utils/ContentTagger.swift:20,266,273,281,290,302
- Sources/NDKSwift/Negentropy/NegentropyItem.swift:42
- Sources/NDKSwift/Encryption/NIP04/NIP04Encryption.swift:126,141

### Solution
Add to `Sources/NDKSwift/Utils/Crypto.swift`:
```swift
public enum CryptoConstants {
    // Existing:
    public static let privateKeySize = 32
    
    // Add:
    public static let publicKeySize = 32
    public static let eventIdSize = 32
    public static let hexEncodedKeyLength = 64
    public static let hexEncodedEventIdLength = 64
}
```

## 3. Consolidate Error Message Patterns

### Problem
"Failed to" error messages are inconsistent and duplicated:
- "Failed to encrypt", "Failed to decrypt", "Failed to parse", etc.
- Some use sentence case, others don't

### Files affected:
- Sources/NDKSwift/Signers/NDKBunkerSigner.swift:527,555,560
- Sources/NDKSwift/RPC/NDKNostrRPC.swift:67,142
- Sources/NDKSwift/Wallets/NIP60/WalletEventProcessor.swift:66,67,114
- Sources/NDKSwift/Wallets/NIP60/Payment.swift:17,24,70,272

### Solution
Add error message factory methods to NDKError:
```swift
extension NDKError {
    static func failedToParseContent(_ type: String) -> NDKError {
        return .invalidContent("Failed to parse \(type)")
    }
    
    static func failedToPerformOperation(_ operation: String, reason: String? = nil) -> NDKError {
        let message = reason != nil ? "Failed to \(operation): \(reason!)" : "Failed to \(operation)"
        return .failedTo(operation, message: reason)
    }
}
```

## 4. Extract Common JSON Parsing Pattern

### Problem
The pattern `content.data(using: .utf8)` followed by `JSONDecoder().decode` appears frequently:

### Files affected (17 occurrences):
- Sources/NDKSwift/RPC/NDKNostrRPC.swift:64
- Sources/NDKSwift/Wallets/NIP60/WalletEventProcessor.swift:64,112
- Sources/NDKSwift/Wallets/NIP60/P2PKManager.swift:57
- Sources/NDKSwift/Core/NDKProfileManager.swift:120
- Sources/NDKSwift/Wallets/NWC/NWCResponseHandler.swift:298,334
- Sources/NDKSwift/Wallets/NIP60/Nutzap.swift:237,259

### Solution
Add extension to String:
```swift
extension String {
    func decodeJSON<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = self.data(using: .utf8) else {
            throw NDKError.invalidDataFormat("JSON", details: "Failed to convert string to UTF-8 data")
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
```

## Implementation Priority

1. **NostrJSONConstants** - Highest impact, affects Cashu/wallet functionality
2. **Hex validation constants** - Medium-high impact, improves validation clarity
3. **JSON parsing extension** - Medium impact, reduces boilerplate
4. **Error message consolidation** - Lower impact but improves consistency

## Estimated Effort
- Total time: ~2 hours
- Each improvement is isolated and can be done incrementally
- No breaking changes, all are internal refactors