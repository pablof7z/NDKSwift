import Foundation

/// Blossom client for interacting with Blossom servers
public actor BlossomClient {
    private let networkClient: NDKNetworkClient
    private var serverCache: [String: BlossomServerDescriptor] = [:]

    public init(urlSession: NDKNetworkFetching = URLSession.shared) {
        networkClient = NDKNetworkClient(session: urlSession)
    }

    // MARK: - Private Helpers

    private func createServerError(response: HTTPURLResponse, data: Data, serverURL: String) -> NDKError {
        let errorMessage = String(data: data, encoding: .utf8)
        return NDKError.serverError(relay: serverURL, code: response.statusCode, message: errorMessage)
    }

    // MARK: - BUD-01: Server Discovery

    /// Discover Blossom server capabilities
    public func discoverServer(_ serverURL: String) async throws -> BlossomServerDescriptor {
        if let cached = serverCache[serverURL] {
            return cached
        }

        let baseURL = try URLUtils.validateURL(serverURL)
        let wellKnownURL = baseURL.appendingPathComponent(".well-known/blossom")

        var request = URLRequest(url: wellKnownURL)
        request.httpMethod = HTTPConstants.methodGet
        request.setValue(HTTPConstants.contentTypeApplicationJSON, forHTTPHeaderField: HTTPConstants.headerAccept)

        do {
            let descriptor = try await networkClient.fetchAndDecode(
                BlossomServerDescriptor.self,
                for: request
            )
            serverCache[serverURL] = descriptor
            return descriptor
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom server discovery", error: error)
        }
    }

    // MARK: - BUD-02: Upload

    /// Upload a file to a Blossom server with progress streaming
    /// - Returns: AsyncThrowingStream that yields progress events and completes with the uploaded blob
    public func upload(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        ndk: NDK,
        configuration: BlossomUploadConfiguration = .default
    ) -> AsyncThrowingStream<BlossomUploadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let blob = try await performUpload(
                        data: data,
                        mimeType: mimeType,
                        to: serverURL,
                        ndk: ndk,
                        configuration: configuration
                    ) { bytesSent, totalBytes in
                        continuation.yield(.progress(bytesSent: bytesSent, totalBytes: totalBytes))
                    }
                    continuation.yield(.completed(blob))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Upload and await only the final result (no progress tracking)
    public func upload(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        ndk: NDK,
        configuration: BlossomUploadConfiguration = .default
    ) async throws -> BlossomBlob {
        try await performUpload(
            data: data,
            mimeType: mimeType,
            to: serverURL,
            ndk: ndk,
            configuration: configuration,
            onProgress: nil
        )
    }

    private func performUpload(
        data: Data,
        mimeType: String?,
        to serverURL: String,
        ndk: NDK,
        configuration: BlossomUploadConfiguration,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> BlossomBlob {
        let signer = try ndk.requireSigner()
        let baseURL = try URLUtils.validateURL(serverURL)
        let sha256Hex = Crypto.sha256(data).hexString

        // Discover server capabilities (optional - failures are non-fatal)
        let descriptor: BlossomServerDescriptor?
        do {
            descriptor = try await discoverServer(serverURL)
        } catch {
            NDKLogger.log(.warning, category: .relay, "Failed to discover Blossom server at \(serverURL): \(error.localizedDescription)")
            descriptor = nil
        }

        // Validate constraints
        if let maxSize = descriptor?.maxUploadSize, data.count > maxSize {
            throw NDKError.fileTooLarge(maxSize: maxSize)
        }

        let finalMimeType = mimeType ?? BlossomMediaProcessor.inferMimeType(from: data) ?? "application/octet-stream"

        if let acceptedTypes = descriptor?.acceptsMimeTypes,
           !acceptedTypes.contains(finalMimeType) && !acceptedTypes.contains("*/*") {
            throw NDKError.unsupportedMimeType(finalMimeType)
        }

        // Create auth
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: sha256Hex,
            size: Int64(data.count),
            mimeType: finalMimeType,
            signer: signer,
            ndk: ndk,
            expiration: nil
        )

        // Build request
        let uploadPath = descriptor?.uploadUrl ?? "/upload"
        let uploadURL = baseURL.appendingPathComponent(uploadPath)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = HTTPConstants.methodPut
        request.setValue(finalMimeType, forHTTPHeaderField: HTTPConstants.headerContentType)
        request.setValue(try auth.authorizationHeaderValue(), forHTTPHeaderField: HTTPConstants.headerAuthorization)

        // Create session with custom timeouts
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest
        sessionConfig.timeoutIntervalForResource = configuration.timeoutIntervalForResource
        sessionConfig.httpAdditionalHeaders = [HTTPConstants.headerUserAgent: HTTPConstants.userAgentNDKSwift]

        // Perform upload with optional progress tracking
        let (responseData, httpResponse) = try await performURLSessionUpload(
            request: request,
            data: data,
            configuration: sessionConfig,
            onProgress: onProgress
        )

        // Handle response
        switch httpResponse.statusCode {
        case HTTPStatusCode.ok, HTTPStatusCode.created:
            let uploadDescriptor = try JSONCoding.decode(BlossomUploadDescriptor.self, from: responseData)

            guard uploadDescriptor.sha256 == sha256Hex else {
                throw NDKError.invalidSHA256(sha256Hex)
            }

            // Extract dimensions for images
            var dimensions: (width: Int, height: Int)?
            if BlossomMediaProcessor.isProcessableImageType(finalMimeType) {
                dimensions = BlossomMediaProcessor.processImage(data)
            }

            return BlossomBlob(
                sha256: uploadDescriptor.sha256,
                url: uploadDescriptor.url,
                size: uploadDescriptor.size,
                type: uploadDescriptor.type,
                uploaded: Date(nostrTimestamp: uploadDescriptor.uploaded),
                dimensions: dimensions
            )

        case HTTPStatusCode.badRequest:
            if let maxSize = descriptor?.maxUploadSize {
                throw NDKError.fileTooLarge(maxSize: maxSize)
            }
            throw NDKError.unsupportedMimeType(finalMimeType)

        case HTTPStatusCode.unauthorized:
            throw NDKError.unauthorized(relay: serverURL, message: ErrorMessageConstants.Messages.blossomAuthorizationFailed)

        case HTTPStatusCode.tooManyRequests:
            throw NDKError.uploadFailed(reason: "Rate limited by Blossom server")

        default:
            throw createServerError(response: httpResponse, data: responseData, serverURL: serverURL)
        }
    }

    private func performURLSessionUpload(
        request: URLRequest,
        data: Data,
        configuration: URLSessionConfiguration,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> (Data, HTTPURLResponse) {
        if let onProgress = onProgress {
            // Use delegate-based upload for progress tracking
            return try await withCheckedThrowingContinuation { continuation in
                let delegate = UploadProgressDelegate(
                    onProgress: onProgress,
                    onComplete: { result in
                        continuation.resume(with: result)
                    }
                )
                let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                let task = session.uploadTask(with: request, from: data)
                delegate.session = session
                task.resume()
            }
        } else {
            // Simple upload without progress
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (responseData, response) = try await session.upload(for: request, from: data)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Non-HTTP response received")
            }
            return (responseData, httpResponse)
        }
    }

    // MARK: - BUD-03: List

    /// List blobs on a Blossom server
    public func list(
        from serverURL: String,
        ndk: NDK,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> [BlossomBlob] {
        let signer = try ndk.requireSigner()
        let baseURL = try URLUtils.validateURL(serverURL)

        let descriptor: BlossomServerDescriptor?
        do {
            descriptor = try await discoverServer(serverURL)
        } catch {
            NDKLogger.log(.warning, category: .relay, "Failed to discover Blossom server at \(serverURL): \(error.localizedDescription)")
            descriptor = nil
        }
        let listPath = descriptor?.listUrl ?? "/list"

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(listPath), resolvingAgainstBaseURL: true)!

        var queryItems: [URLQueryItem] = []
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(Timestamp.from(since))))
        }
        if let until = until {
            queryItems.append(URLQueryItem(name: "until", value: String(Timestamp.from(until))))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        guard let listURL = urlComponents.url else {
            throw NDKError.invalidURL(serverURL)
        }

        let auth = try await BlossomAuth.createListAuth(
            signer: signer,
            ndk: ndk,
            since: since,
            until: until
        )

        var request = URLRequest(url: listURL)
        request.httpMethod = HTTPConstants.methodGet
        request.setValue(HTTPConstants.contentTypeApplicationJSON, forHTTPHeaderField: HTTPConstants.headerAccept)
        request.setValue(try auth.authorizationHeaderValue(), forHTTPHeaderField: HTTPConstants.headerAuthorization)

        do {
            let listResponse = try await networkClient.fetchAndDecode(
                BlossomListResponse.self,
                for: request
            )

            return listResponse.blobs.map { item in
                BlossomBlob(
                    sha256: item.sha256,
                    url: "\(serverURL)/\(item.sha256)",
                    size: item.size,
                    type: item.type,
                    uploaded: Date(nostrTimestamp: Timestamp(item.uploaded))
                )
            }
        } catch NDKError.unauthorized {
            throw NDKError.unauthorized(relay: serverURL, message: ErrorMessageConstants.Messages.blossomAuthorizationFailed)
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom list", error: error)
        }
    }

    // MARK: - BUD-04: Delete

    /// Delete a blob from a Blossom server
    public func delete(
        sha256: String,
        from serverURL: String,
        ndk: NDK,
        reason: String? = nil
    ) async throws {
        let signer = try ndk.requireSigner()
        let baseURL = try URLUtils.validateURL(serverURL)
        let deleteURL = baseURL.appendingPathComponent(sha256)

        let auth = try await BlossomAuth.createDeleteAuth(
            sha256: sha256,
            signer: signer,
            ndk: ndk,
            reason: reason
        )

        var request = URLRequest(url: deleteURL)
        request.httpMethod = HTTPConstants.methodDelete
        request.setValue(try auth.authorizationHeaderValue(), forHTTPHeaderField: HTTPConstants.headerAuthorization)

        do {
            let (_, httpResponse) = try await networkClient.fetchAndValidateData(for: request)

            switch httpResponse.statusCode {
            case HTTPStatusCode.ok, HTTPStatusCode.noContent:
                return

            default:
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: nil)
            }
        } catch NDKError.unauthorized {
            throw NDKError.unauthorized(relay: serverURL, message: ErrorMessageConstants.Messages.blossomAuthorizationFailed)
        } catch NDKError.invalidRequest {
            throw NDKError.blobNotFound(sha256: sha256)
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom delete", error: error)
        }
    }

    // MARK: - Download

    /// Download a blob from a Blossom server (no auth required)
    public func download(
        sha256: String,
        from serverURL: String
    ) async throws -> Data {
        let url = try URLUtils.validateURL("\(serverURL)/\(sha256)")

        var request = URLRequest(url: url)
        request.httpMethod = HTTPConstants.methodGet

        do {
            let data = try await networkClient.fetchData(with: request)
            let downloadedHex = Crypto.sha256(data).hexString

            guard downloadedHex == sha256 else {
                throw NDKError.invalidSHA256(sha256)
            }

            return data
        } catch NDKError.invalidRequest {
            throw NDKError.blobNotFound(sha256: sha256)
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom download", error: error)
        }
    }
}

// MARK: - Upload Progress Delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let onComplete: @Sendable (Result<(Data, HTTPURLResponse), Error>) -> Void
    private var responseData = Data()
    private var response: HTTPURLResponse?
    var session: URLSession?

    init(
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (Result<(Data, HTTPURLResponse), Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { self.session?.invalidateAndCancel() }

        if let error = error {
            onComplete(.failure(error))
        } else if let response = response {
            onComplete(.success((responseData, response)))
        } else {
            onComplete(.failure(NDKError.invalidResponse(from: "No HTTP response")))
        }
    }
}
