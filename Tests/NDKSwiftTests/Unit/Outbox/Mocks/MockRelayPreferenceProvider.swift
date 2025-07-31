import Foundation
@testable import NDKSwift

/// Mock implementation of RelayPreferenceProvider for testing
final class MockRelayPreferenceProvider: RelayPreferenceProvider {
    private var relayInfo: [PublicKey: NDKOutboxItem] = [:]
    private var fetchCallCount: [PublicKey: Int] = [:]
    
    /// Add relay info for a pubkey
    func setRelayInfo(for pubkey: PublicKey, info: NDKOutboxItem) {
        relayInfo[pubkey] = info
    }
    
    /// Remove relay info for a pubkey
    func removeRelayInfo(for pubkey: PublicKey) {
        relayInfo[pubkey] = nil
    }
    
    /// Get the number of times getRelaysFor was called for a pubkey
    func getFetchCount(for pubkey: PublicKey) -> Int {
        fetchCallCount[pubkey] ?? 0
    }
    
    /// Reset all fetch counts
    func resetFetchCounts() {
        fetchCallCount.removeAll()
    }
    
    /// Clear all relay info
    func clear() {
        relayInfo.removeAll()
        fetchCallCount.removeAll()
    }
    
    // MARK: - RelayPreferenceProvider
    
    func getRelaysFor(pubkey: PublicKey) async -> NDKOutboxItem? {
        fetchCallCount[pubkey, default: 0] += 1
        return relayInfo[pubkey]
    }
}