# Dead and Duplicated Code Analysis - NDKSwift

## Summary

This analysis identified several areas of dead code, duplication, and opportunities for consolidation in the NDKSwift codebase.

## 1. Major Dead Code

### MemoryCache.swift (Lines 27-390)
**CRITICAL**: The entire proof state management functionality is commented out, representing ~360 lines of dead code:
- `ProofEntry` struct
- `ProofState` enum  
- `ProofStateError` enum
- All proof-related methods: `saveProof`, `updateProofState`, `getAvailableProofs`, `selectProofs`, etc.

**Reason**: This functionality has been migrated to `ProofStateManager.swift` but the old code remains commented out.

**Action**: Delete all commented proof-related code from MemoryCache.swift

### WalletImports.swift
- **Dead Type Alias**: `public typealias CashuError = CashuSwift.CashuError` (Line 11)
- **Reason**: The type does not exist in the imported CashuSwift library
- **Action**: Remove this alias

## 2. Direct Code Duplication

### Hex String Conversion
**File**: `WalletImports.swift` (Lines 47-71)
- The `String.hexData` extension duplicates functionality from `DataHexExtensions.swift`
- Both convert hex strings to Data with identical logic
- **Action**: Remove `String.hexData` from WalletImports.swift and use `String.hexDecoded()` instead

### HexValidator Redundant Aliases
**File**: `HexValidator.swift`
- `isValidHexString` → duplicate of `isValidHex`
- `isValidHexPubkey` → duplicate of `isValid32ByteHex`
- `isValidEventId` → duplicate of `isValid32ByteHex`
- `isValidSignature` → duplicate of `isValid64ByteHex`
- **Action**: Remove these redundant aliases

## 3. Incomplete/Broken Features

### Subscription Grouping
**Files**: `NDKRelaySubscriptionManager.swift`, `InternalSubscription.swift`
- `NDKRelaySubscriptionManager` tries to access properties that don't exist on InternalSubscription:
  - `groupableDelay` (Line 56)
  - `groupableDelayType` (Line 57)
  - `isGroupable` exists but is always `true`
- **Impact**: The subscription grouping feature cannot work as intended
- **Action**: Either implement missing properties or remove incomplete grouping logic

## 4. Architectural Overlaps

### WOT (Web of Trust) Caching
**File**: `NDKSessionData.swift` (Lines 414-420)
- Contains stubbed methods: `loadCachedWOT()`, `saveWOTToCache()`
- Meanwhile, NDKCache provides general caching infrastructure
- **Action**: Implement WOT caching through NDKCache or remove stubs

### Relay Source Tracking
**Files**: `NDKEventTracker.swift`, `NDKSQLiteCache.swift`
- Two separate mechanisms track which relays events have been seen on
- `NDKEventTracker`: In-memory tracking
- `NDKSQLiteCache`: Persistent storage
- **Action**: Clarify single source of truth for relay tracking

## 5. Test Code Duplication Opportunities

While test files weren't directly analyzed, common patterns suggest:
- NDK instance setup repeated across test files
- Signer creation duplicated
- Mock data generation repeated
- Relay connection setup for integration tests

**Recommendations**:
1. Create `BaseUnitTestCase` with common NDK/cache setup
2. Create `TestFixtures` for shared test data generation
3. Create `BaseIntegrationTestCase` for relay setup
4. Enhance async test utilities

## 6. Miscellaneous Issues

### Incorrect @_exported Usage
**File**: `WalletImports.swift` (Line 8)
- `@_exported import CashuSwift` has no effect in internal files
- **Action**: Remove `@_exported` modifier

## Priority Actions

1. ~~**HIGH**: Remove ~360 lines of dead proof code from MemoryCache.swift~~ ✅ COMPLETED
2. ~~**HIGH**: Fix subscription grouping by implementing missing properties~~ ✅ COMPLETED
3. ~~**MEDIUM**: Remove duplicate hex conversion in WalletImports.swift~~ ✅ COMPLETED
4. ~~**MEDIUM**: Remove redundant HexValidator aliases~~ ✅ COMPLETED
5. **LOW**: Consolidate WOT caching approach
6. **LOW**: Clarify relay source tracking architecture

## Completed Actions (2025-01-31)

- ✅ Removed all dead proof state management code from MemoryCache.swift
- ✅ Removed duplicate String.hexData from WalletImports.swift
- ✅ Removed redundant HexValidator method aliases
- ✅ Fixed incorrect @_exported usage in WalletImports.swift
- ✅ Enhanced test infrastructure with base classes and utilities
- ✅ Fixed subscription grouping by implementing missing properties:
  - Added `isGroupable`, `groupableDelay`, and `groupableDelayType` to InternalSubscription
  - Fixed NDKRelaySubscriptionManager to properly use these properties
  - Removed conflicting property extensions from NDKRelaySubscriptionGroup
  - Created comprehensive tests for subscription grouping functionality

## Estimated Impact

Removing identified dead and duplicate code would:
- Reduce codebase by ~400+ lines
- Fix a critical bug in subscription grouping
- Improve maintainability by eliminating confusion
- Ensure consistent hex/validation utilities usage