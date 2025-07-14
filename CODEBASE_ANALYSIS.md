# NDKSwift Codebase Analysis

## 1. Broken Functionality / Failing Tests

### Current Issues:
- **CashuRelayHealthSimpleTest.swift** - Compilation errors:
  - Missing `await` keywords for async methods (`recordEventFromRelay`)
  - Reference to undefined property `currentTokenEventIds` in test extension
  
- **MockSigner.swift** - Does not conform to NDKSigner protocol:
  - Missing static `signerType` property
  - Missing `serialize()` method
  - Missing static `deserialize(_:ndk:)` method

### Action Items:
- Fix test compilation errors by adding missing `await` keywords
- Update MockSigner to fully implement NDKSigner protocol
- Run full test suite to identify other failing tests

## 2. Duplicate Code Patterns

### Payment Request/Confirmation Protocols
- `NDKPaymentRequest` and `PaymentRequest` protocols in different files
- `NDKPaymentConfirmation` and `PaymentConfirmation` protocols duplicated
- Location: `/Wallet/NDKWallet.swift` and `/Zaps/NDKPaymentProvider.swift`
- **Impact**: Confusion about which protocol to implement, potential type mismatches

### Event Processing
- Multiple implementations of event fetching logic across:
  - `NDKOutboxManager`
  - `NDKRelayPoolExtensions`
  - Main `NDK` class

### Cache Operations
- Similar cache patterns repeated across different cache implementations
- Could benefit from shared base implementation

## 3. Single Responsibility Principle (SRP) Violations

### NDK.swift (1,326 lines)
The main NDK class has grown too large and handles:
- Relay pool management
- Event publishing/fetching
- Subscription management
- Profile management
- Cache coordination
- Authentication
- Wallet integration
- Zap management

**Recommendation**: Break into focused components:
- `NDKEventManager` - Event operations
- `NDKRelayCoordinator` - Relay management
- `NDKSubscriptionCoordinator` - Subscription handling

### NDKCashuWallet.swift (961 lines)
Handles too many responsibilities:
- Token management
- Mint interactions
- Event processing
- Relay health monitoring
- Balance tracking
- Transaction processing
- Event subscription

**Recommendation**: Extract to separate components:
- `CashuTokenManager`
- `CashuMintInteractor`
- `CashuEventProcessor`

### NDKRelay.swift (812 lines)
Combines multiple concerns:
- WebSocket connection management
- Message parsing/serialization
- Subscription tracking
- Connection state management
- Error handling

**Recommendation**: Separate into:
- `RelayConnection` - WebSocket handling
- `RelayMessageProcessor` - Message parsing
- `RelaySubscriptionTracker` - Subscription management

## 4. Over-Engineered Components

### Excessive Handler Pattern
The wallet system uses many small handler structs:
- `NutzapHandler`
- `WalletConfigHandler`
- `DeleteEventHandler`
- `TokenEventHandler`
- `QuoteEventHandler`
- `SpendingHistoryHandler`

**Issue**: Each handler is a separate type for what could be simple methods. This creates unnecessary complexity and indirection.

**Recommendation**: Consolidate into a single `WalletEventProcessor` with methods for each event type.

### Wrapper Types
- `WalletAdapterPaymentProvider` - Unnecessary wrapper around wallet functionality

### Protocol Proliferation
Several protocols appear to have single implementations:
- `MintCache` protocol with likely single implementation
- `WalletEventHandler` protocol used only internally

**Recommendation**: Remove protocols that don't provide value through multiple implementations or testing benefits.

### Complex Extension Chains
- 70+ extensions across 41 files
- Many extensions could be consolidated into their primary types

## 5. Other Observations

### Large Files Requiring Attention:
1. **NDKSQLiteCache.swift** (1,000 lines) - Consider breaking into query builders and data mappers
2. **NDKSubscriptionManager.swift** (551 lines) - Extract subscription filtering logic
3. **NDKZapManager.swift** (572 lines) - Separate zap creation from payment processing

### Positive Patterns Found:
- Good use of Swift concurrency (async/await, actors)
- Consistent error handling patterns
- Well-structured protocol definitions for core abstractions

## Recommendations Summary

1. **Immediate Fixes**:
   - Fix test compilation errors (DONE - fixed await keywords and MockSigner)
   - Update MockSigner implementation (DONE - added missing protocol requirements)
   - Remove duplicate protocol definitions (PaymentRequest vs NDKPaymentRequest)

2. **Refactoring Priorities**:
   - Break down NDK.swift into focused managers
   - Consolidate wallet event handlers
   - Simplify NDKRelay into separate concerns

3. **Simplification Opportunities**:
   - Remove single-implementation protocols
   - Consolidate related extensions
   - Eliminate unnecessary wrapper types like WalletAdapterPaymentProvider

4. **Architecture Improvements**:
   - Implement clear separation of concerns
   - Reduce class/struct sizes to under 300 lines
   - Use composition over complex inheritance/protocol chains

## Additional Findings

### Type Naming Inconsistencies
- Some types use NDK prefix (NDKEvent, NDKFilter) while others don't (PaymentRequest, CashuProofRequest)
- This creates confusion about which types are part of the core NDK API

### Testing Infrastructure Issues
- Tests have duplicate MockRelay implementations causing compilation conflicts
- Missing mock implementations for various protocols
- Test helpers accessing private properties instead of using public APIs