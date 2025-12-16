import Foundation
import XCTest
@testable import NDKSwiftCore

// MARK: - Test Event Factory

/// Factory for creating test events
public enum TestEventFactory {

    /// Create a simple test event
    public static func createEvent(
        kind: Kind = 1,
        content: String = "Test content",
        pubkey: PublicKey = "test_pubkey"
    ) -> NDKEvent {
        // Generate a valid 64-char hex ID and signature
        let idString = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                       UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let id = String(idString.prefix(64).lowercased())

        let sigString = UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                        UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                        UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                        UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let sig = String(sigString.prefix(128).lowercased())

        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [],
            content: content,
            sig: sig
        )
    }

    /// Create multiple test events
    public static func createEvents(
        count: Int,
        kind: Kind = 1,
        contentPrefix: String = "Test event",
        pubkey: PublicKey? = nil
    ) -> [NDKEvent] {
        (0..<count).map { index in
            createEvent(
                kind: kind,
                content: "\(contentPrefix) #\(index)",
                pubkey: pubkey ?? "test_pubkey"
            )
        }
    }

    /// Create events from multiple authors
    public static func createEventsFromAuthors(
        authors: [PublicKey],
        eventsPerAuthor: Int = 1,
        kind: Kind = 1
    ) -> [NDKEvent] {
        var events: [NDKEvent] = []
        for (authorIndex, author) in authors.enumerated() {
            for eventIndex in 0..<eventsPerAuthor {
                events.append(createEvent(
                    kind: kind,
                    content: "Event \(eventIndex) from author \(authorIndex)",
                    pubkey: author
                ))
            }
        }
        return events
    }
}

// MARK: - Mock Relay Factory

/// Factory for creating mock relays
public enum MockRelayFactory {

    /// Standard test relay URLs
    public static let standardURLs = [
        "wss://mock1.relay.test/",
        "wss://mock2.relay.test/",
        "wss://mock3.relay.test/"
    ]

    /// Fallback relay URLs (simulating real fallback relays)
    public static let fallbackURLs = [
        "wss://fallback1.relay.test/",
        "wss://fallback2.relay.test/"
    ]

    /// Outbox relay URLs (simulating author-specific outbox relays)
    public static let outboxURLs = [
        "wss://outbox1.relay.test/",
        "wss://outbox2.relay.test/"
    ]

    /// Create multiple connected mock relays
    public static func createConnectedMocks(
        urls: [RelayURL],
        ndk: NDK
    ) async -> [ControllableMockRelay] {
        var mocks: [ControllableMockRelay] = []
        for url in urls {
            let (mock, _) = await ndk.addMockRelay(url: url)
            mocks.append(mock)
        }
        return mocks
    }
}

// MARK: - Async Test Helpers

/// Wait for an async condition with timeout
public func waitForCondition(
    timeout: TimeInterval = 2.0,
    pollInterval: TimeInterval = 0.05,
    file: StaticString = #file,
    line: UInt = #line,
    _ condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }

    XCTFail("Condition not met within \(timeout)s", file: file, line: line)
}

/// Wait for a set to contain expected elements
public func waitForSetToContain<T: Hashable>(
    _ getSet: @escaping () async -> Set<T>,
    expected: Set<T>,
    timeout: TimeInterval = 2.0,
    file: StaticString = #file,
    line: UInt = #line
) async throws {
    try await waitForCondition(timeout: timeout, file: file, line: line) {
        let current = await getSet()
        return expected.isSubset(of: current)
    }
}

/// Collect events from an async stream with timeout
public func collectEvents(
    from stream: AsyncStream<NDKEvent>,
    maxCount: Int,
    timeout: TimeInterval = 2.0
) async -> [NDKEvent] {
    var events: [NDKEvent] = []

    let task = Task {
        for await event in stream {
            events.append(event)
            if events.count >= maxCount {
                break
            }
        }
    }

    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    task.cancel()

    return events
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Assert that two relay URL sets are equal (with normalization)
    public func assertRelayURLsEqual(
        _ actual: Set<RelayURL>,
        _ expected: Set<RelayURL>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let normalizedActual = Set(actual.map { $0.normalizedRelayURL })
        let normalizedExpected = Set(expected.map { $0.normalizedRelayURL })

        XCTAssertEqual(normalizedActual, normalizedExpected,
                      "Relay URLs don't match.\nActual: \(normalizedActual)\nExpected: \(normalizedExpected)",
                      file: file, line: line)
    }

    /// Assert that actual contains all expected relay URLs
    public func assertRelayURLsContain(
        _ actual: Set<RelayURL>,
        expected: Set<RelayURL>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let normalizedActual = Set(actual.map { $0.normalizedRelayURL })
        let normalizedExpected = Set(expected.map { $0.normalizedRelayURL })

        let missing = normalizedExpected.subtracting(normalizedActual)
        XCTAssertTrue(missing.isEmpty,
                     "Missing relay URLs: \(missing)\nActual: \(normalizedActual)",
                     file: file, line: line)
    }
}
