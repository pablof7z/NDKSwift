#!/usr/bin/env swift

import Foundation

/// Example demonstrating the del tag functionality in NIP-60 wallets
/// This shows how token events properly include del tags when proofs are spent

// This is a conceptual example showing how the del tag functionality works
// In a real application, you would need proper mint setup and network connectivity

func demonstrateDelTagFunctionality() {
    print("🧪 NIP-60 Del Tag Functionality Demo")
    print("=====================================\n")
    
    // Simulate proof data (in real code, these would be CashuSwift.Proof objects)
    struct SimulatedProof {
        let keysetID: String
        let amount: Int
        let secret: String
        let C: String
    }
    
    let proof1 = SimulatedProof(
        keysetID: "test-keyset",
        amount: 10,
        secret: "secret1",
        C: "C1"
    )
    
    let proof2 = SimulatedProof(
        keysetID: "test-keyset",
        amount: 20,
        secret: "secret2",
        C: "C2"
    )
    
    let mintURL = "https://mint.example.com"
    let token1EventId = "initial-token-event-123"
    
    print("1️⃣ Initial State:")
    print("   Token Event ID: \(token1EventId)")
    print("   Proof 1: 10 sats (C: \(proof1.C))")
    print("   Proof 2: 20 sats (C: \(proof2.C))")
    print("   Total: 30 sats\n")
    
    // Simulate the ownership tracking that happens in ProofStateManager
    var proofOwnership: [String: String] = [:] // proof.C -> owning event ID
    
    // Initial state: both proofs owned by token1
    proofOwnership[proof1.C] = token1EventId
    proofOwnership[proof2.C] = token1EventId
    
    print("✅ Both proofs owned by: {\(token1EventId)}\n")
    
    // Simulate spending proof1
    print("2️⃣ Spending Proof 1 (10 sats)...")
    // In real code: proofStateManager.markProofsAsDeleted([proof1])
    
    print("   Remaining proofs: 1")
    print("   Available: Proof 2 (20 sats)\n")
    
    // Key part: Get the previous owner of the remaining proof
    let previousOwnerEventId = proofOwnership[proof2.C] ?? "unknown"
    
    print("3️⃣ Creating New Token Event:")
    print("   Proofs: [Proof 2]")
    print("   Previous owner: {\(previousOwnerEventId)}")
    print("   ⚡️ DEL TAG: [\"\(previousOwnerEventId)\"]\n")
    
    // In the actual implementation, this is what happens:
    print("📝 The new token event will include:")
    print("""
    {
        "kind": 7375,
        "content": {
            "mint": "\(mintURL)",
            "proofs": [
                {
                    "id": "\(proof2.keysetID)",
                    "amount": \(proof2.amount),
                    "secret": "\(proof2.secret)",
                    "C": "\(proof2.C)"
                }
            ],
            "del": ["\(token1EventId)"]  // ← This is the key part!
        }
    }
    """)
    
    print("\n✅ Result:")
    print("   - Other clients will see the del tag")
    print("   - They'll know to ignore the old token event")
    print("   - No double-spending attempts will occur")
    print("   - Wallet state remains consistent across all clients")
}

// Run the demo
demonstrateDelTagFunctionality()