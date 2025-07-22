# Low-Risk Improvements for NDKSwift - Round 2

After reviewing the codebase following your previous improvements, I've identified several additional low-risk opportunities:

## 1. JSON Event Field Names as Constants

In `/Sources/NDKSwift/Core/NDK.swift` (lines 666-674), event fields are hardcoded when creating auth messages:

```swift
let eventDict: [String: Any] = [
    "id": authEvent.id,
    "pubkey": authEvent.pubkey,
    "created_at": authEvent.createdAt,
    "kind": authEvent.kind,
    "tags": authEvent.tags,
    "content": authEvent.content,
    "sig": authEvent.sig
]
```

**Recommendation**: Create constants for these JSON field names that are used throughout the codebase:

```swift
// In a new file: Sources/NDKSwift/Utils/NostrJSONConstants.swift
public struct NostrJSONConstants {
    public static let id = "id"
    public static let pubkey = "pubkey"
    public static let createdAt = "created_at"
    public static let kind = "kind"
    public static let tags = "tags"
    public static let content = "content"
    public static let sig = "sig"
}
```

## 2. Additional Tag Constants

Several tag names are still hardcoded in various files:

- `"challenge"` and `"relay"` in auth handling (NDK.swift:661-662)
- `"amount"` used in multiple files (NDKZapRequest.swift, NDKNutzap.swift)
- `"lnurl"` in zap-related files
- `"proof"` in Cashu-related files
- `"mint"` in wallet files
- `"unit"` in payment files
- `"bolt11"` for Lightning invoices

**Recommendation**: Add these to NostrTagConstants:

```swift
// Auth tags
public static let challenge = "challenge"
public static let relay = "relay"

// Payment/Zap tags  
public static let amount = "amount"
public static let lnurl = "lnurl"
public static let bolt11 = "bolt11"

// Cashu/Wallet tags
public static let proof = "proof"
public static let mint = "mint"
public static let unit = "unit"
```

## 3. Lightning Network Protocol Prefixes

Multiple files check for Lightning network prefixes:

- `"lnbc"`, `"lntb"`, `"lnbcrt"` in various files
- `"lnurl"` prefix checks

**Recommendation**: Create constants for these:

```swift
// In Sources/NDKSwift/Utils/LightningConstants.swift
public struct LightningConstants {
    public struct Prefixes {
        public static let mainnet = "lnbc"
        public static let testnet = "lntb"
        public static let regtest = "lnbcrt"
        public static let lnurl = "lnurl"
    }
    
    public static func isLightningInvoice(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.starts(with: Prefixes.mainnet) ||
               lowercased.starts(with: Prefixes.testnet) ||
               lowercased.starts(with: Prefixes.regtest)
    }
}
```

## 4. Bech32 HRP Constants

Several files use hardcoded HRP (Human Readable Part) values:

- `"lnurl"` in multiple places
- `"npub"`, `"nsec"`, `"note"`, `"nevent"`, `"naddr"` mentioned in documentation

**Recommendation**: Create Bech32 constants:

```swift
// In Sources/NDKSwift/Utils/Bech32Constants.swift
public struct Bech32HRP {
    public static let npub = "npub"
    public static let nsec = "nsec"
    public static let note = "note"
    public static let nevent = "nevent"
    public static let naddr = "naddr"
    public static let nrelay = "nrelay"
    public static let lnurl = "lnurl"
}
```

## 5. Consolidate URL Scheme Checks

The URL scheme checking (`"ws://"`, `"wss://"`) appears in multiple places and could use the existing RelayConstants:

```swift
// Update RelayConstants to include these utility methods
public struct RelayConstants {
    // ... existing constants ...
    
    public static func isWebSocketURL(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.hasPrefix(WebSocketScheme.secure) || 
               lowercased.hasPrefix(WebSocketScheme.insecure)
    }
}
```

## 6. Missing Documentation on Public APIs

Several public structs and functions lack documentation:

- `NDKRPCRequest` and `NDKRPCResponse` in NDKNostrRPC.swift
- `NIP05CacheStatistics` in NIP05Manager.swift
- `NegentropyItem`, `NegentropyAccumulator`, `NegentropyRange` in Negentropy files
- Various public init methods and properties

**Recommendation**: Add documentation comments to these public APIs following the existing pattern in the codebase.

## 7. Consistent Error Message Formatting

The error factory methods use different patterns for constructing messages. Some use string interpolation, others use optional mapping:

```swift
// Current inconsistent patterns:
"Failed to \(operation): \($0)"
"Invalid \(dataType): \($0)"
"Missing required \(field) in \($0)"
```

**Recommendation**: Standardize on a single pattern throughout NDKErrorFactories.swift.

## 8. Extract Common JSON Parsing Patterns

The pattern of checking for specific tags appears frequently:

```swift
event.tags.first(where: { $0.first == "tagname" })?[safe: 1]
```

This could be extracted to use the existing TagValidation utilities more consistently.

## Implementation Priority

1. **Highest Priority**: JSON field name constants and additional tag constants (prevents typos, improves maintainability)
2. **Medium Priority**: Lightning and Bech32 constants (consolidates domain knowledge)
3. **Lower Priority**: Documentation and error message consistency (improves developer experience)

All of these changes are:
- Non-breaking (adding constants, not changing behavior)
- Easy to test (compile-time verification)
- Improve code maintainability
- Reduce the chance of typos
- Make the codebase more consistent