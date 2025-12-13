@testable import NDKSwiftCore
import XCTest

final class RetryPolicyTests: XCTestCase {
    // MARK: - Configuration Tests

    func testDefaultConfigurations() {
        let relayConfig = RetryPolicyConfiguration.relayConnection
        XCTAssertEqual(relayConfig.initialDelay, 1.0)
        XCTAssertEqual(relayConfig.maxDelay, 300.0)
        XCTAssertEqual(relayConfig.multiplier, 2.0)
        XCTAssertNil(relayConfig.maxAttempts)
        XCTAssertEqual(relayConfig.jitterFactor, 0.1)

        let rpcConfig = RetryPolicyConfiguration.rpcRequest
        XCTAssertEqual(rpcConfig.initialDelay, 0.5)
        XCTAssertEqual(rpcConfig.maxDelay, 30.0)
        XCTAssertEqual(rpcConfig.multiplier, 1.5)
        XCTAssertEqual(rpcConfig.maxAttempts, 5)
        XCTAssertEqual(rpcConfig.jitterFactor, 0.2)

        let criticalConfig = RetryPolicyConfiguration.critical
        XCTAssertEqual(criticalConfig.initialDelay, 0.1)
        XCTAssertEqual(criticalConfig.maxDelay, 5.0)
        XCTAssertEqual(criticalConfig.multiplier, 2.0)
        XCTAssertEqual(criticalConfig.maxAttempts, 10)
        XCTAssertEqual(criticalConfig.jitterFactor, 0.05)
    }

    func testJitterFactorClamping() {
        let config1 = RetryPolicyConfiguration(jitterFactor: -0.5)
        XCTAssertEqual(config1.jitterFactor, 0.0)

        let config2 = RetryPolicyConfiguration(jitterFactor: 1.5)
        XCTAssertEqual(config2.jitterFactor, 1.0)

        let config3 = RetryPolicyConfiguration(jitterFactor: 0.5)
        XCTAssertEqual(config3.jitterFactor, 0.5)
    }

    // MARK: - Basic Retry Policy Tests

    func testExponentialBackoff() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            maxDelay: 10.0,
            multiplier: 2.0,
            maxAttempts: nil,
            jitterFactor: 0.0 // No jitter for predictable testing
        )
        let policy = RetryPolicy(configuration: config)

        // First delay should be initial delay
        let delay1 = policy.nextDelay()
        XCTAssertEqual(delay1, 1.0)

        // Second delay should be doubled
        let delay2 = policy.nextDelay()
        XCTAssertEqual(delay2, 2.0)

        // Third delay should be doubled again
        let delay3 = policy.nextDelay()
        XCTAssertEqual(delay3, 4.0)

        // Fourth delay should be doubled again
        let delay4 = policy.nextDelay()
        XCTAssertEqual(delay4, 8.0)

        // Fifth delay should be capped at maxDelay
        let delay5 = policy.nextDelay()
        XCTAssertEqual(delay5, 10.0)

        // Subsequent delays should remain at maxDelay
        let delay6 = policy.nextDelay()
        XCTAssertEqual(delay6, 10.0)
    }

    func testMaxAttempts() {
        let config = RetryPolicyConfiguration(
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        XCTAssertNotNil(policy.nextDelay()) // Attempt 1
        XCTAssertNotNil(policy.nextDelay()) // Attempt 2
        XCTAssertNotNil(policy.nextDelay()) // Attempt 3
        XCTAssertNil(policy.nextDelay()) // Should be nil after max attempts
    }

    func testJitter() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            jitterFactor: 0.5
        )
        let policy = RetryPolicy(configuration: config)

        // Get multiple delays to test jitter
        var delays: [TimeInterval] = []
        for _ in 0 ..< 10 {
            policy.reset()
            if let delay = policy.nextDelay() {
                delays.append(delay)
            }
        }

        // All delays should be within jitter range (0.5 to 1.5)
        for delay in delays {
            XCTAssertGreaterThanOrEqual(delay, 0.5)
            XCTAssertLessThanOrEqual(delay, 1.5)
        }

        // There should be some variation (not all the same)
        let uniqueDelays = Set(delays)
        XCTAssertGreaterThan(uniqueDelays.count, 1)
    }

    func testReset() {
        let config = RetryPolicyConfiguration(
            maxAttempts: 2,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        // Use up attempts
        XCTAssertNotNil(policy.nextDelay())
        XCTAssertNotNil(policy.nextDelay())
        XCTAssertNil(policy.nextDelay())

        // Reset should allow retries again
        policy.reset()
        XCTAssertNotNil(policy.nextDelay())
        XCTAssertNotNil(policy.nextDelay())
        XCTAssertNil(policy.nextDelay())
    }

    func testStatistics() {
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            multiplier: 2.0,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        var stats = policy.statistics
        XCTAssertEqual(stats.attempts, 0)
        XCTAssertEqual(stats.currentDelay, 1.0)
        XCTAssertFalse(stats.isRetrying)

        _ = policy.nextDelay()
        stats = policy.statistics
        XCTAssertEqual(stats.attempts, 1)
        XCTAssertEqual(stats.currentDelay, 2.0)

        _ = policy.nextDelay()
        stats = policy.statistics
        XCTAssertEqual(stats.attempts, 2)
        XCTAssertEqual(stats.currentDelay, 4.0)
    }

    // MARK: - Async Execute Tests

    func testExecuteSuccessOnFirstAttempt() async throws {
        let policy = RetryPolicy(configuration: .critical)
        var attempts = 0

        let result = try await policy.execute {
            attempts += 1
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 1)
    }

    func testExecuteRetryOnFailure() async throws {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01,
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        var attempts = 0

        let result = try await policy.execute {
            attempts += 1
            if attempts < 3 {
                throw TestError.retryable
            }
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 3)
    }

    func testExecuteMaxAttemptsReached() async {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01,
            maxAttempts: 2,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        var attempts = 0

        do {
            _ = try await policy.execute {
                attempts += 1
                throw TestError.retryable
            }
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(attempts, 2)
            // Should wrap the original error
            XCTAssertTrue(error.localizedDescription.contains("Max retry attempts reached"))
        }
    }

    func testExecuteShouldRetryPredicate() async throws {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.01,
            maxAttempts: 5,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)
        var attempts = 0

        do {
            _ = try await policy.execute(
                operation: {
                    attempts += 1
                    throw TestError.nonRetryable
                },
                shouldRetry: { error in
                    // Only retry specific errors
                    if case TestError.retryable = error {
                        return true
                    }
                    return false
                }
            )
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(attempts, 1) // Should not retry non-retryable errors
        }
    }

    func testExecuteWithTimeout() async throws {
        let config = RetryPolicyConfiguration(
            initialDelay: 0.1,
            maxAttempts: nil,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        do {
            _ = try await policy.executeWithTimeout(
                timeout: 0.05, // 50ms timeout
                operation: {
                    // This will always fail, causing retries
                    throw TestError.retryable
                }
            )
            XCTFail("Should have timed out")
        } catch {
            // Should timeout before many retry attempts
            XCTAssertTrue(error.localizedDescription.contains("timeout"))
        }
    }

    // MARK: - Schedule Retry Tests

    func testScheduleRetry() {
        let expectation = expectation(description: "Retry operation executed")
        let config = RetryPolicyConfiguration(
            initialDelay: 0.05,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        policy.scheduleRetry {
            expectation.fulfill()
        }

        // Verify retry is scheduled
        XCTAssertTrue(policy.statistics.isRetrying)

        wait(for: [expectation], timeout: 0.5)

        // After execution, should no longer be retrying
        XCTAssertFalse(policy.statistics.isRetrying)
    }

    func testCancelScheduledRetry() {
        let config = RetryPolicyConfiguration(initialDelay: 0.5)
        let policy = RetryPolicy(configuration: config)

        var operationExecuted = false
        policy.scheduleRetry {
            operationExecuted = true
        }

        // Verify retry is scheduled
        XCTAssertTrue(policy.statistics.isRetrying)

        // Cancel before it executes
        policy.cancel()

        // Verify it's no longer retrying
        XCTAssertFalse(policy.statistics.isRetrying)

        // Wait a bit to ensure operation doesn't execute
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertFalse(operationExecuted)
    }

    func testLinearBackoff() {
        // Test with multiplier = 1.0 for linear backoff
        let config = RetryPolicyConfiguration(
            initialDelay: 1.0,
            maxDelay: 100.0,
            multiplier: 1.0,
            jitterFactor: 0.0
        )
        let policy = RetryPolicy(configuration: config)

        // All delays should be the same (linear)
        let delay1 = policy.nextDelay()
        XCTAssertEqual(delay1, 1.0)

        let delay2 = policy.nextDelay()
        XCTAssertEqual(delay2, 1.0)

        let delay3 = policy.nextDelay()
        XCTAssertEqual(delay3, 1.0)
    }

    func testExecuteWithTimeoutSuccess() async throws {
        let policy = RetryPolicy()

        let result = try await policy.executeWithTimeout(timeout: 1.0) {
            "quick success"
        }

        XCTAssertEqual(result, "quick success")
    }

    func testConfigurationInitialization() {
        let config = RetryPolicyConfiguration(
            initialDelay: 2.0,
            maxDelay: 60.0,
            multiplier: 3.0,
            maxAttempts: 5,
            jitterFactor: 0.3
        )

        XCTAssertEqual(config.initialDelay, 2.0)
        XCTAssertEqual(config.maxDelay, 60.0)
        XCTAssertEqual(config.multiplier, 3.0)
        XCTAssertEqual(config.maxAttempts, 5)
        XCTAssertEqual(config.jitterFactor, 0.3)
    }

    func testInitialState() {
        let policy = RetryPolicy()
        let stats = policy.statistics

        XCTAssertEqual(stats.attempts, 0)
        XCTAssertEqual(stats.currentDelay, 1.0) // Default initial delay
        XCTAssertFalse(stats.isRetrying)
    }

    // MARK: - Helper Types

    enum TestError: Error, Equatable {
        case retryable
        case nonRetryable
    }
}
