@testable import NDKSwiftCore

import XCTest

@available(iOS 17.0, macOS 14.0, *)
final class NDKMetaSubscriptionTests: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    var tempDbPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-sub-test-\(UUID().uuidString).db").path
        cache = try await NDKSQLiteCache(path: tempDbPath, debugMode: true)
        ndk = NDK(cache: cache, outboxEnabled: false)
    }

    override func tearDown() async throws {
        if let cache = cache {
            try await cache.clear()
        }
        ndk = nil
        cache = nil
        if let tempDbPath = tempDbPath {
            try? FileManager.default.removeItem(atPath: tempDbPath)
        }
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    @MainActor
    func testMetaSubscriptionInitialization() async throws {
        let filter = NDKFilter(authors: ["test_pubkey"], kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        XCTAssertEqual(metaSub.events.count, 0)
        XCTAssertEqual(metaSub.count, 0)
        XCTAssertFalse(metaSub.eosed)
        XCTAssertEqual(metaSub.sort, .tagTime)

        await metaSub.stop()
    }

    @MainActor
    func testMetaSubscriptionCustomSort() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter, sort: .count)

        XCTAssertEqual(metaSub.sort, .count)

        await metaSub.stop()
    }

    // MARK: - Sort Mode Tests

    @MainActor
    func testSortModeChange() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter, sort: .tagTime)

        XCTAssertEqual(metaSub.sort, .tagTime)

        metaSub.sort = .count
        XCTAssertEqual(metaSub.sort, .count)

        metaSub.sort = .time
        XCTAssertEqual(metaSub.sort, .time)

        metaSub.sort = .uniqueAuthors
        XCTAssertEqual(metaSub.sort, .uniqueAuthors)

        await metaSub.stop()
    }

    // MARK: - Clear Tests

    @MainActor
    func testClearResetsState() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        await metaSub.clear()

        XCTAssertEqual(metaSub.events.count, 0)
        XCTAssertFalse(metaSub.eosed)

        await metaSub.stop()
    }

    // MARK: - Stop Tests

    @MainActor
    func testStopCancelsSubscription() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        // Should not throw
        await metaSub.stop()

        // Should be safe to call multiple times
        await metaSub.stop()
    }

    // MARK: - Events Tagging Tests

    @MainActor
    func testEventsTaggingReturnsEmptyArrayForUnknownEvent() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        let unknownEvent = NDKEvent(
            id: "unknown_event_id",
            pubkey: "some_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Unknown event",
            sig: "test_sig"
        )

        let pointers = await metaSub.eventsTagging(unknownEvent)
        XCTAssertEqual(pointers.count, 0)

        await metaSub.stop()
    }

    // MARK: - Factory Method Tests

    @MainActor
    func testMetaSubscribeFactoryMethod() async throws {
        let filter = NDKFilter(authors: ["test_pubkey"], kinds: [6, 16])
        let metaSub = ndk.metaSubscribe(filter: filter, sort: .count)

        XCTAssertEqual(metaSub.sort, .count)
        XCTAssertEqual(metaSub.events.count, 0)

        await metaSub.stop()
    }

    // MARK: - Thread Safety Tests

    @MainActor
    func testConcurrentAccessToEvents() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        // Concurrent reads should be safe
        await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { @MainActor in
                    metaSub.events.count
                }
            }

            for await count in group {
                XCTAssertGreaterThanOrEqual(count, 0)
            }
        }

        await metaSub.stop()
    }

    @MainActor
    func testConcurrentEventsTaggingCalls() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        let testEvent = NDKEvent(
            id: "test_event",
            pubkey: "some_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test",
            sig: "sig"
        )

        // Concurrent calls to eventsTagging should be safe
        await withTaskGroup(of: [NDKEvent].self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    await metaSub.eventsTagging(testEvent)
                }
            }

            for await pointers in group {
                XCTAssertNotNil(pointers)
            }
        }

        await metaSub.stop()
    }

    @MainActor
    func testConcurrentSortChanges() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        let sortModes: [NDKMetaSubscriptionSort] = [.time, .count, .tagTime, .uniqueAuthors]

        // Rapid sort changes should not crash
        for _ in 0 ..< 20 {
            for mode in sortModes {
                metaSub.sort = mode
            }
        }

        // Give async tasks time to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        await metaSub.stop()
    }

    @MainActor
    func testConcurrentClearCalls() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        // Multiple concurrent clears should be safe
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { @MainActor in
                    await metaSub.clear()
                }
            }
        }

        XCTAssertEqual(metaSub.events.count, 0)

        await metaSub.stop()
    }
}

// MARK: - High Concurrency Stress Tests

@available(iOS 17.0, macOS 14.0, *)
final class NDKMetaSubscriptionStressTests: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    var tempDbPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-sub-stress-test-\(UUID().uuidString).db").path
        cache = try await NDKSQLiteCache(path: tempDbPath, debugMode: true)
        ndk = NDK(cache: cache, outboxEnabled: false)
    }

    override func tearDown() async throws {
        if let cache = cache {
            try await cache.clear()
        }
        ndk = nil
        cache = nil
        if let tempDbPath = tempDbPath {
            try? FileManager.default.removeItem(atPath: tempDbPath)
        }
        try await super.tearDown()
    }

    @MainActor
    func testHighConcurrencyStress() async throws {
        let filter = NDKFilter(kinds: [6])
        let metaSub = NDKMetaSubscription(ndk: ndk, filter: filter)

        // Hammer the subscription with concurrent operations
        await withTaskGroup(of: Void.self) { group in
            // Concurrent reads of events
            for _ in 0 ..< 50 {
                group.addTask { @MainActor in
                    _ = metaSub.events
                    _ = metaSub.count
                    _ = metaSub.eosed
                }
            }

            // Concurrent eventsTagging calls
            let testEvent = NDKEvent(
                id: "stress_test_event",
                pubkey: "pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                tags: [],
                content: "Test",
                sig: "sig"
            )

            for _ in 0 ..< 50 {
                group.addTask {
                    _ = await metaSub.eventsTagging(testEvent)
                }
            }

            // Concurrent sort changes
            let sortModes: [NDKMetaSubscriptionSort] = [.time, .count, .tagTime, .uniqueAuthors]
            for i in 0 ..< 20 {
                group.addTask { @MainActor in
                    metaSub.sort = sortModes[i % sortModes.count]
                }
            }
        }

        // If we get here without crashing, the concurrency is handled correctly
        await metaSub.stop()
    }
}
