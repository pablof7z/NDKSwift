# NIP-60 Del Tag Fix Documentation

## Overview

This document describes the fix implemented to ensure NDKSwift properly includes `del` tags in NIP-60 token events when proofs are spent, as required by the specification.

## The Problem

When a Cashu wallet spends some proofs from a token event and creates a new token event with the remaining proofs, NIP-60 requires that the new token event include a `del` tag referencing the superseded token event. This tells other clients that the old token event should be ignored.

### Example Scenario:
1. Token1 contains proof1 (10 sats) and proof2 (20 sats)
2. User spends proof1
3. A new Token2 should be created with:
   - Only proof2 (20 sats)
   - A `del: ["token1-id"]` tag

Without the `del` tag, other clients would see both Token1 and Token2, potentially leading to double-spending attempts.

## The Solution

### 1. Enhanced Proof Ownership Tracking

Added ownership tracking to `ProofStateManager`:

```swift
public struct ProofEntry {
    let proof: CashuSwift.Proof
    var state: ProofState
    let mint: String
    var ownerEventId: String?      // Which event owns this proof
    var ownerTimestamp: Timestamp?  // When it was claimed
}
```

### 2. New Method to Get Previous Owners

Added `getOwnerEventIds` method to `ProofStateManager`:

```swift
func getOwnerEventIds(for proofs: [CashuSwift.Proof]) -> Set<String> {
    var ownerIds = Set<String>()
    
    for proof in proofs {
        if let entry = proofState[proof.C],
           let ownerEventId = entry.ownerEventId {
            ownerIds.insert(ownerEventId)
        }
    }
    
    return ownerIds
}
```

### 3. Updated Token Event Creation

Modified `WalletEventManager.updateTokenEvents` to include `del` tags:

```swift
// Get the previous owner event IDs for these proofs
let previousOwnerEventIds = await proofStateManager.getOwnerEventIds(for: proofs)

// Only include events that are currently active
let deletedEventIds = Array(previousOwnerEventIds.intersection(currentTokenEventIds))

// Pass to token event creation
let eventId = try await saveTokenEvent(
    token: token,
    signer: signer,
    deletedEventIds: deletedEventIds.isEmpty ? nil : deletedEventIds
)
```

## How It Works

1. **Proof Addition**: When processing token events, each proof's ownership is tracked with the event ID and timestamp
2. **Spending Proofs**: When proofs are spent, they're marked as deleted but ownership info is retained
3. **Creating New Token**: When creating a new token event with remaining proofs:
   - The system checks which event previously owned these proofs
   - If that event is still active, it's included in the `del` tag
   - The new event properly supersedes the old one

## Testing

### Unit Test Example

```swift
func testDelTagScenario() async {
    let manager = ProofStateManager()
    
    // Initial state: Token1 has two proofs
    let proof1 = CashuSwift.Proof(keysetID: "k1", amount: 10, secret: "s1", C: "C1")
    let proof2 = CashuSwift.Proof(keysetID: "k1", amount: 20, secret: "s2", C: "C2")
    
    let token1Id = "token-event-001"
    await manager.addProof(proof1, mint: "mint1", eventId: token1Id, timestamp: 1000)
    await manager.addProof(proof2, mint: "mint1", eventId: token1Id, timestamp: 1000)
    
    // Spend proof1
    await manager.markProofsAsDeleted([proof1])
    
    // Get owner of remaining proof
    let previousOwners = await manager.getOwnerEventIds(for: [proof2])
    
    // Should know that proof2 belonged to token1
    XCTAssertEqual(previousOwners.first, token1Id)
    
    // New token event should include: del: ["token-event-001"]
}
```

### Integration Testing

To test the full integration:

1. Create a wallet with initial proofs
2. Spend some proofs using the wallet's `update()` method
3. Verify the published token events include proper `del` tags
4. Verify other clients can correctly process the superseded events

## Benefits

1. **NIP-60 Compliance**: Fully compliant with the specification
2. **Prevents Double-Spending**: Other clients know which tokens to ignore
3. **Proper State Sync**: Wallet state remains consistent across clients
4. **Timestamp-based Conflict Resolution**: Handles out-of-order event processing

## Implementation Notes

- The fix is backward compatible - old events without ownership info still work
- Timestamp comparison ensures newer events always win in conflicts
- The system only includes `del` tags when actually superseding active events
- No redundant deletion events are created when `del` tags suffice

## Future Improvements

1. Add comprehensive integration tests with mock relay infrastructure
2. Add metrics to track del tag usage and effectiveness
3. Consider adding a reconciliation mechanism for missing del tags in historical data