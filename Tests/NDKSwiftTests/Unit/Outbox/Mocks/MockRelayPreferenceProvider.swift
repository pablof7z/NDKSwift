import Foundation
@testable import NDKSwiftCore

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

    func getRelaysSyncFor(pubkey: String, type _: RelayListType) async -> NDKOutboxItem? {
        return relayInfo[pubkey]
    }

    func getRelaysFor(pubkey: String, maxAge _: TimeInterval, type _: RelayListType) async throws -> NDKOutboxItem? {
        fetchCallCount[pubkey, default: 0] += 1
        return relayInfo[pubkey]
    }

    func getAllCachedItems() async -> [NDKOutboxItem] {
        return Array(relayInfo.values)
    }

    func track(pubkey: String, readRelays: Set<String>, writeRelays: Set<String>, source: RelayListSource, emitDiscoveryEvent _: Bool) async {
        let item = NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelays.map { RelayInfo(url: $0) }),
            writeRelays: Set(writeRelays.map { RelayInfo(url: $0) }),
            fetchedAt: Date(),
            source: source
        )
        relayInfo[pubkey] = item
    }

    func clear() async {
        relayInfo.removeAll()
        fetchCallCount.removeAll()
    }

    func cleanupExpired() async {
        // No-op for testing
    }
}
