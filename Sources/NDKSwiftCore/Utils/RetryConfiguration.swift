import Foundation

/// Configuration for retry behavior across various NDK operations
public struct RetryConfiguration: Sendable {
    /// Base delay between retry attempts
    public let baseDelay: TimeInterval

    /// How much to increase delay after each attempt
    public let delayIncrement: TimeInterval

    /// Maximum number of retry attempts
    public let maxAttempts: Int

    /// Maximum delay between attempts (caps exponential backoff)
    public let maxDelay: TimeInterval

    /// Whether to use exponential backoff
    public let useExponentialBackoff: Bool

    /// Jitter factor (0.0 to 1.0) to randomize delays
    public let jitterFactor: Double

    public init(
        baseDelay: TimeInterval = NetworkConstants.retryBaseDelay,
        delayIncrement: TimeInterval = NetworkConstants.retryDelayIncrement,
        maxAttempts: Int = 3,
        maxDelay: TimeInterval = NetworkConstants.maxRetryDelay,
        useExponentialBackoff: Bool = false,
        jitterFactor: Double = 0.1
    ) {
        self.baseDelay = baseDelay
        self.delayIncrement = delayIncrement
        self.maxAttempts = maxAttempts
        self.maxDelay = maxDelay
        self.useExponentialBackoff = useExponentialBackoff
        self.jitterFactor = max(0, min(1, jitterFactor)) // Clamp to 0...1
    }

    /// Calculate delay for a given attempt (0-indexed)
    public func delay(for attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return baseDelay }

        var delay: TimeInterval
        if useExponentialBackoff {
            // Exponential: baseDelay * 2^attempt
            delay = baseDelay * pow(2.0, Double(attempt))
        } else {
            // Linear: baseDelay + (attempt * delayIncrement)
            delay = baseDelay + (Double(attempt) * delayIncrement)
        }

        // Apply max delay cap
        delay = min(delay, maxDelay)

        // Apply jitter
        if jitterFactor > 0 {
            let jitter = delay * jitterFactor * (Double.random(in: -1 ... 1))
            delay += jitter
        }

        return max(0, delay) // Ensure non-negative
    }

    // MARK: - Preset Configurations

    /// Fast retry for local operations
    public static let fast = RetryConfiguration(
        baseDelay: 0.1,
        delayIncrement: 0.1,
        maxAttempts: 3,
        maxDelay: 1.0
    )

    /// Standard retry for network operations
    public static let standard = RetryConfiguration(
        baseDelay: NetworkConstants.retryBaseDelay,
        delayIncrement: NetworkConstants.retryDelayIncrement,
        maxAttempts: 3,
        maxDelay: NetworkConstants.maxRetryDelay
    )

    /// Aggressive retry with exponential backoff for critical operations
    public static let aggressive = RetryConfiguration(
        baseDelay: 1.0,
        delayIncrement: 0,
        maxAttempts: 5,
        maxDelay: 60.0,
        useExponentialBackoff: true,
        jitterFactor: 0.2
    )

    /// Mint operations need more retries
    public static let mint = RetryConfiguration(
        baseDelay: NetworkConstants.retryBaseDelay,
        delayIncrement: NetworkConstants.retryDelayIncrement,
        maxAttempts: NetworkConstants.maxMintRetries,
        maxDelay: NetworkConstants.maxRetryDelay
    )

    /// No retry
    public static let none = RetryConfiguration(
        baseDelay: 0,
        delayIncrement: 0,
        maxAttempts: 0,
        maxDelay: 0
    )
}

// MARK: - Retry Execution Helper

public extension RetryConfiguration {
    /// Execute an async operation with retry logic
    func execute<T>(
        operation: () async throws -> T,
        shouldRetry: ((Error) -> Bool)? = nil
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0 ..< max(1, maxAttempts) {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    throw error
                }

                // Don't delay after the last attempt
                if attempt < maxAttempts - 1 {
                    let delayTime = delay(for: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delayTime * Double(TimeConstants.nanosecondsPerSecond)))
                }
            }
        }

        throw lastError ?? NDKError.unknown("Retry failed with no error")
    }
}
