import XCTest
@testable import NDKSwiftCore

// MARK: - Test Errors

/// Error thrown when a test operation times out
struct TestTimeoutError: Error, LocalizedError {
    let timeout: TimeInterval
    
    var errorDescription: String? {
        return "Test operation timed out after \(timeout) seconds"
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Waits for an expectation with a default timeout
    func waitForExpectation(_ expectation: XCTestExpectation, timeout: TimeInterval = 5.0) {
        wait(for: [expectation], timeout: timeout)
    }
    
    /// Creates and returns an expectation with the given description
    func makeExpectation(description: String = #function) -> XCTestExpectation {
        return expectation(description: description)
    }
    
    /// Asserts that an async throwing function throws a specific error type
    func assertThrowsError<T, E: Error>(
        _ expression: @autoclosure () async throws -> T,
        errorType: E.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error of type \(errorType) but no error was thrown", file: file, line: line)
        } catch is E {
            // Success - expected error type was thrown
        } catch {
            XCTFail("Expected error of type \(errorType) but got \(type(of: error)): \(error)", file: file, line: line)
        }
    }
    
    /// Asserts that an async function completes within a timeout
    func assertCompletesWithin<T>(
        timeout: TimeInterval,
        _ expression: @autoclosure @escaping () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        let task = Task {
            try await expression()
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
            if task.isCancelled {
                XCTFail("Operation timed out after \(timeout) seconds", file: file, line: line)
            }
            throw error
        }
    }
    
    /// Runs an async operation with a timeout, returning nil if it times out
    func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T? {
        return try await withThrowingTaskGroup(of: T?.self) { group in
            // Add the main operation
            group.addTask {
                return try await operation()
            }
            
            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            // Wait for the first to complete
            let result = try await group.next()!
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    /// Runs an async test with a default timeout
    func runWithTimeout<T>(
        timeout: TimeInterval = 10.0,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        guard let result = try await withTimeout(timeout, operation: operation) else {
            XCTFail("Test timed out after \(timeout) seconds")
            throw TestTimeoutError(timeout: timeout)
        }
        return result
    }
}

// MARK: - Test Data Helpers

extension XCTestCase {
    /// Generates a random hex string of specified byte length
    func randomHex(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Generates a random 32-byte hex string (for keys)
    func randomKey() -> String {
        return randomHex(byteCount: 32)
    }
    
    /// Generates a random 64-byte hex string (for signatures)
    func randomSignature() -> String {
        return randomHex(byteCount: 64)
    }
}

// MARK: - Relay Test Helpers

extension XCTestCase {
    /// Creates a test relay URL
    func testRelayURL(_ index: Int = 1) -> String {
        return "wss://test.relay\(index).com/"
    }
    
    /// Creates multiple test relay URLs
    func testRelayURLs(count: Int) -> [String] {
        return (1...count).map { testRelayURL($0) }
    }
}

// MARK: - Event Test Helpers

extension XCTestCase {
    /// Creates a basic test event
    func createTestEvent(
        kind: Int = 1,
        content: String = "Test content",
        pubkey: String? = nil,
        tags: [[String]] = []
    ) -> NDKEvent {
        return NDKEvent(
            kind: kind,
            content: content,
            tags: tags,
            pubkey: pubkey ?? randomKey()
        )
    }
}