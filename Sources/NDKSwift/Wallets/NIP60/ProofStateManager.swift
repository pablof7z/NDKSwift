import Foundation
import CashuSwift

// MARK: - Extensions for CashuSwift.Proof to support Set operations
extension CashuSwift.Proof: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        // Use the proof's C value as the unique identifier for hashing
        hasher.combine(C)
    }
}

/// Manages the state of Cashu proofs within a wallet
/// This includes tracking availability, reservations for concurrent operations, and selection algorithms
public actor ProofStateManager {
    // MARK: - Types
    
    public enum ProofState: Equatable {
        case available
        case reserved   // For concurrent operations
        case deleted    // Spent proofs
    }
    
    public struct ProofEntry {
        let proof: CashuSwift.Proof
        var state: ProofState
        let mint: String
        var ownerEventId: String? // Which event currently owns this proof
        var ownerTimestamp: Timestamp? // Timestamp of the owner event
    }
    
    // MARK: - Properties
    
    private var proofState: [String: ProofEntry] = [:] // proof.C -> entry
    
    // MARK: - Public Methods
    
    /// Add a proof to the state manager
    func addProof(_ proof: CashuSwift.Proof, mint: String, state: ProofState = .available, eventId: String? = nil, timestamp: Timestamp? = nil) {
        // Check if proof already exists
        if let existing = proofState[proof.C] {
            // Only update if the new event is newer (higher timestamp)
            if let newTimestamp = timestamp, let existingTimestamp = existing.ownerTimestamp {
                if newTimestamp <= existingTimestamp {
                    // Existing owner is newer or same age, don't update ownership
                    return
                }
            }
        }
        
        proofState[proof.C] = ProofEntry(
            proof: proof,
            state: state,
            mint: mint,
            ownerEventId: eventId,
            ownerTimestamp: timestamp
        )
    }
    
    /// Update the state of a proof
    func updateProofState(_ proofC: String, state: ProofState) {
        if var entry = proofState[proofC] {
            entry.state = state
            proofState[proofC] = entry
        }
    }
    
    /// Update ownership of existing proofs to a new event
    func updateProofOwnership(_ proofs: [CashuSwift.Proof], eventId: String, timestamp: Timestamp) {
        print("ProofStateManager.updateProofOwnership - Updating \(proofs.count) proofs to event \(eventId)")
        for proof in proofs {
            if var entry = proofState[proof.C] {
                let previousOwner = entry.ownerEventId ?? "none"
                // Only update if the new event is newer
                if let existingTimestamp = entry.ownerTimestamp {
                    if timestamp <= existingTimestamp {
                        print("  Proof \(proof.C): NOT updating owner from \(previousOwner) to \(eventId) - existing timestamp is newer")
                        continue // Don't update, existing owner is newer
                    }
                }
                entry.ownerEventId = eventId
                entry.ownerTimestamp = timestamp
                proofState[proof.C] = entry
                print("  Proof \(proof.C): Updated owner from \(previousOwner) to \(eventId)")
            } else {
                print("  Proof \(proof.C): WARNING - proof not found in state!")
            }
        }
    }
    
    /// Get all available proofs
    func getAvailableProofs() -> [CashuSwift.Proof] {
        return proofState.values
            .filter { $0.state == .available }
            .map { $0.proof }
    }
    
    /// Get available proofs for a specific mint
    func getAvailableProofs(mint: String) -> [CashuSwift.Proof] {
        return proofState.values
            .filter { $0.state == .available && $0.mint == mint }
            .map { $0.proof }
    }
    
    /// Get all proofs grouped by mint
    func getAvailableProofsByMint() -> [String: [CashuSwift.Proof]] {
        var result: [String: [CashuSwift.Proof]] = [:]
        
        for entry in proofState.values where entry.state == .available {
            result[entry.mint, default: []].append(entry.proof)
        }
        
        return result
    }
    
    /// Get total balance
    func getTotalBalance() -> Int64 {
        return proofState.values
            .filter { $0.state == .available }
            .reduce(0) { $0 + Int64($1.proof.amount) }
    }
    
    /// Get balance for a specific mint
    func getBalance(mint: String) -> Int64 {
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mint }
        let balance = availableProofs.reduce(0) { $0 + Int64($1.proof.amount) }
        print("ProofStateManager.getBalance(mint: \(mint)) - found \(availableProofs.count) available proofs, balance: \(balance)")
        return balance
    }
    
    /// Get all mints that have sufficient balance for the given amount
    /// Returns mints sorted by balance (highest first)
    func getMintsWithSufficientBalance(amount: Int64) -> [String] {
        let availableProofsByMint = getAvailableProofsByMint()
        
        return availableProofsByMint
            .compactMap { (mintURL, proofs) in
                let balance = proofs.reduce(0) { $0 + Int64($1.amount) }
                return balance >= amount ? (mint: mintURL, balance: balance) : nil
            }
            .sorted { $0.balance > $1.balance }
            .map { $0.mint }
    }
    
    /// Select proofs for a given amount from a specific mint
    /// Uses a greedy algorithm to minimize the number of proofs and change
    func selectProofs(amount: Int64, mint: String) -> [CashuSwift.Proof] {
        var selected: [CashuSwift.Proof] = []
        var total: Int64 = 0
        
        // Get available proofs from state, filtered by mint
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mint }
            .map { $0.proof }
        
        // Sort proofs by amount (ascending) to minimize change
        let sortedProofs = availableProofs.sorted { $0.amount < $1.amount }
        
        for proof in sortedProofs {
            if total >= amount {
                break
            }
            selected.append(proof)
            total += Int64(proof.amount)
        }
        
        return total >= amount ? selected : []
    }
    
    /// Reserve proofs for concurrent operations
    func reserveProofs(_ proofs: [CashuSwift.Proof]) throws {
        for proof in proofs {
            guard var entry = proofState[proof.C], entry.state == .available else {
                // Rollback any reservations we've made so far
                for reservedProof in proofs where reservedProof.C != proof.C {
                    if var reservedEntry = proofState[reservedProof.C], reservedEntry.state == .reserved {
                        reservedEntry.state = .available
                        proofState[reservedProof.C] = reservedEntry
                    }
                }
                throw ProofStateError.proofNotAvailable(proofC: proof.C)
            }
            entry.state = .reserved
            proofState[proof.C] = entry
        }
    }
    
    /// Release reserved proofs back to available
    func releaseProofs(_ proofs: [CashuSwift.Proof]) {
        for proof in proofs {
            if var entry = proofState[proof.C], entry.state == .reserved {
                entry.state = .available
                proofState[proof.C] = entry
            }
        }
    }
    
    /// Mark proofs as deleted/spent
    func markProofsAsDeleted(_ proofs: [CashuSwift.Proof]) {
        for proof in proofs {
            if var entry = proofState[proof.C] {
                entry.state = .deleted
                proofState[proof.C] = entry
            }
        }
    }
    
    /// Mark proofs owned by a deleted event as deleted
    func markProofsOwnedByEventAsDeleted(_ eventId: String) -> [CashuSwift.Proof] {
        var deletedProofs: [CashuSwift.Proof] = []
        
        for (proofC, entry) in proofState {
            // Only delete if this event still owns the proof
            if entry.ownerEventId == eventId && entry.state != .deleted {
                var updatedEntry = entry
                updatedEntry.state = .deleted
                proofState[proofC] = updatedEntry
                deletedProofs.append(entry.proof)
            }
        }
        
        return deletedProofs
    }
    
    /// Remove deleted proofs from state
    func pruneDeletedProofs() {
        proofState = proofState.filter { $0.value.state != .deleted }
    }
    
    /// Clear all proof state
    func clear() {
        proofState.removeAll()
    }
    
    /// Get proof state for debugging
    func getProofState(for proofC: String) -> ProofState? {
        return proofState[proofC]?.state
    }
    
    /// Get all proof entries (for reconciliation)
    func getAllEntries() -> [ProofEntry] {
        return Array(proofState.values)
    }
    
    /// Get proof entries for a specific mint
    func getEntries(mint: String) -> [ProofEntry] {
        return proofState.values.filter { $0.mint == mint }
    }
    
    /// Reconcile proof states after checking with mint
    func reconcileProofStates(spentProofCs: Set<String>) {
        for proofC in spentProofCs {
            if var entry = proofState[proofC] {
                entry.state = .deleted
                proofState[proofC] = entry
            }
        }
    }
    
    /// Get the owner event ID for a single proof
    /// Returns the event ID that owns this proof, or nil if no owner
    func getOwnerEventId(for proof: CashuSwift.Proof) -> String? {
        return proofState[proof.C]?.ownerEventId
    }
    
    /// Get the mint for a proof
    func getMintForProof(_ proof: CashuSwift.Proof) -> String? {
        return proofState[proof.C]?.mint
    }
    
    /// Get the owner event IDs for a set of proofs
    /// Returns a set of event IDs that previously owned these proofs
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
    
    /// Get all proofs (available and reserved) that belong to a specific event
    /// This is crucial for proper proof rollover when creating new token events
    func getProofsForEvent(_ eventId: String) -> [CashuSwift.Proof] {
        let proofs = proofState.values
            .filter { entry in
                entry.ownerEventId == eventId && entry.state != .deleted
            }
            .map { $0.proof }
        print("ProofStateManager.getProofsForEvent(\(eventId)) - Found \(proofs.count) proofs")
        return proofs
    }
    
    /// Get all available proofs that belong to a specific event
    func getAvailableProofsForEvent(_ eventId: String) -> [CashuSwift.Proof] {
        let proofs = proofState.values
            .filter { entry in
                entry.ownerEventId == eventId && entry.state == .available
            }
            .map { $0.proof }
        print("ProofStateManager.getAvailableProofsForEvent(\(eventId)) - Found \(proofs.count) available proofs")
        for proof in proofs {
            print("  - Proof C: \(proof.C), amount: \(proof.amount)")
        }
        return proofs
    }
}

// MARK: - Errors

enum ProofStateError: LocalizedError {
    case proofNotAvailable(proofC: String)
    
    var errorDescription: String? {
        switch self {
        case .proofNotAvailable(let proofC):
            return "Proof not available for reservation: \(proofC)"
        }
    }
}

// MARK: - NDKError Extension

extension NDKError {
    static func fromProofStateError(_ error: ProofStateError) -> NDKError {
        switch error {
        case .proofNotAvailable(let proofC):
            return NDKError.invalidProof("Proof not available for reservation: \(proofC)")
        }
    }
}