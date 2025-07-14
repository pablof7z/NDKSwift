import XCTest
@testable import NDKSwift

// Custom assertions for NDK types
func assertEventsEqual(
    _ event1: NDKEvent,
    _ event2: NDKEvent,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(event1.id, event2.id, "Event IDs don't match", file: file, line: line)
    XCTAssertEqual(event1.pubkey, event2.pubkey, "Event pubkeys don't match", file: file, line: line)
    XCTAssertEqual(event1.createdAt, event2.createdAt, "Event timestamps don't match", file: file, line: line)
    XCTAssertEqual(event1.kind, event2.kind, "Event kinds don't match", file: file, line: line)
    XCTAssertEqual(event1.content, event2.content, "Event content doesn't match", file: file, line: line)
    XCTAssertEqual(event1.sig, event2.sig, "Event signatures don't match", file: file, line: line)
    assertTagsEqual(event1.tags, event2.tags, file: file, line: line)
}

func assertTagsEqual(
    _ tags1: [[String]],
    _ tags2: [[String]],
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(tags1.count, tags2.count, "Tag counts don't match", file: file, line: line)
    
    for (index, tag1) in tags1.enumerated() {
        guard index < tags2.count else { break }
        let tag2 = tags2[index]
        XCTAssertEqual(tag1, tag2, "Tags at index \(index) don't match", file: file, line: line)
    }
}

func assertFiltersEqual(
    _ filter1: NDKFilter,
    _ filter2: NDKFilter,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(filter1.ids, filter2.ids, "Filter IDs don't match", file: file, line: line)
    XCTAssertEqual(filter1.authors, filter2.authors, "Filter authors don't match", file: file, line: line)
    XCTAssertEqual(filter1.kinds, filter2.kinds, "Filter kinds don't match", file: file, line: line)
    XCTAssertEqual(filter1.since, filter2.since, "Filter since timestamps don't match", file: file, line: line)
    XCTAssertEqual(filter1.until, filter2.until, "Filter until timestamps don't match", file: file, line: line)
    XCTAssertEqual(filter1.limit, filter2.limit, "Filter limits don't match", file: file, line: line)
    XCTAssertEqual(filter1.tags, filter2.tags, "Filter tags don't match", file: file, line: line)
}

func assertProfilesEqual(
    _ profile1: NDKUserProfile,
    _ profile2: NDKUserProfile,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(profile1.name, profile2.name, "Profile names don't match", file: file, line: line)
    XCTAssertEqual(profile1.displayName, profile2.displayName, "Profile display names don't match", file: file, line: line)
    XCTAssertEqual(profile1.about, profile2.about, "Profile about sections don't match", file: file, line: line)
    XCTAssertEqual(profile1.picture, profile2.picture, "Profile pictures don't match", file: file, line: line)
    XCTAssertEqual(profile1.banner, profile2.banner, "Profile banners don't match", file: file, line: line)
    XCTAssertEqual(profile1.nip05, profile2.nip05, "Profile NIP-05 identifiers don't match", file: file, line: line)
    XCTAssertEqual(profile1.lud06, profile2.lud06, "Profile LUD-06 addresses don't match", file: file, line: line)
    XCTAssertEqual(profile1.lud16, profile2.lud16, "Profile LUD-16 addresses don't match", file: file, line: line)
}

func assertEventValid(
    _ event: NDKEvent,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertFalse(event.id.isEmpty, "Event ID should not be empty", file: file, line: line)
    XCTAssertFalse(event.pubkey.isEmpty, "Event pubkey should not be empty", file: file, line: line)
    XCTAssertEqual(event.pubkey.count, 64, "Event pubkey should be 64 characters", file: file, line: line)
    XCTAssertTrue(event.createdAt > 0, "Event timestamp should be positive", file: file, line: line)
    
    XCTAssertEqual(event.id.count, 64, "Event ID should be 64 characters", file: file, line: line)
    
    if !event.sig.isEmpty {
        XCTAssertEqual(event.sig.count, 128, "Event signature should be 128 characters", file: file, line: line)
    }
}

func assertEventSigned(
    _ event: NDKEvent,
    file: StaticString = #file,
    line: UInt = #line
) {
    assertEventValid(event, file: file, line: line)
    XCTAssertFalse(event.sig.isEmpty, "Event should be signed", file: file, line: line)
    XCTAssertEqual(event.sig.count, 128, "Event signature should be 128 characters", file: file, line: line)
}

func assertRelayMessageValid(
    _ message: String,
    expectedType: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertTrue(message.hasPrefix("["), "Relay message should start with '['", file: file, line: line)
    XCTAssertTrue(message.hasSuffix("]"), "Relay message should end with ']'", file: file, line: line)
    
    // Try to parse as JSON array
    guard let data = message.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
          !array.isEmpty,
          let messageType = array[0] as? String else {
        XCTFail("Invalid relay message format", file: file, line: line)
        return
    }
    
    XCTAssertEqual(messageType, expectedType, "Unexpected message type", file: file, line: line)
}

// Helper to assert async operations complete within timeout
func assertCompletes<T>(
    within timeout: TimeInterval = 5.0,
    file: StaticString = #file,
    line: UInt = #line,
    _ operation: @escaping () async throws -> T
) async throws -> T {
    let task = Task {
        try await operation()
    }
    
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        task.cancel()
        XCTFail("Operation timed out after \(timeout) seconds", file: file, line: line)
        throw AsyncTestError.timeout
    }
    
    let result = try await task.value
    timeoutTask.cancel()
    return result
}