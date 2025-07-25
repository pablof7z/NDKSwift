import Foundation
import CashuSwift

/// Handles nutzap redemption during wallet startup
/// Ensures we wait for both nutzap and spending history EOSE before redeeming
actor StartupNutzapRedemption {
    private let wallet: NIP60Wallet
    private let eventManager: WalletEventManager

    // Completion handler called when redemption is complete
    var onCompletion: (() async -> Void)?

    // Track EOSE state
    private var nutzapEoseReceived = false
    private var spendingHistoryEoseReceived = false

    // Collect nutzaps during initial sync
    private var pendingNutzaps: [NDKEvent] = []

    // Track which nutzaps were marked as redeemed by 7376 events
    private var nutzapsMarkedRedeemed: Set<String> = []

    init(wallet: NIP60Wallet, eventManager: WalletEventManager) {
        self.wallet = wallet
        self.eventManager = eventManager
    }

    /// Track nutzap event during initial sync
    func trackNutzap(_ event: NDKEvent) {
        NDKLogger.log(.debug, category: .wallet, "Tracking nutzap for startup redemption: \(event.id)")
        pendingNutzaps.append(event)
    }

    /// Process spending history event to mark nutzaps as redeemed
    func processSpendingHistory(_ event: NDKEvent) {
        // Check for redeemed nutzap events in the clear tags
        for tag in event.tags {
            if tag.count >= 4 && tag[0] == NostrConstants.TagName.event && tag[3] == NostrConstants.Marker.redeemed {
                let redeemedNutzapId = tag[1]
                NDKLogger.log(.info, category: .wallet, "📝 Marking nutzap \(redeemedNutzapId) as already redeemed from history")
                nutzapsMarkedRedeemed.insert(redeemedNutzapId)
            }
        }
    }

    /// Mark that nutzap EOSE was received
    func markNutzapEoseReceived() {
        NDKLogger.log(.info, category: .wallet, "✅ Nutzap EOSE received")
        nutzapEoseReceived = true
        checkAndRedeemIfReady()
    }

    /// Mark that spending history EOSE was received
    func markSpendingHistoryEoseReceived() {
        NDKLogger.log(.info, category: .wallet, "✅ Spending history EOSE received")
        spendingHistoryEoseReceived = true
        checkAndRedeemIfReady()
    }

    /// Check if both EOSE received and redeem pending nutzaps
    private func checkAndRedeemIfReady() {
        guard nutzapEoseReceived && spendingHistoryEoseReceived else {
            NDKLogger.log(.debug, category: .wallet, "⏳ Waiting for both EOSE (nutzap: \(nutzapEoseReceived), history: \(spendingHistoryEoseReceived))")
            return
        }

        // Filter out already redeemed nutzaps
        let unredeemed = pendingNutzaps.filter { !nutzapsMarkedRedeemed.contains($0.id) }

        NDKLogger.log(.info, category: .wallet, "🚀 Starting batch redemption: \(unredeemed.count) unredeemed nutzaps out of \(pendingNutzaps.count) total")

        // Start redemption task
        Task {
            await redeemNutzaps(unredeemed)
            // Clear state after processing is complete
            reset()
            // Notify completion
            await onCompletion?()
        }
    }

    /// Redeem a batch of nutzaps
    private func redeemNutzaps(_ nutzaps: [NDKEvent]) async {
        for nutzap in nutzaps {
            do {
                NDKLogger.log(.info, category: .wallet, "💸 Attempting to redeem nutzap \(nutzap.id)")
                try await wallet.processIncomingNutzap(nutzap)
                NDKLogger.log(.info, category: .wallet, "✅ Successfully redeemed nutzap \(nutzap.id)")
            } catch {
                NDKLogger.log(.error, category: .wallet, "❌ Failed to redeem nutzap \(nutzap.id): \(error)")
                // Update status to failed
                let redemptionError: NutzapRedemptionError
                if let nutzapError = error as? NutzapRedemptionError {
                    redemptionError = nutzapError
                } else {
                    redemptionError = .unknownError(error.localizedDescription)
                }

                await eventManager.updateNutzapStatus(
                    nutzap.id,
                    status: .failed(
                        error: redemptionError,
                        attempts: 1,
                        lastAttempt: Timestamp.now
                    )
                )
            }
        }
    }

    /// Reset state for next startup
    func reset() {
        nutzapEoseReceived = false
        spendingHistoryEoseReceived = false
        pendingNutzaps.removeAll()
        nutzapsMarkedRedeemed.removeAll()
    }
}