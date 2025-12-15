import Foundation

// MARK: - Observer Types for Reactive Support

private struct EventObserver {
    let filter: NDKFilter
    let continuation: AsyncThrowingStream<[NDKEvent], Error>.Continuation
    let includeExisting: Bool
    var hasEmittedExisting: Bool = false
}

private struct ProfileObserver {
    let pubkey: String
    let continuation: AsyncThrowingStream<NDKUserMetadata?, Error>.Continuation
    let includeExisting: Bool
    var hasEmittedExisting: Bool = false
}

/// Comprehensive in-memory cache implementation for testing and temporary use
public actor MemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    private var unpublishedEventRelays: [String: Set<String>] = [:]
    private var eventCreationTimes: [String: Date] = [:]
    private var decryptedContent: LRUCache<String, String>

    // Generic key-value store: namespace -> key -> value
    private var kvStore: [String: [String: Data]] = [:]

    // Tombstone cache for deletion events that arrive before the original event
    private var deletionTombstones: [String: Date] = [:]
    private let tombstoneTTL: TimeInterval = NetworkConstants.tombstoneTTL

    // Cleanup task for tombstones
    private var cleanupTask: Task<Void, Never>?

    // Reactive observation support
    private var eventObservers: [UUID: EventObserver] = [:]
    private var profileObservers: [UUID: ProfileObserver] = [:]

    public init() {
        // Initialize LRU cache with configured item limit for decrypted content
        decryptedContent = LRUCache(capacity: NetworkConstants.defaultCacheCapacity)

        // Start periodic cleanup of expired tombstones
        Task { [weak self] in
            await self?.startTombstoneCleanup()
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - Observer Management

    private func addEventObserver(id: UUID, observer: EventObserver) {
        eventObservers[id] = observer
    }

    private func removeEventObserver(id: UUID) {
        eventObservers.removeValue(forKey: id)
    }

    private func markObserverAsEmittedExisting(id: UUID) {
        if var observer = eventObservers[id] {
            observer.hasEmittedExisting = true
            eventObservers[id] = observer
        }
    }

    private func notifyEventObservers(for event: NDKEvent) {
        for (_, observer) in eventObservers {
            // Check if event matches filter
            if observer.filter.matches(event: event) {
                observer.continuation.yield([event])
            }
        }
    }

    // MARK: - Event Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "MemoryCache: Skipping ephemeral event (kind: \(event.kind)): \(event.id)")
            return
        }

        events[event.id] = event

        // Notify observers about the saved event
        notifyEventObservers(for: event)
    }

    public func getEvent(id: String) async -> NDKEvent? {
        let event = events[id]
        NDKLogger.log(.trace, category: .cache, "Retrieved event \(id): \(event != nil ? "found" : "not found")")
        return event
    }

    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []

        for event in events.values {
            if filter.matches(event: event) {
                results.append(event)
            }
        }

        // Apply limit if specified
        if let limit = filter.limit, limit > 0 {
            results = Array(results.prefix(limit))
        }

        // Sort by created_at descending
        // Extract created_at values for sorting
        let sortedResults = await withTaskGroup(of: (NDKEvent, Timestamp).self) { group in
            for event in results {
                group.addTask {
                    let timestamp = event.createdAt
                    return (event, timestamp)
                }
            }

            var eventWithTimestamps: [(NDKEvent, Timestamp)] = []
            for await result in group {
                eventWithTimestamps.append(result)
            }

            // Sort by timestamp descending
            eventWithTimestamps.sort { $0.1 > $1.1 }

            return eventWithTimestamps.map { $0.0 }
        }

        results = sortedResults

        return results
    }

    public func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
        NDKLogger.log(.debug, category: .cache, "Deleted event \(id)")
    }

    // MARK: - Cache Management

    public func clear() async throws {
        events.removeAll()
        eventConfirmations.removeAll()
        kvStore.removeAll()
        await decryptedContent.clear()
        NDKLogger.log(.info, category: .cache, "Cleared all cache data")
    }

    // MARK: - Optimistic Publishing Support

    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        events[eventId] = event
        eventConfirmations[eventId] = .optimistic
        unpublishedEventRelays[eventId] = relays
        eventCreationTimes[eventId] = Date()
        NDKLogger.log(.debug, category: .cache, "Added unpublished event \(eventId) for relays: \(relays.joined(separator: ", "))")
    }

    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if let existingState = eventConfirmations[eventId] {
            switch existingState {
            case .optimistic:
                eventConfirmations[eventId] = .confirmed(fromRelay: relay)
                NDKLogger.log(.debug, category: .cache, "Confirmed event \(eventId) on relay \(relay)")
            case .confirmed:
                NDKLogger.log(.trace, category: .cache, "Event \(eventId) already confirmed")
            }
        } else {
            // Event not found, might have been confirmed directly
            eventConfirmations[eventId] = .confirmed(fromRelay: relay)
            NDKLogger.log(.debug, category: .cache, "Marked event \(eventId) as confirmed on relay \(relay)")
        }
    }

    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return eventConfirmations[eventId]
    }

    public func getUnpublishedEvents(maxAge: TimeInterval = TimeConstants.unpublishedEventRetryWindow, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Date().addingTimeInterval(-maxAge)
        var results: [(event: NDKEvent, targetRelays: Set<String>)] = []

        for (eventId, confirmationState) in eventConfirmations {
            // Only include optimistic events
            guard case .optimistic = confirmationState else { continue }

            // Check age constraint
            if let creationTime = eventCreationTimes[eventId], creationTime < cutoffTime {
                continue
            }

            // Get the event and relays
            guard let event = events[eventId],
                  let targetRelays = unpublishedEventRelays[eventId] else { continue }

            results.append((event: event, targetRelays: targetRelays))
        }

        // Sort by creation time (newest first)
        results.sort { lhs, rhs in
            let lhsTime = eventCreationTimes[lhs.event.id] ?? Date.distantPast
            let rhsTime = eventCreationTimes[rhs.event.id] ?? Date.distantPast
            return lhsTime > rhsTime
        }

        // Apply limit if specified
        if let limit = limit, limit > 0 {
            results = Array(results.prefix(limit))
        }

        NDKLogger.log(.trace, category: .cache, "Found \(results.count) unpublished events (maxAge: \(maxAge)s)")
        return results
    }

    // MARK: - Decrypted Content Cache

    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        let key = "\(eventId):\(viewerPubkey)"
        return await decryptedContent.get(key)
    }

    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        let key = "\(eventId):\(viewerPubkey)"
        await decryptedContent.set(key, value: content)
        NDKLogger.log(.trace, category: .cache, "Cached decrypted content for event \(eventId) viewer \(viewerPubkey)")
    }

    public func clearDecryptedContent() async {
        await decryptedContent.clear()
        NDKLogger.log(.debug, category: .cache, "Cleared all decrypted content")
    }

    public func clearDecryptedContent(for viewerPubkey: String) async {
        // Get all keys that end with the viewer pubkey
        let allItems = await decryptedContent.allItems()
        for (key, _) in allItems where key.hasSuffix(":\(viewerPubkey)") {
            await decryptedContent.delete(key)
        }
        NDKLogger.log(.debug, category: .cache, "Cleared decrypted content for viewer \(viewerPubkey)")
    }

    // MARK: - Debug Helpers

    public func eventCount() async -> Int {
        return events.count
    }

    public func unconfirmedEventCount() async -> Int {
        return eventConfirmations.values.filter { !$0.isConfirmed }.count
    }

    // MARK: - Generic Key-Value Store

    public func setValue(_ value: Data, forKey key: String, namespace: String) async throws {
        if kvStore[namespace] == nil {
            kvStore[namespace] = [:]
        }
        kvStore[namespace]?[key] = value
        NDKLogger.log(.trace, category: .cache, "Set KV value for \(namespace):\(key)")
    }

    public func getValue(forKey key: String, namespace: String) async -> Data? {
        let value = kvStore[namespace]?[key]
        NDKLogger.log(.trace, category: .cache, "Get KV value for \(namespace):\(key): \(value != nil ? "found" : "not found")")
        return value
    }

    public func deleteValue(forKey key: String, namespace: String) async throws {
        kvStore[namespace]?.removeValue(forKey: key)
        NDKLogger.log(.trace, category: .cache, "Deleted KV value for \(namespace):\(key)")
    }

    public func getValues(namespace: String, keyPrefix: String?) async -> [String: Data] {
        guard let namespaceStore = kvStore[namespace] else {
            return [:]
        }

        if let prefix = keyPrefix {
            let filtered = namespaceStore.filter { $0.key.hasPrefix(prefix) }
            NDKLogger.log(.trace, category: .cache, "Retrieved \(filtered.count) KV values for \(namespace) with prefix \(prefix)")
            return filtered
        }

        NDKLogger.log(.trace, category: .cache, "Retrieved \(namespaceStore.count) KV values for \(namespace)")
        return namespaceStore
    }

    // MARK: - Negentropy Support

    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []

        for event in events.values {
            // Check time range
            if event.createdAt < from || event.createdAt >= to {
                continue
            }

            // Apply filter if provided
            if let filter = filter {
                if !filter.matches(event: event) {
                    continue
                }
            }

            results.append(event)
        }

        // Sort by timestamp for consistent ordering
        let sorted = results.sorted { $0.createdAt < $1.createdAt }
        NDKLogger.log(.trace, category: .cache, "Found \(sorted.count) events in range [\(from), \(to))")
        return sorted
    }

    public func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        var results: [(id: String, timestamp: Timestamp)] = []

        for event in events.values {
            // Check time range
            if event.createdAt < from || event.createdAt >= to {
                continue
            }

            // Apply filter if provided
            if let filter = filter {
                if !filter.matches(event: event) {
                    continue
                }
            }

            results.append((id: event.id, timestamp: event.createdAt))
        }

        // Sort by timestamp for consistent ordering
        let sorted = results.sorted { $0.timestamp < $1.timestamp }
        NDKLogger.log(.trace, category: .cache, "Found \(sorted.count) event IDs in range [\(from), \(to))")
        return sorted
    }

    public func hasEvents(ids: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]

        for id in ids {
            result[id] = events[id] != nil
        }

        let foundCount = result.values.filter { $0 }.count
        NDKLogger.log(.trace, category: .cache, "Checked \(ids.count) event IDs, found \(foundCount)")
        return result
    }

    // MARK: - Event Processing with Deletion Support

    public func processEvent(
        _ event: NDKEvent,
        from _: String,
        subscriptionId _: String
    ) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "MemoryCache: Skipping ephemeral event in processEvent (kind: \(event.kind)): \(event.id)")
            return
        }

        // Check if event was tombstoned by a deletion event
        if deletionTombstones[event.id] != nil {
            // Event was deleted before it arrived, don't save it
            NDKLogger.log(.debug, category: .cache, "Event \(event.id) was tombstoned, not saving")
            return
        }

        // Process deletion events (NIP-09) before saving
        if event.kind == EventKind.deletion {
            await processDeletionEvent(event)
        }

        // Save the event (this will also notify observers)
        try await saveEvent(event)
    }

    /// Process a kind:5 deletion event according to NIP-09
    private func processDeletionEvent(_ deletionEvent: NDKEvent) async {
        // Extract event IDs to delete from "e" tags
        let eventIdsToDelete = deletionEvent.tags.eventIds

        guard !eventIdsToDelete.isEmpty else { return }

        let now = Date()

        // Process each event to be deleted
        for eventId in eventIdsToDelete {
            // Check if the event exists in cache
            if let existingEvent = events[eventId] {
                // Verify the deletion event author matches the original event author
                if existingEvent.pubkey == deletionEvent.pubkey {
                    // Delete the event from cache
                    do {
                        try await deleteEvent(id: eventId)
                        NDKLogger.log(.debug, category: .cache, "Deleted event \(eventId)")
                    } catch {
                        NDKLogger.log(.error, category: .cache, "Failed to delete event \(eventId): \(error)")
                    }
                }
            } else {
                // Event not in cache yet - add to tombstone cache
                // This prevents the event from being added if it arrives later
                deletionTombstones[eventId] = now
            }
        }
    }

    // MARK: - Tombstone Cleanup

    private func startTombstoneCleanup() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                // Wait for cleanup interval (1 hour)
                try? await Task.sleep(nanoseconds: UInt64(TimeConstants.hour * 1_000_000_000))

                guard !Task.isCancelled else { break }

                // Clean up expired tombstones
                await self?.cleanupExpiredTombstones()
            }
        }
    }

    private func cleanupExpiredTombstones() async {
        let now = Date()
        var expiredKeys: [String] = []

        for (eventId, tombstoneDate) in deletionTombstones {
            if now.timeIntervalSince(tombstoneDate) > tombstoneTTL {
                expiredKeys.append(eventId)
            }
        }

        for key in expiredKeys {
            deletionTombstones.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            NDKLogger.log(.debug, category: .cache, "Cleaned up \(expiredKeys.count) expired tombstones")
        }
    }

    // MARK: - Reactive Observation

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool = true
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        AsyncThrowingStream { continuation in
            let observerId = UUID()

            Task {
                // Create and store observer
                let observer = EventObserver(
                    filter: filter,
                    continuation: continuation,
                    includeExisting: includeExisting
                )
                self.addEventObserver(id: observerId, observer: observer)

                // If includeExisting, emit current matching events
                if includeExisting {
                    do {
                        let existingEvents = try await self.queryEvents(filter)
                        if !existingEvents.isEmpty {
                            continuation.yield(existingEvents)
                        }
                        self.markObserverAsEmittedExisting(id: observerId)
                    } catch {
                        continuation.finish(throwing: error)
                        self.removeEventObserver(id: observerId)
                        return
                    }
                }
            }

            continuation.onTermination = { _ in
                Task {
                    await self.removeEventObserver(id: observerId)
                }
            }
        }
    }

    public func observeProfile(
        pubkey: String,
        includeExisting: Bool = true
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        // For MemoryCache, we don't have a built-in change notification system
        // So we'll create a stream that emits existing profile and then completes
        AsyncThrowingStream { continuation in
            Task {
                // If includeExisting, emit current profile
                if includeExisting {
                    // First yield nil to indicate we're starting
                    continuation.yield(nil)

                    // Then fetch the actual profile
                    do {
                        let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.metadata], limit: 1)
                        let profileEvents = try await self.queryEvents(filter)
                        if let profileEvent = profileEvents.first {
                            let metadata = NDKUserMetadata(event: profileEvent)
                            continuation.yield(metadata)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                // Since MemoryCache doesn't have change notifications,
                // we complete the stream after emitting existing profile
                continuation.finish()
            }
        }
    }
}
