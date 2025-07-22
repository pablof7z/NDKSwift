# Low-Risk Improvements Round 3

This document summarizes the third round of low-risk improvements to the NDKSwift codebase.

## Improvements Made

### 1. Extended NostrJSONConstants with Cashu/wallet fields
- Added constants for Cashu proof fields: `amount`, `secret`, `C`, `proofs`, `proof`, `mint`, `unit`
- Added wallet event fields: `direction`, `state`
- Eliminates hardcoded JSON field names in wallet and Cashu-related code

### 2. Updated code to use constants instead of hardcoded strings
- `NDKNutzap` now uses NostrTagConstants for tag names
- `NDKZapRequest` now uses NostrTagConstants for tag names
- `WalletEventManager` now uses NostrTagConstants for tag names
- `WalletTransactionHistory` now uses NostrTagConstants for tag names
- `Nutzap` now uses NostrJSONConstants for notification userInfo

## Next Improvements Identified

### 1. Replace duplicate NostrTag enum with NostrTagConstants (High Priority)
- 7 files currently use the duplicate `NostrTag` enum from TagValidation.swift
- This violates DRY principle as NostrTagConstants already defines these constants
- Files to update:
  - NDKList.swift
  - NDKCashuEvents.swift
  - NDKEvent.swift
  - NDKBlockedMintsEvent.swift
  - NDKEventExtensions.swift
  - WalletEventProcessor.swift

### 2. Extract hex validation constants
- Magic numbers 32 and 64 appear frequently for hex validation
- Should be defined as constants in CryptoConstants

### 3. Consolidate JSON parsing patterns
- The pattern `string.data(using: .utf8)` + `JSONDecoder().decode()` appears 17+ times
- Could be extracted to a String extension method

## Benefits

- Reduced code duplication
- Improved maintainability
- Consistent use of constants
- Better type safety
- Easier to update values in one place