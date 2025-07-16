import Foundation
import CashuSwift

/// Monitors wallet health and relay synchronization status
/// This component tracks relay event consistency and wallet state health
public actor WalletHealthMonitor {
    // MARK: - Types
    
    public struct RelayHealth: Sendable {
        public let relay: NDKRelay
        public let knownEvents: Int
        public let missingEvents: [String]
        public let extraEvents: [String]  // Events that were deleted but relay still has
        public let isHealthy: Bool
        
        public init(relay: NDKRelay, knownEvents: Int, missingEvents: [String], extraEvents: [String], isHealthy: Bool) {
            self.relay = relay
            self.knownEvents = knownEvents
            self.missingEvents = missingEvents
            self.extraEvents = extraEvents
            self.isHealthy = isHealthy
        }
    }
    
    public struct WalletHealthStatus: Sendable {
        public let isHealthy: Bool
        public let lastCheckTime: Date
        public let relayHealth: [RelayHealth]
        public let totalEvents: Int
        public let syncedRelays: Int
        public let outOfSyncRelays: Int
    }
    
    // MARK: - Properties
    
    private let eventManager: WalletEventManager
    private let ndk: NDK
    private var relayEventSets: [String: Set<String>] = [:] // relay URL -> event IDs
    private var lastHealthCheck: Date?
    
    // MARK: - Initialization
    
    public init(eventManager: WalletEventManager, ndk: NDK) {
        self.eventManager = eventManager
        self.ndk = ndk
    }
    
    // MARK: - Health Monitoring
    
    /// Check the health of all wallet relays
    public func checkRelayHealth(walletRelays: [NDKRelay]) async -> [RelayHealth] {
        var results: [RelayHealth] = []
        
        // Get canonical event set from event manager
        let canonicalEventSet = await calculateCanonicalEventSet()
        
        for relay in walletRelays {
            let relayEvents = relayEventSets[relay.url] ?? Set<String>()
            
            // Find missing events (in canonical but not on relay)
            let missingEvents = Array(canonicalEventSet.subtracting(relayEvents))
            
            // Find extra events (on relay but not in canonical)
            let extraEvents = Array(relayEvents.subtracting(canonicalEventSet))
            
            let isHealthy = missingEvents.isEmpty && extraEvents.isEmpty
            
            let health = RelayHealth(
                relay: relay,
                knownEvents: relayEvents.count,
                missingEvents: missingEvents,
                extraEvents: extraEvents,
                isHealthy: isHealthy
            )
            
            results.append(health)
        }
        
        lastHealthCheck = Date()
        return results
    }
    
    /// Get overall wallet health status
    public func getWalletHealthStatus(walletRelays: [NDKRelay]) async -> WalletHealthStatus {
        let relayHealth = await checkRelayHealth(walletRelays: walletRelays)
        let canonicalEventSet = await calculateCanonicalEventSet()
        
        let syncedRelays = relayHealth.filter { $0.isHealthy }.count
        let outOfSyncRelays = relayHealth.filter { !$0.isHealthy }.count
        
        return WalletHealthStatus(
            isHealthy: outOfSyncRelays == 0,
            lastCheckTime: lastHealthCheck ?? Date(),
            relayHealth: relayHealth,
            totalEvents: canonicalEventSet.count,
            syncedRelays: syncedRelays,
            outOfSyncRelays: outOfSyncRelays
        )
    }
    
    /// Update relay event set for tracking
    public func updateRelayEventSet(relay: String, events: Set<String>) {
        relayEventSets[relay] = events
    }
    
    /// Track event on relay
    public func trackEventOnRelay(eventId: String, relay: String) {
        relayEventSets[relay, default: Set<String>()].insert(eventId)
    }
    
    /// Remove event from relay tracking
    public func removeEventFromRelay(eventId: String, relay: String) {
        relayEventSets[relay]?.remove(eventId)
    }
    
    /// Clear all relay event sets
    public func clearRelayEventSets() {
        relayEventSets.removeAll()
    }
    
    /// Get relay event set
    public func getRelayEventSet(relay: String) -> Set<String> {
        return relayEventSets[relay] ?? Set<String>()
    }
    
    // MARK: - Private Methods
    
    private func calculateCanonicalEventSet() async -> Set<String> {
        // Current wallet state = what we have locally that's not deleted
        let current = await eventManager.getCurrentTokenEventIds()
        var result = Set<String>()
        for eventId in current {
            if !(await eventManager.shouldFilterEvent(eventId)) {
                result.insert(eventId)
            }
        }
        return result
    }
    
    // MARK: - Proof State Monitoring
    
    /// Check and reconcile proof states with all mints
    /// This queries each mint for the status of our proofs and updates our local state accordingly
    public func checkAndReconcileProofStates(
        proofStateManager: ProofStateManager,
        mints: [String: CashuSwift.Mint],
        signer: NDKSigner
    ) async throws -> ProofReconciliationResult {
        print("🔍 Starting proof state reconciliation...")
        
        // Group proofs by mint for efficient checking
        var proofsByMint: [String: [(proof: CashuSwift.Proof, entryKey: String)]] = [:]
        
        let entries = await proofStateManager.getAllEntries()
        for entry in entries where entry.state == ProofStateManager.ProofState.available {
            if proofsByMint[entry.mint] == nil {
                proofsByMint[entry.mint] = []
            }
            proofsByMint[entry.mint]?.append((proof: entry.proof, entryKey: entry.proof.C))
        }
        
        // Track spent proofs we discover
        var spentProofs: [CashuSwift.Proof] = []
        var spentProofsByMint: [String: [CashuSwift.Proof]] = [:]
        var pendingProofs: [CashuSwift.Proof] = []
        var errorCount = 0
        
        // Check each mint
        for (mintURL, proofEntries) in proofsByMint {
            guard let mint = mints[mintURL] else {
                print("⚠️ Mint not found for URL: \(mintURL)")
                errorCount += 1
                continue
            }
            
            let proofs = proofEntries.map { $0.proof }
            
            do {
                print("🏦 Checking \(proofs.count) proofs with mint: \(mintURL)")
                
                // Query mint for proof states
                let states = try await CashuSwift.check(proofs, mint: mint)
                
                // Process results
                for (index, state) in states.enumerated() {
                    let proofEntry = proofEntries[index]
                    
                    switch state {
                    case .spent:
                        print("💸 Found spent proof: \(proofEntry.proof.C.suffix(8))")
                        spentProofs.append(proofEntry.proof)
                        if spentProofsByMint[mintURL] == nil {
                            spentProofsByMint[mintURL] = []
                        }
                        spentProofsByMint[mintURL]?.append(proofEntry.proof)
                        
                    case .pending:
                        print("⏳ Found pending proof: \(proofEntry.proof.C.suffix(8))")
                        pendingProofs.append(proofEntry.proof)
                        
                    case .unspent:
                        // Proof is still good, no action needed
                        break
                    }
                }
                
            } catch {
                print("❌ Error checking mint \(mintURL): \(error)")
                errorCount += 1
            }
        }
        
        // Update proof state manager with spent proofs
        if !spentProofs.isEmpty {
            print("🗑️ Marking \(spentProofs.count) proofs as spent")
            await proofStateManager.markProofsAsDeleted(spentProofs)
            
            // Update wallet state if we found spent proofs
            if !spentProofsByMint.isEmpty {
                // Create state changes for each mint
                for (mint, proofs) in spentProofsByMint {
                    let stateChange = WalletStateChange(
                        store: [],
                        destroy: proofs,
                        mint: mint,
                        memo: "Reconciliation - remove spent proofs"
                    )
                    
                    let tokenChange = await WalletStateCalculator.calculateNewState(
                        stateChange: stateChange,
                        proofStateManager: proofStateManager
                    )
                    
                    _ = try await eventManager.updateTokenEvents(
                        tokenChange: tokenChange,
                        proofStateManager: proofStateManager,
                        signer: signer
                    )
                }
            }
        }
        
        let totalChecked = proofsByMint.values.flatMap { $0 }.count
        print("✅ Reconciliation complete. Checked: \(totalChecked), Spent: \(spentProofs.count), Pending: \(pendingProofs.count)")
        
        return ProofReconciliationResult(
            totalChecked: totalChecked,
            spentProofs: spentProofs,
            pendingProofs: pendingProofs,
            errors: errorCount
        )
    }
}

// MARK: - Supporting Types

/// Result of proof reconciliation with mints
public struct ProofReconciliationResult {
    public let totalChecked: Int
    public let spentProofs: [CashuSwift.Proof]
    public let pendingProofs: [CashuSwift.Proof]
    public let errors: Int
}