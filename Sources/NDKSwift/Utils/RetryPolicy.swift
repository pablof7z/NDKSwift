import Foundation

/// Retry policy configuration for network operations
public struct RetryPolicyConfiguration {
    /// Initial delay between retries (in seconds)
    public let initialDelay: TimeInterval
    
    /// Maximum delay between retries (in seconds)
    public let maxDelay: TimeInterval
    
    /// Multiplier for exponential backoff
    public let multiplier: Double
    
    /// Maximum number of retry attempts (nil for unlimited)
    public let maxAttempts: Int?
    
    /// Jitter factor (0.0 to 1.0) to randomize delays
    public let jitterFactor: Double
    
    /// Default configuration for relay connections
    public static let relayConnection = RetryPolicyConfiguration(
        initialDelay: 1.0,
        maxDelay: 300.0,
        multiplier: 2.0,
        maxAttempts: nil,
        jitterFactor: 0.1
    )
    
    /// Default configuration for RPC requests
    public static let rpcRequest = RetryPolicyConfiguration(
        initialDelay: 0.5,
        maxDelay: 30.0,
        multiplier: 1.5,
        maxAttempts: 5,
        jitterFactor: 0.2
    )
    
    /// Configuration for critical operations
    public static let critical = RetryPolicyConfiguration(
        initialDelay: 0.1,
        maxDelay: 5.0,
        multiplier: 2.0,
        maxAttempts: 10,
        jitterFactor: 0.05
    )
    
    public init(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 300.0,
        multiplier: Double = 2.0,
        maxAttempts: Int? = nil,
        jitterFactor: Double = 0.1
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.maxAttempts = maxAttempts
        self.jitterFactor = min(max(jitterFactor, 0.0), 1.0) // Clamp between 0 and 1
    }
}

/// Manages retry logic with exponential backoff
public final class RetryPolicy {
    private let configuration: RetryPolicyConfiguration
    private var currentDelay: TimeInterval
    private var attemptCount: Int = 0
    private let queue = DispatchQueue(label: "com.ndkswift.retrypolicy")
    
    /// Timer for scheduled retries
    private var retryTimer: Timer?
    
    /// Whether retry is currently active
    public private(set) var isRetrying: Bool = false
    
    public init(configuration: RetryPolicyConfiguration = .relayConnection) {
        self.configuration = configuration
        self.currentDelay = configuration.initialDelay
    }
    
    /// Reset the retry policy to initial state
    public func reset() {
        queue.sync {
            currentDelay = configuration.initialDelay
            attemptCount = 0
            isRetrying = false
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }
    
    /// Calculate the next retry delay
    public func nextDelay() -> TimeInterval? {
        queue.sync {
            // Check if we've exceeded max attempts
            if let maxAttempts = configuration.maxAttempts,
               attemptCount >= maxAttempts {
                return nil
            }
            
            // Calculate base delay
            let baseDelay = min(currentDelay, configuration.maxDelay)
            
            // Add jitter
            let jitterRange = baseDelay * configuration.jitterFactor
            let jitter = Double.random(in: -jitterRange...jitterRange)
            let delayWithJitter = max(0, baseDelay + jitter)
            
            // Update for next iteration
            currentDelay = min(currentDelay * configuration.multiplier, configuration.maxDelay)
            attemptCount += 1
            
            return delayWithJitter
        }
    }
    
    /// Schedule a retry operation
    public func scheduleRetry(operation: @escaping () -> Void) {
        guard let delay = nextDelay() else {
            // Max attempts reached
            return
        }
        
        queue.sync {
            isRetrying = true
            retryTimer?.invalidate()
            
            retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.queue.sync {
                    self?.isRetrying = false
                }
                operation()
            }
        }
    }
    
    /// Cancel any scheduled retry
    public func cancel() {
        queue.sync {
            retryTimer?.invalidate()
            retryTimer = nil
            isRetrying = false
        }
    }
    
    /// Get current retry statistics
    public var statistics: (attempts: Int, currentDelay: TimeInterval, isRetrying: Bool) {
        queue.sync {
            (attemptCount, currentDelay, isRetrying)
        }
    }
}

/// Async/await support for RetryPolicy
extension RetryPolicy {
    /// Execute an async operation with retry logic
    public func execute<T>(
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        reset()
        
        while true {
            do {
                return try await operation()
            } catch {
                // Check if we should retry this error
                guard shouldRetry(error) else {
                    throw error
                }
                
                // Get next delay or throw if max attempts reached
                guard let delay = nextDelay() else {
                    throw NDKError.runtime("max_retries_reached", "Max retry attempts reached: \(error)")
                }
                
                // Wait for the delay
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    /// Execute an async operation with retry logic and timeout
    public func executeWithTimeout<T>(
        timeout: TimeInterval,
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation task
            group.addTask {
                try await self.execute(
                    operation: operation,
                    shouldRetry: shouldRetry
                )
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKError.network("timeout", "Operation timed out")
            }
            
            // Return the first result (either success or timeout)
            guard let result = try await group.next() else {
                throw NDKError.runtime("no_result", "No result from retry operation")
            }
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
}