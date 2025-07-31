# Wallet Common Imports

This directory contains common utilities and imports for wallet-related functionality in NDKSwift.

## WalletImports.swift

The `WalletImports.swift` file provides a centralized location for commonly used wallet dependencies and utilities.

### Usage

Instead of importing multiple dependencies in each wallet file:

```swift
// Before
import Foundation
import CashuSwift
```

You can now use a single import:

```swift
// After
import WalletImports
```

### What's Included

1. **Automatic Exports**
   - `Foundation` - Swift Foundation framework
   - `CashuSwift` - Cashu ecash library

2. **Type Aliases**
   - `CashuToken` - Alias for `CashuSwift.Token`
   - `CashuProof` - Alias for `CashuSwift.Proof`
   - `CashuKeyset` - Alias for `CashuSwift.Keyset`
   - `CashuMint` - Alias for `CashuSwift.Mint`

3. **Common Constants**
   - `WalletConstants.defaultUnit` - Default unit for transactions ("sat")
   - `WalletConstants.maxMintRetries` - Maximum retry attempts for mint operations
   - `WalletConstants.mintTimeout` - Default timeout for mint operations
   - `WalletConstants.maxProofsPerTransaction` - Maximum proofs per transaction
   - `WalletConstants.mintInfoCacheDuration` - Cache duration for mint info

4. **Utility Extensions**
   - Use `Data.hexString` from DataHexExtensions.swift - Convert data to hex string
   - Use `String.hexDecoded()` from DataHexExtensions.swift - Convert hex string to data

### Migration Guide

To migrate existing wallet files to use the common imports:

1. Replace individual imports with `import WalletImports`
2. Update any fully qualified type names (e.g., `CashuSwift.Token`) to use the type aliases
3. Consider using the provided constants instead of hardcoded values

### Adding New Common Imports

When adding new commonly used imports or utilities:

1. Add the import with `@_exported` to automatically re-export it
2. Create type aliases for commonly used types
3. Add any shared constants to `WalletConstants`
4. Document the addition in this README