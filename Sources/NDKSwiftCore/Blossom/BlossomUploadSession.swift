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
        timeoutIntervalForRequest: 120,  // 2 minutes per-request timeout
        timeoutIntervalForResource: 600  // 10 minutes total upload timeout
    )

    /// Configuration optimized for large file uploads
    public static let largeFile = BlossomUploadConfiguration(
        timeoutIntervalForRequest: 300,   // 5 minutes per-request timeout
        timeoutIntervalForResource: 1800  // 30 minutes total upload timeout
    )

    /// Create a custom upload configuration
    /// - Parameters:
    ///   - timeoutIntervalForRequest: Timeout interval for each request in seconds (default: 120)
    ///   - timeoutIntervalForResource: Timeout interval for entire resource transfer in seconds (default: 600)
    public init(
        timeoutIntervalForRequest: TimeInterval = 120,
        timeoutIntervalForResource: TimeInterval = 600
    ) {
        self.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.timeoutIntervalForResource = timeoutIntervalForResource
    }
}

// MARK: - Upload Progress

/// Progress information for Blossom uploads
public struct BlossomUploadProgress: Sendable {
    /// Number of bytes sent so far
    public let bytesSent: Int64

    /// Total bytes expected to send
    public let totalBytes: Int64

    /// Progress as a fraction from 0.0 to 1.0
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesSent) / Double(totalBytes)
    }

    /// Progress as a percentage from 0 to 100
    public var percentComplete: Int {
        Int(fractionCompleted * 100)
    }
}

// MARK: - Upload Delegate

/// Internal delegate for tracking upload progress
final class BlossomUploadDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let progressHandler: @Sendable (BlossomUploadProgress) -> Void

    init(progressHandler: @escaping @Sendable (BlossomUploadProgress) -> Void) {
        self.progressHandler = progressHandler
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = BlossomUploadProgress(
            bytesSent: totalBytesSent,
            totalBytes: totalBytesExpectedToSend
        )
        progressHandler(progress)
    }
}

// MARK: - Upload Session Manager

/// Manages upload sessions with progress tracking and custom configurations
actor BlossomUploadSessionManager {

    /// Perform an upload with progress tracking
    /// - Parameters:
    ///   - request: The URLRequest to execute
    ///   - data: The data to upload
    ///   - configuration: Upload configuration with timeout settings
    ///   - onProgress: Optional callback for progress updates
    /// - Returns: Tuple of response data and HTTP response
    func upload(
        request: URLRequest,
        data: Data,
        configuration: BlossomUploadConfiguration,
        onProgress: (@Sendable (BlossomUploadProgress) -> Void)?
    ) async throws -> (Data, HTTPURLResponse) {
        // Create session configuration with custom timeouts
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest
        sessionConfig.timeoutIntervalForResource = configuration.timeoutIntervalForResource

        // Set user agent
        sessionConfig.httpAdditionalHeaders = [
            HTTPConstants.headerUserAgent: HTTPConstants.userAgentNDKSwift
        ]

        // Create delegate for progress tracking if needed
        let delegate: BlossomUploadDelegate?
        if let progressHandler = onProgress {
            delegate = BlossomUploadDelegate(progressHandler: progressHandler)
        } else {
            delegate = nil
        }

        // Create session with delegate
        let session = URLSession(
            configuration: sessionConfig,
            delegate: delegate,
            delegateQueue: nil
        )

        defer {
            session.invalidateAndCancel()
        }

        // Perform the upload
        let (responseData, response) = try await session.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NDKError.invalidResponse(from: "Non-HTTP response received")
        }

        return (responseData, httpResponse)
    }
}
