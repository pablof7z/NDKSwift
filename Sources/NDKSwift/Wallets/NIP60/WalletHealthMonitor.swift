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
            var missingEvents: [String] = []
            var knownEvents = 0

            // Check each canonical event using NDK's event tracker
            for eventId in canonicalEventSet {
                let seenOnRelays = await ndk.eventTracker.getSeenOnRelays(eventId: eventId)
                if seenOnRelays.contains(relay.url) {
                    knownEvents += 1
                } else {
                    // Also check if it was successfully published to this relay
                    let publishedRelays = await ndk.eventTracker.getSuccessfullyPublishedRelays(eventId: eventId)
                    if publishedRelays.contains(relay.url) {
                        knownEvents += 1
                    } else {
                        missingEvents.append(eventId)
                    }
                }
            }

            // Trust that relays handle deletion events properly (NIP-09)
            // so we don't track "extra events"
            let isHealthy = missingEvents.isEmpty

            let health = RelayHealth(
                relay: relay,
                knownEvents: knownEvents,
                missingEvents: missingEvents,
                extraEvents: [], // Not tracking as per requirements
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

        let syncedRelays = relayHealth.count { $0.isHealthy }
        let outOfSyncRelays = relayHealth.count { !$0.isHealthy }

        return WalletHealthStatus(
            isHealthy: outOfSyncRelays == 0,
            lastCheckTime: lastHealthCheck ?? Date(),
            relayHealth: relayHealth,
            totalEvents: canonicalEventSet.count,
            syncedRelays: syncedRelays,
            outOfSyncRelays: outOfSyncRelays
        )
    }

    // Note: Relay tracking is now handled by NDKEventTracker
    // These methods have been removed to avoid duplication

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
        mintManager: MintManager,
        signer: NDKSigner
    ) async throws -> ProofReconciliationResult {
        NDKLogger.log(.debug, category: .wallet, "🔍 Starting proof state reconciliation...")

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
            // Try to get mint from current snapshot first
            var mint = mints[mintURL]

            // If not found, try to load it and add to mint manager
            if mint == nil, let url = URL(string: mintURL) {
                do {
                    NDKLogger.log(.debug, category: .wallet, "🔄 Auto-loading mint: \(mintURL)")
                    let loadedMint = try await mintManager.loadMint(url: url)

                    // Add to mint manager (following the pattern from requestMintQuote)
                    await mintManager.addMintURL(url: url)
                    // Store keysets in mint manager
                    for keyset in loadedMint.keysets {
                        await mintManager.addKeyset(keyset)
                    }

                    mint = loadedMint
                    NDKLogger.log(.debug, category: .wallet, "✅ Successfully loaded mint: \(mintURL)")
                } catch {
                    NDKLogger.log(.debug, category: .wallet, "⚠️ Failed to load mint \(mintURL): \(error)")
                    errorCount += 1
                    continue
                }
            }

            guard let mint = mint else {
                NDKLogger.log(.debug, category: .wallet, "⚠️ Mint not found for URL: \(mintURL)")
                errorCount += 1
                continue
            }

            let proofs = proofEntries.map { $0.proof }

            do {
                NDKLogger.log(.debug, category: .wallet, "🏦 Checking \(proofs.count) proofs with mint: \(mintURL)")

                // Query mint for proof states
                let states = try await CashuSwift.check(proofs, mint: mint)

                // Process results
                for (index, state) in states.enumerated() {
                    let proofEntry = proofEntries[index]

                    switch state {
                    case .spent:
                        NDKLogger.log(.debug, category: .wallet, "💸 Found spent proof: \(proofEntry.proof.C.suffix(8))")
                        spentProofs.append(proofEntry.proof)
                        if spentProofsByMint[mintURL] == nil {
                            spentProofsByMint[mintURL] = []
                        }
                        spentProofsByMint[mintURL]?.append(proofEntry.proof)

                    case .pending:
                        NDKLogger.log(.debug, category: .wallet, "⏳ Found pending proof: \(proofEntry.proof.C.suffix(8))")
                        pendingProofs.append(proofEntry.proof)

                    case .unspent:
                        // Proof is still good, no action needed
                        break
                    }
                }

            } catch {
                NDKLogger.log(.debug, category: .wallet, "❌ Error checking mint \(mintURL): \(error)")
                errorCount += 1
            }
        }

        // Update proof state manager with spent proofs
        if !spentProofs.isEmpty {
            NDKLogger.log(.debug, category: .wallet, "🗑️ Marking \(spentProofs.count) proofs as spent")
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
                        signer: signer,
                        relays: []
                    )
                }
            }
        }

        let totalChecked = proofsByMint.values.flatMap { $0 }.count
        NDKLogger.log(.debug, category: .wallet, "✅ Reconciliation complete. Checked: \(totalChecked), Spent: \(spentProofs.count), Pending: \(pendingProofs.count)")

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