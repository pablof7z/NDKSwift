import XCTest
@testable import NDKSwiftCore

// MARK: - Event Assertions

/// Asserts two events are equal (comparing all fields)
func XCTAssertEventEqual(
    _ event1: NDKEvent,
    _ event2: NDKEvent,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(event1.id, event2.id, "Event IDs don't match", file: file, line: line)
    XCTAssertEqual(event1.pubkey, event2.pubkey, "Event pubkeys don't match", file: file, line: line)
    XCTAssertEqual(event1.createdAt, event2.createdAt, "Event timestamps don't match", file: file, line: line)
    XCTAssertEqual(event1.kind, event2.kind, "Event kinds don't match", file: file, line: line)
    XCTAssertEqual(event1.content, event2.content, "Event content doesn't match", file: file, line: line)
    XCTAssertEqual(event1.sig, event2.sig, "Event signatures don't match", file: file, line: line)
    XCTAssertEqual(event1.tags.count, event2.tags.count, "Event tag counts don't match", file: file, line: line)
    
    // Compare tags
    for (index, tag1) in event1.tags.enumerated() {
        let tag2 = event2.tags[index]
        XCTAssertEqual(tag1.count, tag2.count, "Tag parameter count mismatch at index \(index)", file: file, line: line)
        for (paramIndex, param1) in tag1.enumerated() {
            let param2 = tag2[paramIndex]
            XCTAssertEqual(param1, param2, "Tag parameter mismatch at index \(index), param \(paramIndex)", file: file, line: line)
        }
    }
}

/// Asserts an event matches a filter
func XCTAssertFilterMatches(
    _ filter: NDKFilter,
    event: NDKEvent,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(
        filter.matches(event: event),
        "Event does not match filter. Event: \(event), Filter: \(filter)",
        file: file,
        line: line
    )
}

/// Asserts an event does not match a filter
func XCTAssertFilterDoesNotMatch(
    _ filter: NDKFilter,
    event: NDKEvent,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(
        filter.matches(event: event),
        "Event unexpectedly matches filter. Event: \(event), Filter: \(filter)",
        file: file,
        line: line
    )
}

// MARK: - Relay Assertions

/// Asserts a relay is connected
func XCTAssertRelayConnected(
    _ relay: NDKRelay,
    timeout: TimeInterval = 5.0,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let startTime = Date()
    
    while Date().timeIntervalSince(startTime) < timeout {
        if await relay.isConnected {
            return // Success
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    XCTFail("Relay \(relay.url) failed to connect within \(timeout) seconds", file: file, line: line)
}

/// Asserts a relay is disconnected
func XCTAssertRelayDisconnected(
    _ relay: NDKRelay,
    timeout: TimeInterval = 5.0,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let startTime = Date()
    
    while Date().timeIntervalSince(startTime) < timeout {
        if await !relay.isConnected {
            return // Success
        }
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    XCTFail("Relay \(relay.url) failed to disconnect within \(timeout) seconds", file: file, line: line)
}

// MARK: - Cache Assertions

/// Asserts an event exists in cache
func XCTAssertEventInCache(
    _ event: NDKEvent,
    cache: NDKCache,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let cachedEvent = await cache.getEvent(id: event.id)
    XCTAssertNotNil(cachedEvent, "Event \(event.id) not found in cache", file: file, line: line)
    
    if let cachedEvent = cachedEvent {
        XCTAssertEventEqual(event, cachedEvent, file: file, line: line)
    }
}

/// Asserts an event does not exist in cache
func XCTAssertEventNotInCache(
    eventId: EventID,
    cache: NDKCache,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let cachedEvent = await cache.getEvent(id: eventId)
    XCTAssertNil(cachedEvent, "Event \(eventId) unexpectedly found in cache", file: file, line: line)
}

/// Asserts cache contains expected number of events
func XCTAssertCacheEventCount(
    _ expectedCount: Int,
    filter: NDKFilter? = nil,
    cache: NDKCache,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let events = (try? await cache.queryEvents(filter ?? NDKFilter())) ?? []
    XCTAssertEqual(
        events.count,
        expectedCount,
        "Cache contains \(events.count) events, expected \(expectedCount)",
        file: file,
        line: line
    )
}

// MARK: - Subscription Assertions

/// Asserts a data source receives events
func XCTAssertDataSourceReceivesEvents<T>(
    _ dataSource: NDKSubscription<T>,
    minimumCount: Int = 1,
    timeout: TimeInterval = 5.0,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    
    while Date() < deadline {
        if dataSource.data.count >= minimumCount {
            return // Success
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    XCTFail(
        "Data source received only \(dataSource.data.count) items, expected at least \(minimumCount)",
        file: file,
        line: line
    )
}

// MARK: - Async Assertions

/// Asserts an async operation completes within a timeout
func XCTAssertAsyncCompletes<T>(
    timeout: TimeInterval = 5.0,
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: @escaping () async throws -> T
) async throws -> T {
    let task = Task {
        try await operation()
    }
    
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        task.cancel()
    }
    
    do {
        let result = try await task.value
        timeoutTask.cancel()
        return result
    } catch {
        if error is CancellationError {
            XCTFail("Async operation timed out after \(timeout) seconds", file: file, line: line)
        }
        throw error
    }
}

/// Asserts an async operation throws an error
func XCTAssertAsyncThrows<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: () async throws -> T
) async {
    do {
        _ = try await operation()
        XCTFail("Expected operation to throw an error", file: file, line: line)
    } catch {
        // Success - operation threw an error
    }
}

/// Asserts an async operation throws a specific error type
func XCTAssertAsyncThrows<T, E: Error & Equatable>(
    _ expectedError: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: () async throws -> T
) async {
    do {
        _ = try await operation()
        XCTFail("Expected operation to throw \(expectedError)", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Threw unexpected error type: \(error)", file: file, line: line)
    }
}

// MARK: - Collection Assertions

/// Asserts a collection eventually contains an element matching a predicate
func XCTAssertEventuallyContains<T>(
    _ getValue: () async -> [T],
    where predicate: (T) -> Bool,
    timeout: TimeInterval = 5.0,
    pollingInterval: TimeInterval = 0.1,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let deadline = Date().addingTimeInterval(timeout)
    
    while Date() < deadline {
        let values = await getValue()
        if values.contains(where: predicate) {
            return // Success
        }
        try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
    }
    
    let finalValues = await getValue()
    XCTFail(
        "Collection never contained matching element. Final values: \(finalValues)",
        file: file,
        line: line
    )
}

// MARK: - Content Entity Assertions

extension Array where Element == ContentEntity {
    /// Check if array contains a text entity
    func containsText(_ text: String? = nil) -> Bool {
        contains { entity in
            if case .text(let entityText) = entity {
                return text == nil || entityText == text
            }
            return false
        }
    }
    
    /// Check if array contains an npub entity
    func containsNpub(_ npub: String? = nil) -> Bool {
        contains { entity in
            if case .npub(let entityNpub) = entity {
                return npub == nil || entityNpub == npub
            }
            return false
        }
    }
    
    /// Check if array contains a hashtag entity
    func containsHashtag(_ tag: String? = nil) -> Bool {
        contains { entity in
            if case .hashtag(let entityTag) = entity {
                return tag == nil || entityTag == tag
            }
            return false
        }
    }
    
    /// Check if array contains a URL entity
    func containsURL(_ url: String? = nil) -> Bool {
        contains { entity in
            if case .url(let entityURL) = entity {
                return url == nil || entityURL.absoluteString == url
            }
            return false
        }
    }
    
    /// Check if array contains a note entity
    func containsNote(_ note: String? = nil) -> Bool {
        contains { entity in
            if case .note(let entityNote) = entity {
                return note == nil || entityNote == note
            }
            return false
        }
    }
    
    /// Check if array contains an nprofile entity
    func containsNprofile(_ nprofile: String? = nil) -> Bool {
        contains { entity in
            if case .nprofile(let entityNprofile) = entity {
                return nprofile == nil || entityNprofile == nprofile
            }
            return false
        }
    }
    
    /// Check if array contains a nevent entity
    func containsNevent(_ nevent: String? = nil) -> Bool {
        contains { entity in
            if case .nevent(let entityNevent) = entity {
                return nevent == nil || entityNevent == nevent
            }
            return false
        }
    }
    
    /// Check if array contains an naddr entity
    func containsNaddr(_ naddr: String? = nil) -> Bool {
        contains { entity in
            if case .naddr(let entityNaddr) = entity {
                return naddr == nil || entityNaddr == naddr
            }
            return false
        }
    }
    
    /// Check if array contains a user mention
    func containsUserMention(pubkey: String? = nil) -> Bool {
        contains { entity in
            if case .userMention(let entityPubkey, _) = entity {
                return pubkey == nil || entityPubkey == pubkey
            }
            return false
        }
    }
    
    /// Check if array contains an event mention
    func containsEventMention(_ eventId: String? = nil) -> Bool {
        contains { entity in
            if case .eventMention(let entityEventId) = entity {
                return eventId == nil || entityEventId == eventId
            }
            return false
        }
    }
    
    /// Extract all hashtags from entities
    var hashtags: [String] {
        compactMap { entity in
            if case .hashtag(let tag) = entity { return tag }
            return nil
        }
    }
    
    /// Extract all URLs from entities
    var urls: [String] {
        compactMap { entity in
            if case .url(let url) = entity { return url.absoluteString }
            return nil
        }
    }
    
    /// Count entities of a specific type
    func countOf(_ entityType: ContentEntityType) -> Int {
        filter { entity in
            switch (entity, entityType) {
            case (.text, .text),
                 (.npub, .npub),
                 (.nprofile, .nprofile),
                 (.note, .note),
                 (.nevent, .nevent),
                 (.naddr, .naddr),
                 (.hashtag, .hashtag),
                 (.url, .url),
                 (.userMention, .userMention),
                 (.eventMention, .eventMention):
                return true
            default:
                return false
            }
        }.count
    }
}

/// Content entity type for counting
enum ContentEntityType {
    case text
    case npub
    case nprofile
    case note
    case nevent
    case naddr
    case hashtag
    case url
    case userMention
    case eventMention
}