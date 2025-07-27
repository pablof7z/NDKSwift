import XCTest
@testable import NDKSwift

final class RetryConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = RetryConfiguration()
        
        XCTAssertEqual(config.baseDelay, NetworkConstants.retryBaseDelay)
        XCTAssertEqual(config.delayIncrement, NetworkConstants.retryDelayIncrement)
        XCTAssertEqual(config.maxAttempts, 3)
        XCTAssertEqual(config.maxDelay, NetworkConstants.maxRetryDelay)
        XCTAssertFalse(config.useExponentialBackoff)
        XCTAssertEqual(config.jitterFactor, 0.1)
    }
    
    func testLinearBackoff() {
        let config = RetryConfiguration(
            baseDelay: 1.0,
            delayIncrement: 0.5,
            maxAttempts: 5,
            maxDelay: 10.0,
            useExponentialBackoff: false,
            jitterFactor: 0 // No jitter for predictable testing
        )
        
        XCTAssertEqual(config.delay(for: 0), 1.0)
        XCTAssertEqual(config.delay(for: 1), 1.5)
        XCTAssertEqual(config.delay(for: 2), 2.0)
        XCTAssertEqual(config.delay(for: 3), 2.5)
        XCTAssertEqual(config.delay(for: 4), 3.0)
    }
    
    func testExponentialBackoff() {
        let config = RetryConfiguration(
            baseDelay: 1.0,
            delayIncrement: 0, // Not used in exponential
            maxAttempts: 5,
            maxDelay: 100.0,
            useExponentialBackoff: true,
            jitterFactor: 0 // No jitter for predictable testing
        )
        
        XCTAssertEqual(config.delay(for: 0), 1.0)  // 1 * 2^0 = 1
        XCTAssertEqual(config.delay(for: 1), 2.0)  // 1 * 2^1 = 2
        XCTAssertEqual(config.delay(for: 2), 4.0)  // 1 * 2^2 = 4
        XCTAssertEqual(config.delay(for: 3), 8.0)  // 1 * 2^3 = 8
        XCTAssertEqual(config.delay(for: 4), 16.0) // 1 * 2^4 = 16
    }
    
    func testMaxDelayCap() {
        let config = RetryConfiguration(
            baseDelay: 10.0,
            delayIncrement: 10.0,
            maxAttempts: 5,
            maxDelay: 25.0,
            useExponentialBackoff: false,
            jitterFactor: 0
        )
        
        XCTAssertEqual(config.delay(for: 0), 10.0)
        XCTAssertEqual(config.delay(for: 1), 20.0)
        XCTAssertEqual(config.delay(for: 2), 25.0) // Capped at maxDelay
        XCTAssertEqual(config.delay(for: 3), 25.0) // Still capped
        XCTAssertEqual(config.delay(for: 4), 25.0) // Still capped
    }
    
    func testJitterFactor() {
        let config = RetryConfiguration(
            baseDelay: 10.0,
            delayIncrement: 0,
            maxAttempts: 3,
            maxDelay: 100.0,
            useExponentialBackoff: false,
            jitterFactor: 0.5
        )
        
        // With 50% jitter, delay should be within 5-15 range
        for _ in 0..<10 {
            let delay = config.delay(for: 0)
            XCTAssertGreaterThanOrEqual(delay, 5.0)
            XCTAssertLessThanOrEqual(delay, 15.0)
        }
    }
    
    func testJitterFactorClamping() {
        // Test that jitter factor is clamped to 0...1
        let config1 = RetryConfiguration(jitterFactor: -0.5)
        XCTAssertEqual(config1.jitterFactor, 0.0)
        
        let config2 = RetryConfiguration(jitterFactor: 1.5)
        XCTAssertEqual(config2.jitterFactor, 1.0)
    }
    
    func testNegativeAttempt() {
        let config = RetryConfiguration(baseDelay: 5.0)
        XCTAssertEqual(config.delay(for: -1), 5.0) // Should return baseDelay
    }
    
    func testPresetConfigurations() {
        // Test fast preset
        let fast = RetryConfiguration.fast
        XCTAssertEqual(fast.baseDelay, 0.1)
        XCTAssertEqual(fast.maxAttempts, 3)
        XCTAssertEqual(fast.maxDelay, 1.0)
        
        // Test standard preset
        let standard = RetryConfiguration.standard
        XCTAssertEqual(standard.baseDelay, NetworkConstants.retryBaseDelay)
        XCTAssertEqual(standard.maxAttempts, 3)
        
        // Test aggressive preset
        let aggressive = RetryConfiguration.aggressive
        XCTAssertEqual(aggressive.baseDelay, 1.0)
        XCTAssertEqual(aggressive.maxAttempts, 5)
        XCTAssertTrue(aggressive.useExponentialBackoff)
        
        // Test mint preset
        let mint = RetryConfiguration.mint
        XCTAssertEqual(mint.maxAttempts, NetworkConstants.maxMintRetries)
        
        // Test none preset
        let none = RetryConfiguration.none
        XCTAssertEqual(none.maxAttempts, 0)
    }
    
    func testExecuteSuccess() async throws {
        let config = RetryConfiguration.fast
        var callCount = 0
        
        let result = try await config.execute {
            callCount += 1
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(callCount, 1) // Should succeed on first try
    }
    
    func testExecuteRetryThenSuccess() async throws {
        let config = RetryConfiguration(
            baseDelay: 0.01, // Very short for testing
            maxAttempts: 3,
            jitterFactor: 0
        )
        var callCount = 0
        
        let result = try await config.execute {
            callCount += 1
            if callCount < 3 {
                throw RetryTestError.temporary
            }
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(callCount, 3) // Should succeed on third try
    }
    
    func testExecuteMaxRetriesExceeded() async {
        let config = RetryConfiguration(
            baseDelay: 0.01,
            maxAttempts: 2,
            jitterFactor: 0
        )
        var callCount = 0
        
        do {
            _ = try await config.execute {
                callCount += 1
                throw RetryTestError.temporary
            }
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(callCount, 2) // Should have tried twice
            XCTAssertTrue(error is RetryTestError)
        }
    }
    
    func testExecuteWithShouldRetry() async {
        let config = RetryConfiguration(
            baseDelay: 0.01,
            maxAttempts: 3,
            jitterFactor: 0
        )
        var callCount = 0
        
        do {
            _ = try await config.execute(
                operation: {
                    callCount += 1
                    throw RetryTestError.permanent
                },
                shouldRetry: { error in
                    // Don't retry permanent errors
                    if case RetryTestError.permanent = error {
                        return false
                    }
                    return true
                }
            )
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(callCount, 1) // Should not retry permanent error
            XCTAssertTrue(error is RetryTestError)
        }
    }
    
    func testExecuteWithZeroMaxAttempts() async throws {
        let config = RetryConfiguration(maxAttempts: 0)
        var callCount = 0
        
        // Even with 0 max attempts, should execute once
        let result = try await config.execute {
            callCount += 1
            return "success"
        }
        
        XCTAssertEqual(result, "success")
        XCTAssertEqual(callCount, 1)
    }
}

// Test error types
private enum RetryTestError: Error {
    case temporary
    case permanent
}