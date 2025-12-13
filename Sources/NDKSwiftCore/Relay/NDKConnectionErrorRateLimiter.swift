import Foundation

/// Rate limiter for connection errors to prevent log spam
/// Tracks errors per relay URL and limits logging frequency
actor NDKConnectionErrorRateLimiter {
    private struct ErrorRecord {
        let firstOccurrence: Date
        let lastLogged: Date
        var occurrenceCount: Int
        let errorType: String
    }

    private var errorRecords: [String: ErrorRecord] = [:]
    private let minLogInterval: TimeInterval = 30.0 // Minimum 30 seconds between logs for same error
    private let errorResetInterval: TimeInterval = 300.0 // Reset error count after 5 minutes of no errors

    /// Check if we should log this error based on rate limiting rules
    /// Returns true if the error should be logged, false if it should be suppressed
    func shouldLogError(for url: String, errorType: String) -> Bool {
        let now = Date()

        // Clean up old records
        errorRecords = errorRecords.filter { _, record in
            now.timeIntervalSince(record.lastLogged) < errorResetInterval
        }

        let key = "\(url):\(errorType)"

        if let record = errorRecords[key] {
            let timeSinceLastLog = now.timeIntervalSince(record.lastLogged)

            // Allow logging if enough time has passed
            if timeSinceLastLog >= minLogInterval {
                // Update record
                errorRecords[key] = ErrorRecord(
                    firstOccurrence: record.firstOccurrence,
                    lastLogged: now,
                    occurrenceCount: record.occurrenceCount + 1,
                    errorType: errorType
                )
                return true
            } else {
                // Update count but don't log
                errorRecords[key] = ErrorRecord(
                    firstOccurrence: record.firstOccurrence,
                    lastLogged: record.lastLogged,
                    occurrenceCount: record.occurrenceCount + 1,
                    errorType: errorType
                )
                return false
            }
        } else {
            // First occurrence - always log
            errorRecords[key] = ErrorRecord(
                firstOccurrence: now,
                lastLogged: now,
                occurrenceCount: 1,
                errorType: errorType
            )
            return true
        }
    }

    /// Get a summary of suppressed errors for a URL
    func getSuppressedErrorSummary(for url: String) -> String? {
        let relevantRecords = errorRecords.filter { key, _ in
            key.hasPrefix("\(url):")
        }

        guard !relevantRecords.isEmpty else { return nil }

        let totalSuppressed = relevantRecords.values.reduce(0) { $0 + ($1.occurrenceCount - 1) }
        if totalSuppressed > 0 {
            return "Suppressed \(totalSuppressed) similar error(s) in the last \(Int(minLogInterval)) seconds"
        }

        return nil
    }
}

/// Shared instance for connection error rate limiting
let connectionErrorRateLimiter = NDKConnectionErrorRateLimiter()
