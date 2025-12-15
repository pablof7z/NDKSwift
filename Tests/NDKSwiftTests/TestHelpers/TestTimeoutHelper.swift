import Foundation
import XCTest

/// Utility to add timeout functionality to async test operations
enum TestTimeoutHelper {
    struct TimeoutError: Error, LocalizedError {
        let seconds: TimeInterval

        var errorDescription: String? {
            "Test operation timed out after \(seconds) seconds"
        }
    }

    /// Executes an async operation with a timeout
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds (default: 30)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: TimeoutError if the operation times out, or the error from the operation
    static func withTimeout<T>(
        seconds: TimeInterval = 30,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation task
            group.addTask {
                try await operation()
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }

            // Return the first result (either success or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Executes a non-throwing async operation with a timeout
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds (default: 30)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation, or nil if timeout
    static func withTimeoutOptional<T>(
        seconds: TimeInterval = 30,
        operation: @escaping () async -> T
    ) async -> T? {
        do {
            return try await withTimeout(seconds: seconds) {
                await operation()
            }
        } catch {
            return nil
        }
    }

    /// Convenience method for XCTest async test methods
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds (default: 30)
    ///   - file: Source file (auto-populated)
    ///   - line: Source line (auto-populated)
    ///   - operation: The async test operation
    static func testWithTimeout(
        seconds: TimeInterval = 30,
        file: StaticString = #file,
        line: UInt = #line,
        operation: @escaping () async throws -> Void
    ) async throws {
        do {
            try await withTimeout(seconds: seconds, operation: operation)
        } catch let error as TimeoutError {
            XCTFail("Test timed out after \(error.seconds) seconds", file: file, line: line)
            throw error
        } catch {
            throw error
        }
    }
}

/// Extension to make it easier to use with XCTestCase
extension XCTestCase {
    /// Executes an async test operation with timeout protection
    func performAsyncTest(
        timeout: TimeInterval = 30,
        file: StaticString = #file,
        line: UInt = #line,
        _ operation: @escaping () async throws -> Void
    ) async throws {
        try await TestTimeoutHelper.testWithTimeout(
            seconds: timeout,
            file: file,
            line: line,
            operation: operation
        )
    }
}
