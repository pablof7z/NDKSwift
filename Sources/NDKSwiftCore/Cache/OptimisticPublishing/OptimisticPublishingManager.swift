import Foundation


actor OptimisticPublishingManager {
    private var store: UnpublishedStore?

    init(cachePath: String?) {
        do {
            store = try UnpublishedStore(cachePath: cachePath)
        } catch {
            NDKLogger.log(.warning, category: .cache, "Failed to initialize unpublished store: \(error)")
        }
    }

    func addUnpublishedEvent(_ event: NDKEvent, publishedRelays: [String], pendingRelays: [String: String]) async throws {
        try await store?.add(event, publishedRelays: publishedRelays, pendingRelays: pendingRelays)
    }

    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        try await store?.markRelayPublished(eventId: eventId, relay: relay)
    }

    func recordPublishFailure(eventId: String, relay: String, reason: String) async throws {
        try await store?.markRelayFailed(eventId: eventId, relay: relay, reason: reason)
    }

    func removeUnpublishedEvent(eventId: String) async throws {
        try await store?.remove(eventId: eventId)
    }

    func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return await store?.getEventConfirmationState(eventId: eventId)
    }

    func getUnpublishedEvents(
        maxAge: TimeInterval = TimeConstants.unpublishedEventRetryWindow,
        limit: Int? = nil
    ) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        guard let store = store else { return [] }
        return await store.getUnpublishedEvents(maxAge: maxAge, limit: limit)
    }

    /// Get the stream of unpublished store changes
    var unpublishedChanges: AsyncStream<UnpublishedChange>? {
        get async {
            await store?.changes
        }
    }

    /// Get all unpublished event records with full relay status
    func getAllUnpublishedRecords() async -> [String: UnpublishedStore.UnpublishedEventRecord] {
        guard let store = store else { return [:] }
        return await store.getAllRecords()
    }

    func clear() async throws {
        try await store?.clear()
    }
}
