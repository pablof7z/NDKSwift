@testable import NDKSwiftCore
import NDKSwiftSQLite
import XCTest

final class CacheObservationTests: XCTestCase {
    var ndk: NDK!
    var sqliteCache: NDKSQLiteCache!

    override func setUp() async throws {
        try await super.setUp()
        // Create SQLite cache with a temporary path
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db").path
        sqliteCache = try await NDKSQLiteCache(path: tempPath, debugMode: true)
        ndk = NDK(cache: sqliteCache)
    }

    override func tearDown() async throws {
        try await sqliteCache.clear()
        try await super.tearDown()
    }

    func testCacheObservationReceivesEventsFromNetwork() async throws {
        try await performAsyncTest(timeout: 5.0) { [weak self] in
            guard let self = self else { return }

            // Create a cache-only subscription
            let cacheFilter = NDKFilter(kinds: [1])
            var uniqueEventIds = Set<String>()
            var observationCount = 0

            let cacheTask = Task {
                let eventStream = await self.sqliteCache.observeEvents(
                    matching: cacheFilter,
                    includeExisting: true
                )

                do {
                    for try await events in eventStream {
                        observationCount += 1
                        for event in events {
                            uniqueEventIds.insert(event.id)
                        }
                        print("Cache observation #\(observationCount): received \(events.count) total events")
                    }
                } catch {
                    XCTFail("Cache observation error: \(error)")
                }
            }

            // Give the cache observer time to set up
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Create and save some test events
            let testEvents = try self.createTestEvents(count: 3)
            for event in testEvents {
                try await self.sqliteCache.saveEvent(event)
            }

            // Give time for events to propagate
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // Cancel the cache task
            cacheTask.cancel()

            // Verify we received the correct unique events
            XCTAssertFalse(uniqueEventIds.isEmpty, "Cache should have received events")
            XCTAssertEqual(uniqueEventIds.count, testEvents.count, "Cache should have received all unique events")
            // We expect at least 3 observations (one for each saved event)
            XCTAssertGreaterThanOrEqual(observationCount, 3, "Should have received at least one observation per saved event")
        }
    }

    func testCacheObservationWithFilter() async throws {
        try await performAsyncTest(timeout: 5.0) { [weak self] in
            guard let self = self else { return }

            // Create a specific filter for kind 1 from a specific author
            let testAuthor = "test-author-pubkey"
            let cacheFilter = NDKFilter(
                authors: [testAuthor],
                kinds: [1]
            )
            var uniqueMatchingEventIds = Set<String>()
            var observationCount = 0

            let cacheTask = Task {
                let eventStream = await self.sqliteCache.observeEvents(
                    matching: cacheFilter,
                    includeExisting: false // Don't include existing
                )

                do {
                    for try await events in eventStream {
                        observationCount += 1
                        for event in events {
                            // Verify the event matches our filter
                            if event.pubkey == testAuthor && event.kind == 1 {
                                uniqueMatchingEventIds.insert(event.id)
                            }
                        }
                        print("Filter observation #\(observationCount): received \(events.count) matching events")
                    }
                } catch {
                    XCTFail("Cache observation error: \(error)")
                }
            }

            // Give the cache observer time to set up
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Create events from different authors
            let matchingEvent = try self.createTestEvent(author: testAuthor, kind: 1)
            let nonMatchingEvent1 = try self.createTestEvent(author: "other-author", kind: 1)
            let nonMatchingEvent2 = try self.createTestEvent(author: testAuthor, kind: 4)

            // Save all events
            try await self.sqliteCache.saveEvent(matchingEvent)
            try await self.sqliteCache.saveEvent(nonMatchingEvent1)
            try await self.sqliteCache.saveEvent(nonMatchingEvent2)

            // Give time for events to propagate
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // Cancel the cache task
            cacheTask.cancel()

            // Verify only matching event was received
            XCTAssertEqual(uniqueMatchingEventIds.count, 1, "Cache should have received only one unique matching event")
            XCTAssertTrue(uniqueMatchingEventIds.contains(matchingEvent.id), "Cache should have received the matching event")
            // Each save triggers an observation
            XCTAssertGreaterThanOrEqual(observationCount, 1, "Should have received at least one observation")
        }
    }

    func testIncludeExistingParameter() async throws {
        try await performAsyncTest(timeout: 5.0) { [weak self] in
            guard let self = self else { return }

            // Pre-save some events
            let existingEvents = try self.createTestEvents(count: 2)
            for event in existingEvents {
                try await self.sqliteCache.saveEvent(event)
            }

            // Test with includeExisting = true
            var eventsWithExisting: [NDKEvent] = []
            let filter = NDKFilter(kinds: [1])

            let taskWithExisting = Task {
                let eventStream = await self.sqliteCache.observeEvents(
                    matching: filter,
                    includeExisting: true
                )

                do {
                    for try await events in eventStream {
                        eventsWithExisting.append(contentsOf: events)
                        if eventsWithExisting.count >= 2 {
                            break // Got the existing events
                        }
                    }
                } catch {
                    XCTFail("Cache observation error: \(error)")
                }
            }

            // Give time to receive existing events
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            taskWithExisting.cancel()

            // Test with includeExisting = false
            var eventsWithoutExisting: [NDKEvent] = []

            let taskWithoutExisting = Task {
                let eventStream = await self.sqliteCache.observeEvents(
                    matching: filter,
                    includeExisting: false
                )

                do {
                    for try await events in eventStream {
                        eventsWithoutExisting.append(contentsOf: events)
                    }
                } catch {
                    XCTFail("Cache observation error: \(error)")
                }
            }

            // Give time to see if any existing events are received
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            // Now add a new event
            let newEvent = try self.createTestEvent()
            try await self.sqliteCache.saveEvent(newEvent)

            // Give time for new event to propagate
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            taskWithoutExisting.cancel()

            // Verify results
            XCTAssertGreaterThanOrEqual(eventsWithExisting.count, 2, "Should have received existing events with includeExisting=true")
            XCTAssertEqual(eventsWithoutExisting.count, 1, "Should have received only new event with includeExisting=false")
        }
    }

    // MARK: - Helper Methods

    private func createTestEvents(count: Int) throws -> [NDKEvent] {
        return try (0 ..< count).map { index in
            try createTestEvent(content: "Test event \(index)")
        }
    }

    private func createTestEvent(
        author: String = "test-author",
        kind: UInt32 = 1,
        content: String = "Test content"
    ) throws -> NDKEvent {
        return EventTestFactory.createEvent(
            kind: Int(kind),
            content: content,
            tags: [],
            pubkey: author,
            createdAt: Timestamp.now
        )
    }
}
