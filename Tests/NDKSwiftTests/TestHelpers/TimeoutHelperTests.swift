import XCTest
@testable import NDKSwift

final class TimeoutHelperTests: XCTestCase {
    
    // MARK: - XCTestCase+Async Tests
    
    func testWithTimeout_Success() async throws {
        // Test that operations completing before timeout succeed
        let result = try await withTimeout(2.0) { () async throws -> String in
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
    }
    
    func testWithTimeout_Failure() async throws {
        // Test that operations exceeding timeout return nil
        let result = try await withTimeout(0.1) { () async throws -> String in
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            return "Should not reach here"
        }
        
        XCTAssertNil(result)
    }
    
    func testRunWithTimeout_Success() async throws {
        // Test that runWithTimeout succeeds for fast operations
        let result = try await runWithTimeout(timeout: 2.0) {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
    }
    
    func testRunWithTimeout_ThrowsOnTimeout() async {
        // Test that runWithTimeout throws TestTimeoutError on timeout
        // Note: This test expects XCTFail to be called by runWithTimeout, 
        // so we use a custom expectation approach
        
        var didTimeout = false
        var thrownError: Error?
        
        do {
            _ = try await runWithTimeout(timeout: 0.1) {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                return "Should not reach here"
            }
        } catch {
            didTimeout = true
            thrownError = error
        }
        
        XCTAssertTrue(didTimeout, "Expected operation to timeout")
        XCTAssertTrue(thrownError is TestTimeoutError, "Expected TestTimeoutError but got \(String(describing: thrownError))")
        
        if let timeoutError = thrownError as? TestTimeoutError {
            XCTAssertEqual(timeoutError.timeout, 0.1)
        }
    }
    
    // MARK: - TestTimeoutHelper Tests
    
    func testTimeoutHelper_Success() async throws {
        // Test TestTimeoutHelper with successful operation
        let result = try await TestTimeoutHelper.withTimeout(seconds: 2.0) {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Helper Success"
        }
        
        XCTAssertEqual(result, "Helper Success")
    }
    
    func testTimeoutHelper_ThrowsOnTimeout() async {
        // Test TestTimeoutHelper throws on timeout
        do {
            _ = try await TestTimeoutHelper.withTimeout(seconds: 0.1) {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                return "Should not reach here"
            }
            XCTFail("Expected timeout error")
        } catch let error as TestTimeoutHelper.TimeoutError {
            XCTAssertEqual(error.seconds, 0.1)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testTimeoutHelper_Optional() async {
        // Test optional timeout helper
        let result = await TestTimeoutHelper.withTimeoutOptional(seconds: 0.1) {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                // Ignore cancellation
            }
            return "Should not reach here"
        }
        
        XCTAssertNil(result)
    }
    
    // MARK: - Performance Tests
    
    func testTimeoutOverhead() async throws {
        // Ensure timeout mechanism doesn't add significant overhead
        let startTime = Date()
        
        _ = try await withTimeout(5.0) { () async throws -> String in
            // Fast operation
            return "Fast"
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.1, "Timeout mechanism should not add significant overhead")
    }
    
    func testTimeoutCancellation() async throws {
        // Test that operations are properly cancelled on timeout
        var wasCancelled = false
        
        _ = try await withTimeout(0.1) { () async throws -> String in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            } catch {
                wasCancelled = Task.isCancelled
            }
            return "Should be cancelled"
        }
        
        // Give a bit of time for cancellation to propagate
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        XCTAssertTrue(wasCancelled, "Long-running task should be cancelled on timeout")
    }
}