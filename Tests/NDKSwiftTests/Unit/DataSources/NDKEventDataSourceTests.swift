@testable import NDKSwiftCore
@testable import NDKSwiftUI
import XCTest

/// Tests for NDKEventDataSource event batching behavior
final class NDKEventDataSourceTests: NDKTestCase {
    var ndk: NDK!
    var cache: MockCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = MockCache()
        ndk = NDK(cache: cache)
    }

    override func tearDown() async throws {
        ndk = nil
        cache = nil
        try await super.tearDown()
    }

    /// Test that NDKEventDataSource updates its events array in batches, not one-by-one
    /// This ensures UI counters don't flicker through every intermediate value
    @MainActor
    func testEventsArrayUpdatesInBatches() async throws {
        // Given - 1000 events in cache
        let eventCount = 1000
        var cachedEvents: [NDKEvent] = []
        for i in 0..<eventCount {
            let event = EventTestFactory.createEvent(
                kind: EventKind.textNote,
                content: "Event \(i)"
            )
            cachedEvents.append(event)
        }
        await cache.setMockEvents(cachedEvents)

        // When - create event data source
        let dataSource = NDKEventDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [1])
        )

        // Track how many times events.count changes
        var countUpdates: [Int] = []
        let observationTask = Task { @MainActor in
            while !Task.isCancelled {
                let currentCount = dataSource.events.count
                if countUpdates.isEmpty || countUpdates.last != currentCount {
                    countUpdates.append(currentCount)
                }
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }
        }

        // Wait for events to load
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        observationTask.cancel()

        // Then - events array should update in LARGE batches
        // With 1000 events that can be read in ~16ms, we should see just a few updates
        // Ideally: 0 → 1000 (2 updates) or at most 0 → 500 → 1000 (3 updates)
        let finalCount = dataSource.events.count
        XCTAssertGreaterThan(finalCount, 900,
            "Should have loaded most/all events. Got \(finalCount)")

        XCTAssertLessThan(countUpdates.count, 5,
            "Events array should update in very large batches. Got \(countUpdates.count) updates for \(eventCount) events. Updates: \(countUpdates)")
    }
}

// MARK: - Mock Cache

actor MockCache: NDKCache {
    private var mockEvents: [NDKEvent] = []

    func setMockEvents(_ events: [NDKEvent]) {
        mockEvents = events
    }

    func saveEvent(_ event: NDKEvent) async throws {
        mockEvents.append(event)
    }

    func getEvent(id: String) async -> NDKEvent? {
        mockEvents.first { $0.id == id }
    }

    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        mockEvents
    }

    func observeEvents(matching filter: NDKFilter, includeExisting: Bool) async -> AsyncThrowingStream<[NDKEvent], Error> {
        let events = self.mockEvents
        return AsyncThrowingStream { continuation in
            Task {
                if includeExisting {
                    // Yield all events in ONE batch (simulating cache behavior)
                    continuation.yield(events)
                }
                continuation.finish()
            }
        }
    }

    func observeProfile(pubkey: String, includeExisting: Bool) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func deleteEvent(id: String) async throws {}
    func clear() async throws {}
    func clearPersisted() async throws {}
}
