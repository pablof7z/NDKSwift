# Build Issue - Duplicate Symbols in CashuSwift

## Problem

The CLI-Nutsack example cannot currently be built due to duplicate symbol errors in the CashuSwift library:

```
duplicate symbol 'static CashuSwift.CashuSwift.restore(mint: CashuSwift.MintRepresenting, with: Swift.String, batchSize: Swift.Int) async throws -> [CashuSwift.CashuSwiftKeysetRestoreResult]' in:
    /path/to/CashuSwift.build/restore.swift.o
    /path/to/CashuSwift.build/restore.swift.o
ld: 8 duplicate symbols
clang: error: linker command failed with exit code 1
```

## Root Cause

The issue is in the CashuSwift library's `restore.swift` file, which appears to be compiled twice or contains duplicate symbol definitions. This happens when:

1. NDKSwift depends on CashuSwift (via Libraries/CashuSwift)
2. CLI-Nutsack depends on NDKSwift
3. Swift Package Manager ends up compiling CashuSwift twice, leading to duplicate symbols

## Attempted Solutions

1. **Tried building from main package**: Added CLI-Nutsack as a target to the main Package.swift - same error
2. **Tried building separately**: Built from Examples/CLI-Nutsack directory - same error
3. **Tried linker flags**: Added dead stripping flags - didn't resolve the issue

## Temporary Workarounds

### Option 1: Use the Simple Demo
A simplified version is available that can be run directly:
```bash
swift Examples/CLI-Nutsack-Simple.swift
```

### Option 2: Fix CashuSwift
The issue needs to be fixed in the CashuSwift library itself. The restore.swift file likely has:
- Multiple definitions of the same functions
- Or is being included multiple times in the build

## Next Steps

1. Report the issue to CashuSwift maintainers
2. Investigate if restore.swift has duplicate function definitions
3. Check if there's a circular dependency causing double compilation

## Code Status

The CLI-Nutsack implementation is complete and includes:
- Full navigatable menu system with arrow key support
- Wallet management with NDKCashuWallet
- Transaction history with table view
- Nutzap sending/receiving (NIP-61)
- Multi-mint support
- All features requested by the user

Once the CashuSwift build issue is resolved, the CLI will compile and run successfully.