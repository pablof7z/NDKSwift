import Foundation

/// Manages Cashu proof states and operations
actor CashuProofManager {
    // MARK: - Properties
    
    private var proofs: [String: CashuProof] = [:]  // secret -> proof
    private var proofsByMint: [String: Set<String>] = [:] // mint -> set of secrets
    
    // Active reservations for preventing double-spending
    private var activeReservations: [String: ReservationInfo] = [:]
    
    struct ReservationInfo {
        let proofs: [CashuProof]
        let purpose: String
        let expiry: Date
        let idempotencyKey: String
    }
    
    // MARK: - Proof Management
    
    /// Add new proofs to the manager
    func addProofs(_ newProofs: [CashuProof], mint: String) {
        for var proof in newProofs {
            proof.state = .available
            proofs[proof.secret] = proof
            proofsByMint[mint, default: []].insert(proof.secret)
        }
    }
    
    /// Get all available proofs
    func getAvailableProofs() -> [CashuProof] {
        return proofs.values.filter { proof in
            if case .available = proof.state {
                return true
            }
            return false
        }
    }
    
    /// Get available proofs for a specific mint
    func getAvailableProofs(mint: String) -> [CashuProof] {
        guard let secrets = proofsByMint[mint] else { return [] }
        
        return secrets.compactMap { proofs[$0] }.filter { proof in
            if case .available = proof.state {
                return true
            }
            return false
        }
    }
    
    /// Get all proofs grouped by mint
    func getProofsByMint() -> [String: [CashuProof]] {
        var result: [String: [CashuProof]] = [:]
        
        for (mint, secrets) in proofsByMint {
            result[mint] = secrets.compactMap { proofs[$0] }
        }
        
        return result
    }
    
    // MARK: - Proof Reservation
    
    /// Reserve proofs for a payment operation
    func reserveProofs(amount: Int64, mint: String, for purpose: String) throws -> [CashuProof] {
        let idempotencyKey = "\(purpose)-\(Date().timeIntervalSince1970)"
        
        // Check if we already have this reservation
        if let existing = activeReservations[idempotencyKey] {
            return existing.proofs
        }
        
        // Get available proofs for this mint
        let available = getAvailableProofs(mint: mint)
        
        // Select proofs
        let selected = try selectProofs(from: available, amount: amount)
        
        // Mark as reserved
        let expiry = Date().addingTimeInterval(30) // 30 second reservation
        for i in selected.indices {
            proofs[selected[i].secret]?.state = .reserved(until: expiry, for: purpose)
        }
        
        // Store reservation
        let reservation = ReservationInfo(
            proofs: selected,
            purpose: purpose,
            expiry: expiry,
            idempotencyKey: idempotencyKey
        )
        activeReservations[idempotencyKey] = reservation
        
        return selected
    }
    
    /// Confirm proofs as spent
    func confirmSpent(_ secrets: [String]) {
        for secret in secrets {
            proofs[secret]?.state = .spent
            
            // Remove from mint mapping
            for (mint, var mintSecrets) in proofsByMint {
                if mintSecrets.remove(secret) != nil {
                    proofsByMint[mint] = mintSecrets
                }
            }
        }
        
        // Remove from active reservations
        activeReservations = activeReservations.filter { _, reservation in
            !reservation.proofs.contains { secrets.contains($0.secret) }
        }
    }
    
    /// Release a reservation
    func releaseReservation(_ secrets: [String]) {
        for secret in secrets {
            if case .reserved = proofs[secret]?.state {
                proofs[secret]?.state = .available
            }
        }
        
        // Remove from active reservations
        activeReservations = activeReservations.filter { _, reservation in
            !reservation.proofs.contains { secrets.contains($0.secret) }
        }
    }
    
    /// Release expired reservations
    func releaseExpiredReservations() {
        let now = Date()
        
        // Find expired reservations
        let expired = activeReservations.filter { _, reservation in
            reservation.expiry < now
        }
        
        // Release them
        for (key, reservation) in expired {
            let secrets = reservation.proofs.map { $0.secret }
            releaseReservation(secrets)
            activeReservations.removeValue(forKey: key)
        }
    }
    
    /// Mark a proof as spent (from mint check)
    func markAsSpent(_ secret: String) {
        proofs[secret]?.state = .spent
    }
    
    // MARK: - Private Helpers
    
    /// Select proofs to meet the target amount
    private func selectProofs(from available: [CashuProof], amount: Int64) throws -> [CashuProof] {
        // Sort by amount descending for greedy selection
        let sorted = available.sorted { $0.amount > $1.amount }
        
        var selected: [CashuProof] = []
        var total: Int64 = 0
        
        // Greedy selection - take largest proofs first
        for proof in sorted {
            if total >= amount { break }
            selected.append(proof)
            total += Int64(proof.amount)
        }
        
        guard total >= amount else {
            throw CashuError.insufficientBalance(
                required: amount,
                available: available.reduce(0) { $0 + Int64($1.amount) }
            )
        }
        
        return selected
    }
}

// MARK: - Errors

enum CashuError: LocalizedError {
    case insufficientBalance(required: Int64, available: Int64)
    case noProofsAvailable
    case mintNotFound
    case proofAlreadySpent
    case invalidProof
    
    var errorDescription: String? {
        switch self {
        case .insufficientBalance(let required, let available):
            return "Insufficient balance: required \(required), available \(available)"
        case .noProofsAvailable:
            return "No proofs available"
        case .mintNotFound:
            return "Mint not found"
        case .proofAlreadySpent:
            return "Proof already spent"
        case .invalidProof:
            return "Invalid proof"
        }
    }
}