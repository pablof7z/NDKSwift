import Foundation

// MARK: - Upload Configuration

/// Configuration for Blossom uploads with customizable timeouts
public struct BlossomUploadConfiguration: Sendable {
    /// Timeout interval for each request (how long a request can stall before timing out)
    public let timeoutIntervalForRequest: TimeInterval

    /// Timeout interval for the entire resource transfer
    public let timeoutIntervalForResource: TimeInterval

    /// Default configuration with reasonable timeouts for large uploads
    public static let `default` = BlossomUploadConfiguration(
        timeoutIntervalForRequest: 120,
        timeoutIntervalForResource: 600
    )

    /// Configuration optimized for large file uploads
    public static let largeFile = BlossomUploadConfiguration(
        timeoutIntervalForRequest: 300,
        timeoutIntervalForResource: 1800
    )

    public init(
        timeoutIntervalForRequest: TimeInterval = 120,
        timeoutIntervalForResource: TimeInterval = 600
    ) {
        self.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.timeoutIntervalForResource = timeoutIntervalForResource
    }
}

// MARK: - Upload Event

/// Events emitted during a Blossom upload
public enum BlossomUploadEvent: Sendable {
    /// Upload progress update
    case progress(bytesSent: Int64, totalBytes: Int64)

    /// Upload completed successfully
    case completed(BlossomBlob)

    /// Progress as a fraction from 0.0 to 1.0
    public var fractionCompleted: Double? {
        guard case let .progress(bytesSent, totalBytes) = self, totalBytes > 0 else {
            return nil
        }
        return Double(bytesSent) / Double(totalBytes)
    }
}
