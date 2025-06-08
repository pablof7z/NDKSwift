import XCTest
@testable import NDKSwift

final class RetryPolicyTests: XCTestCase {
    
    func testInitialDelay() {
        let policy = RetryPolicy(configuration: .init(initialDelay: 1.0))
        let delay = policy.nextDelay()
        XCTAssertNotNil(delay)
        XCTAssertGreaterThanOrEqual(delay!, 0.9) // Account for jitter
        XCTAssertLessThanOrEqual(delay!, 1.1)
    }
    
    func testExponentialBackoff() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            multiplier: 2.0,
            jitterFactor: 0.0 // No jitter for predictable testing
        )
        let policy = RetryPolicy(configuration: config)
        
        XCTAssertEqual(policy.nextDelay(), 1.0)
        XCTAssertEqual(policy.nextDelay(), 2.0)
        XCTAssertEqual(policy.nextDelay(), 4.0)
        XCTAssertEqual(policy.nextDelay(), 8.0)
        XCTAssertEqual(policy.nextDelay(), 16.0)
    }
    
    func testMaxDelay() {
        let config = RetryPolicyConfiguration(
            initialDelay: 10.0,
            maxDelay: 20.0,
            multiplier: 3.0,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        XCTAssertEqual(policy.nextDelay(), 10.0)
        XCTAssertEqual(policy.nextDelay(), 20.0) // Capped at max
        XCTAssertEqual(policy.nextDelay(), 20.0) // Still capped
    }
    
    func testMaxAttempts() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        XCTAssertNotNil(policy.nextDelay()) // Attempt 1
        XCTAssertNotNil(policy.nextDelay()) // Attempt 2
        XCTAssertNotNil(policy.nextDelay()) // Attempt 3
        XCTAssertNil(policy.nextDelay())    // No more attempts
    }
    
    func testJitter() {
        let config = RetryPolicyConfiguration(
            initialDelay: 10.0,
            jitterFactor: 0.5 // 50% jitter
        )
        let policy = RetryPolicy(configuration: config)
        
        // Test multiple times to ensure jitter is applied
        var delays: Set<TimeInterval> = []
        for _ in 0..<10 {
            policy.reset()
            if let delay = policy.nextDelay() {
                delays.insert(delay)
            }
        }
        
        // With jitter, we should get different values
        XCTAssertGreaterThan(delays.count, 1)
        
        // All values should be within jitter range
        for delay in delays {
            XCTAssertGreaterThanOrEqual(delay, 5.0)  // 10 - 50%
            XCTAssertLessThanOrEqual(delay, 15.0)    // 10 + 50%
        }
    }
    
    func testReset() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            multiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        // Advance a few times
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        XCTAssertEqual(policy.nextDelay(), 4.0)
        
        // Reset and verify we're back to initial
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), 1.0)
    }
    
    func testStatistics() {
        let policy = RetryPolicy(configuration: .init(initialDelay: 1.0, jitterFactor: 0.0))
        
        let stats1 = policy.statistics
        XCTAssertEqual(stats1.attempts, 0)
        XCTAssertEqual(stats1.currentDelay, 1.0)
        XCTAssertFalse(stats1.isRetrying)
        
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        
        let stats2 = policy.statistics
        XCTAssertEqual(stats2.attempts, 2)
        XCTAssertEqual(stats2.currentDelay, 4.0)
    }
    
    func testPredefinedConfigurations() {
        // Test relay connection config
        let relayConfig = RetryPolicyConfiguration.relayConnection
        XCTAssertEqual(relayConfig.initialDelay, 1.0)
        XCTAssertEqual(relayConfig.maxDelay, 300.0)
        XCTAssertNil(relayConfig.maxAttempts)
        
        // Test RPC request config
        let rpcConfig = RetryPolicyConfiguration.rpcRequest
        XCTAssertEqual(rpcConfig.initialDelay, 0.5)
        XCTAssertEqual(rpcConfig.maxDelay, 30.0)
        XCTAssertEqual(rpcConfig.maxAttempts, 5)
        
        // Test critical config
        let criticalConfig = RetryPolicyConfiguration.critical
        XCTAssertEqual(criticalConfig.initialDelay, 0.1)
        XCTAssertEqual(criticalConfig.maxDelay, 5.0)
        XCTAssertEqual(criticalConfig.maxAttempts, 10)
    }
    
    func testAsyncExecute() async throws {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01, // Very short for testing
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        var attemptCount = 0
        
        // Test successful operation after retries
        let result = try await policy.execute {
            attemptCount += 1
            if attemptCount < 3 {
                throw NDKError.custom("Simulated failure")
            }
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
        XCTAssertEqual(attemptCount, 3)
    }
    
    func testAsyncExecuteMaxAttemptsReached() async {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01,
            maxAttempts: 2,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        var attemptCount = 0
        
        do {
            _ = try await policy.execute {
                attemptCount += 1
                throw NDKError.custom("Always fails")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attemptCount, 2)
            XCTAssertTrue(error.localizedDescription.contains("Max retry attempts reached"))
        }
    }
    
    func testAsyncExecuteWithShouldRetry() async throws {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        var attemptCount = 0
        
        do {
            _ = try await policy.execute(
                operation: {
                    attemptCount += 1
                    throw NDKError.invalidSignature // Non-retryable error
                },
                shouldRetry: { error in
                    // Don't retry signature errors
                    if case NDKError.invalidSignature = error {
                        return false
                    }
                    return true
                }
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attemptCount, 1) // No retries
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testAsyncExecuteWithTimeout() async {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.1,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        
        do {
            _ = try await policy.executeWithTimeout(
                timeout: 0.05, // Very short timeout
                operation: {
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    return "Should timeout"
                }
            )
            XCTFail("Should have timed out")
        } catch {
            XCTAssertTrue(error is NDKError)
            if case NDKError.timeout = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}