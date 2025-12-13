import Foundation

/// Thread-safe utilities for formatting byte counts in a human-readable format
public actor ByteCountFormatters {
    public static let shared = ByteCountFormatters()

    private let formatter: ByteCountFormatter
    private let decimalFormatter: ByteCountFormatter

    private init() {
        // Binary formatter (1024)
        let binaryFormatter = ByteCountFormatter()
        binaryFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        binaryFormatter.countStyle = .binary
        self.formatter = binaryFormatter

        // Decimal formatter (1000)
        let decFormatter = ByteCountFormatter()
        decFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        decFormatter.countStyle = .decimal
        self.decimalFormatter = decFormatter
    }

    /// Format bytes using binary units (1024)
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "1.5 MB")
    public func formatBytes(_ bytes: Int64) -> String {
        return formatter.string(fromByteCount: bytes)
    }

    /// Format bytes using decimal units (1000)
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "1.5 MB")
    public func formatBytesDecimal(_ bytes: Int64) -> String {
        return decimalFormatter.string(fromByteCount: bytes)
    }

    /// Format bytes with specific units
    /// - Parameters:
    ///   - bytes: Number of bytes
    ///   - units: Allowed units for formatting
    /// - Returns: Formatted string
    public func formatBytes(_ bytes: Int64, allowedUnits units: ByteCountFormatter.Units) -> String {
        let customFormatter = ByteCountFormatter()
        customFormatter.allowedUnits = units
        customFormatter.countStyle = .binary
        return customFormatter.string(fromByteCount: bytes)
    }

    /// Get a human-readable description of memory usage
    /// - Parameter bytes: Number of bytes
    /// - Returns: Description string (e.g., "Using 1.5 MB of memory")
    public func memoryUsageDescription(_ bytes: Int64) -> String {
        return "Using \(formatBytes(bytes)) of memory"
    }

    /// Get a progress description for downloads/uploads
    /// - Parameters:
    ///   - current: Current bytes transferred
    ///   - total: Total bytes to transfer
    /// - Returns: Progress string (e.g., "1.2 MB / 5.0 MB")
    public func progressDescription(current: Int64, total: Int64) -> String {
        return "\(formatBytes(current)) / \(formatBytes(total))"
    }

    /// Get a transfer rate description
    /// - Parameter bytesPerSecond: Transfer rate in bytes per second
    /// - Returns: Rate string (e.g., "1.5 MB/s")
    public func transferRateDescription(_ bytesPerSecond: Int64) -> String {
        return "\(formatBytes(bytesPerSecond))/s"
    }

    /// Calculate and format download time estimate
    /// - Parameters:
    ///   - remainingBytes: Bytes left to download
    ///   - bytesPerSecond: Current download rate
    /// - Returns: Time estimate string (e.g., "About 2 minutes remaining")
    public func downloadTimeEstimate(remainingBytes: Int64, bytesPerSecond: Int64) -> String? {
        guard bytesPerSecond > 0 else { return nil }

        let remainingSeconds = Int(remainingBytes / bytesPerSecond)

        if remainingSeconds < 60 {
            return "Less than a minute remaining"
        } else if remainingSeconds < 3600 {
            let minutes = remainingSeconds / 60
            return "About \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        } else {
            let hours = remainingSeconds / 3600
            let minutes = (remainingSeconds % 3600) / 60
            if minutes > 0 {
                return "About \(hours) hour\(hours == 1 ? "" : "s") \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
            } else {
                return "About \(hours) hour\(hours == 1 ? "" : "s") remaining"
            }
        }
    }
}
