import Foundation

/// Utilities for formatting byte counts in a human-readable format
public enum ByteCountFormatters {
    
    /// Shared byte count formatter instance
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter
    }()
    
    /// Shared decimal style formatter (1000 instead of 1024)
    private static let decimalFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .decimal
        return formatter
    }()
    
    /// Format bytes using binary units (1024)
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "1.5 MB")
    public static func formatBytes(_ bytes: Int64) -> String {
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Format bytes using decimal units (1000)
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "1.5 MB")
    public static func formatBytesDecimal(_ bytes: Int64) -> String {
        return decimalFormatter.string(fromByteCount: bytes)
    }
    
    /// Format bytes with specific units
    /// - Parameters:
    ///   - bytes: Number of bytes
    ///   - units: Allowed units for formatting
    /// - Returns: Formatted string
    public static func formatBytes(_ bytes: Int64, allowedUnits units: ByteCountFormatter.Units) -> String {
        let customFormatter = ByteCountFormatter()
        customFormatter.allowedUnits = units
        customFormatter.countStyle = .binary
        return customFormatter.string(fromByteCount: bytes)
    }
    
    /// Get a human-readable description of memory usage
    /// - Parameter bytes: Number of bytes
    /// - Returns: Description string (e.g., "Using 1.5 MB of memory")
    public static func memoryUsageDescription(_ bytes: Int64) -> String {
        return "Using \(formatBytes(bytes)) of memory"
    }
    
    /// Get a progress description for downloads/uploads
    /// - Parameters:
    ///   - current: Current bytes transferred
    ///   - total: Total bytes to transfer
    /// - Returns: Progress string (e.g., "1.2 MB / 5.0 MB")
    public static func progressDescription(current: Int64, total: Int64) -> String {
        return "\(formatBytes(current)) / \(formatBytes(total))"
    }
    
    /// Get a transfer rate description
    /// - Parameter bytesPerSecond: Transfer rate in bytes per second
    /// - Returns: Rate string (e.g., "1.5 MB/s")
    public static func transferRateDescription(_ bytesPerSecond: Int64) -> String {
        return "\(formatBytes(bytesPerSecond))/s"
    }
    
    /// Calculate and format download time estimate
    /// - Parameters:
    ///   - remainingBytes: Bytes left to download
    ///   - bytesPerSecond: Current download rate
    /// - Returns: Time estimate string (e.g., "About 2 minutes remaining")
    public static func downloadTimeEstimate(remainingBytes: Int64, bytesPerSecond: Int64) -> String? {
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

// MARK: - Convenience Extensions

public extension Int64 {
    /// Format this byte count as a human-readable string
    var formattedByteCount: String {
        return ByteCountFormatters.formatBytes(self)
    }
    
    /// Format this byte count using decimal units
    var formattedByteCountDecimal: String {
        return ByteCountFormatters.formatBytesDecimal(self)
    }
}

public extension Int {
    /// Format this byte count as a human-readable string
    var formattedByteCount: String {
        return ByteCountFormatters.formatBytes(Int64(self))
    }
    
    /// Format this byte count using decimal units
    var formattedByteCountDecimal: String {
        return ByteCountFormatters.formatBytesDecimal(Int64(self))
    }
}