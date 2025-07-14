import XCTest

extension XCTestCase {
    /// Helper for testing async code with timeout
    func waitForAsync(
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: @escaping () async throws -> Void
    ) async throws {
        let expectation = XCTestExpectation(description: "Async operation")
        
        Task {
            do {
                try await block()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed with error: \(error)", file: file, line: line)
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
    }
    
    /// Helper for testing AsyncSequence iterations
    func collectAsyncSequence<S: AsyncSequence>(
        _ sequence: S,
        maxItems: Int = 10,
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> [S.Element] {
        var items: [S.Element] = []
        let expectation = XCTestExpectation(description: "AsyncSequence collection")
        
        Task {
            do {
                for try await item in sequence {
                    items.append(item)
                    if items.count >= maxItems {
                        break
                    }
                }
                expectation.fulfill()
            } catch {
                XCTFail("AsyncSequence iteration failed: \(error)", file: file, line: line)
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: timeout)
        return items
    }
    
    /// Helper for asserting async throws
    func assertAsyncThrows<T>(
        _ expression: () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected async expression to throw", file: file, line: line)
        } catch {
            // Expected
        }
    }
    
    /// Helper for asserting async no throw
    func assertAsyncNoThrow<T>(
        _ expression: () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
    
    /// Helper for testing with multiple async tasks
    func runConcurrentTasks(
        count: Int,
        file: StaticString = #file,
        line: UInt = #line,
        task: @escaping (Int) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    try await task(i)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    /// Helper for testing async timeouts
    func withTimeout<T>(
        _ duration: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let task = Task {
            try await operation()
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            task.cancel()
            throw AsyncTestError.timeout
        }
        
        let result = try await task.value
        timeoutTask.cancel()
        return result
    }
}

enum AsyncTestError: Error {
    case timeout
    case unexpectedState
    case testFailed(String)
}