@testable import NDKSwiftCore
import XCTest

// MARK: - Enhanced Async Test Utilities

extension XCTestCase {
    /// Waits for a condition to become true within a timeout period
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    ///   - pollingInterval: How often to check the condition (default: 0.1 seconds)
    ///   - message: Custom failure message
    ///   - condition: The condition to check
    func assertEventually(
        timeout: TimeInterval = 5.0,
        pollingInterval: TimeInterval = 0.1,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () async throws -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                if try await condition() {
                    return // Success
                }
            } catch {
                // Continue polling even if condition throws
            }

            try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }

        // Timeout reached
        let failureMessage = message ?? "Condition did not become true within \(timeout) seconds"
        XCTFail(failureMessage, file: file, line: line)
    }

    /// Asserts that an AsyncSequence produces the expected number of elements
    func assertAsyncSequenceCount<S: AsyncSequence>(
        _ sequence: S,
        expectedCount: Int,
        timeout: TimeInterval = 5.0,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async where S.Element: Sendable {
        var count = 0
        let deadline = Date().addingTimeInterval(timeout)

        do {
            for try await _ in sequence {
                count += 1
                if count >= expectedCount {
                    return // Success
                }

                if Date() > deadline {
                    break
                }
            }
        } catch {
            let failureMessage = message ?? "AsyncSequence threw error: \(error)"
            XCTFail(failureMessage, file: file, line: line)
            return
        }

        let failureMessage = message ?? "Expected \(expectedCount) elements but got \(count) within \(timeout) seconds"
        XCTFail(failureMessage, file: file, line: line)
    }

    /// Collects elements from an AsyncSequence until a condition is met or timeout
    func collectFromAsyncSequence<S: AsyncSequence>(
        _ sequence: S,
        until condition: @escaping (S.Element) async -> Bool,
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [S.Element] where S.Element: Sendable {
        var collected: [S.Element] = []
        let deadline = Date().addingTimeInterval(timeout)

        for try await element in sequence {
            collected.append(element)

            if await condition(element) {
                return collected
            }

            if Date() > deadline {
                XCTFail("Timeout waiting for condition in AsyncSequence", file: file, line: line)
                return collected
            }
        }

        return collected
    }

    /// Waits for the first element from an AsyncSequence
    func firstFromAsyncSequence<S: AsyncSequence>(
        _ sequence: S,
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> S.Element? where S.Element: Sendable {
        let task = Task<S.Element?, Error> {
            for try await element in sequence {
                return element
            }
            return nil
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            task.cancel()
        }

        let result = try await task.value
        timeoutTask.cancel()

        if task.isCancelled && result == nil {
            XCTFail("Timeout waiting for first element from AsyncSequence", file: file, line: line)
        }

        return result
    }
}

// MARK: - NDK-Specific Async Test Helpers

extension XCTestCase {
    /// Waits for an NDK data source to receive a specific number of events
    func waitForEvents<T>(
        from dataSource: NDKSubscription<T>,
        count: Int,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> [T] {
        var events: [T] = []
        let deadline = Date().addingTimeInterval(timeout)

        // events yields [T] batches, not individual T elements
        for await eventBatch in dataSource.events {
            events.append(contentsOf: eventBatch)
            if events.count >= count {
                return events
            }

            if Date() > deadline {
                break
            }
        }

        XCTFail("Expected \(count) events but received \(events.count) within \(timeout) seconds", file: file, line: line)
        return events
    }

    /// Waits for EOSE from a data source
    func waitForEOSE(
        from dataSource: NDKSubscription<NDKEvent>,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        var eoseReceived = false

        let deadline = Date().addingTimeInterval(timeout)

        for await update in dataSource.relayUpdates {
            if case .eose = update {
                eoseReceived = true
                break
            }

            if case .aggregatedEose = update {
                eoseReceived = true
                break
            }

            if Date() > deadline {
                break
            }
        }

        if !eoseReceived {
            XCTFail("EOSE not received within \(timeout) seconds", file: file, line: line)
        }
    }

    /// Publishes an event and waits for it to be confirmed by at least one relay
    func publishAndWaitForConfirmation(
        event: NDKEvent,
        using ndk: NDK,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let publishedRelays = try await ndk.publish(event)

        if publishedRelays.isEmpty {
            XCTFail("Event was not published to any relays", file: file, line: line)
            return
        }

        // Create a filter for the published event
        let filter = NDKFilter(ids: [event.id])

        // Wait for the event to be retrievable using the new observe API
        await assertEventually(timeout: timeout, file: file, line: line) {
            let dataSource = ndk.subscribe(filter: filter, maxAge: 0)
            let firstEvent = await dataSource.first(timeout: 1.0)
            return firstEvent != nil
        }
    }

    /// Waits for NDK to connect to a minimum number of relays
    func waitForRelayConnections(
        ndk: NDK,
        minimumRelays: Int = 1,
        timeout: TimeInterval = 10.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let connected = await ndk.waitForRelayConnections(
            minimumRelays: minimumRelays,
            timeout: timeout
        )

        XCTAssertGreaterThanOrEqual(
            connected,
            minimumRelays,
            "Expected at least \(minimumRelays) relay connections but got \(connected)",
            file: file,
            line: line
        )
    }
}

// MARK: - Async Retry Helpers

extension XCTestCase {
    /// Retries an async operation with exponential backoff
    func retry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 0.1,
        maxDelay: TimeInterval = 2.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1 ... maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, maxDelay) // Exponential backoff
                }
            }
        }

        throw lastError ?? NSError(domain: "TestRetry", code: 0, userInfo: [NSLocalizedDescriptionKey: "Retry failed"])
    }
}

// MARK: - Parallel Test Execution

extension XCTestCase {
    /// Executes multiple async operations in parallel and waits for all to complete
    func runInParallel<T>(
        operations: [() async throws -> T]
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: T.self) { group in
            for operation in operations {
                group.addTask {
                    try await operation()
                }
            }

            var results: [T] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Executes multiple async operations in parallel with a specific type
    func runInParallel<T>(
        _ operation: @escaping (Int) async throws -> T,
        count: Int
    ) async throws -> [T] {
        let operations = (0 ..< count).map { index in
            { try await operation(index) }
        }
        return try await runInParallel(operations: operations)
    }
}
