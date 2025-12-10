import Foundation

/// Blossom client for interacting with Blossom servers
public actor BlossomClient {
    private let networkClient: NDKNetworkClient
    private var serverCache: [String: BlossomServerDescriptor] = [:]

    // MARK: - Constants

    public init(urlSession: NDKNetworkFetching = URLSession.shared) {
        self.networkClient = NDKNetworkClient(session: urlSession)
    }

    // MARK: - Private Helpers

    /// Helper method to handle HTTP responses and extract error messages
    private func handleHTTPResponse(_ response: URLResponse?, data: Data, serverURL: String) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NDKError.invalidResponse(from: "Blossom server")
        }
        return httpResponse
    }

    /// Helper method to create server error with message extraction
    private func createServerError(response: HTTPURLResponse, data: Data, serverURL: String) -> NDKError {
        let errorMessage = String(data: data, encoding: .utf8)
        return NDKError.serverError(relay: serverURL, code: response.statusCode, message: errorMessage)
    }

    // MARK: - BUD-01: Server Discovery

    /// Discover Blossom server capabilities
    public func discoverServer(_ serverURL: String) async throws -> BlossomServerDescriptor {
        // Check cache first
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
            
            // Cache the descriptor
            serverCache[serverURL] = descriptor
            
            return descriptor
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom server discovery", error: error)
        }
    }

    // MARK: - BUD-02: Upload

    /// Upload a file to a Blossom server
    public func upload(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        auth: BlossomAuth
    ) async throws -> BlossomBlob {
        let baseURL = try URLUtils.validateURL(serverURL)

        // Calculate SHA256
        let sha256Hex = Crypto.sha256(data).hexString

        // Check if we need to discover the server first
        let descriptor: BlossomServerDescriptor?
        do {
            descriptor = try await discoverServer(serverURL)
        } catch {
            NDKLogger.log(.warning, category: .relay, "Failed to discover Blossom server at \(serverURL): \(error.localizedDescription)")
            descriptor = nil
        }

        // Validate file size if server has limits
        if let maxSize = descriptor?.maxUploadSize, data.count > maxSize {
            throw NDKError.fileTooLarge(maxSize: maxSize)
        }

        // Validate mime type if server has restrictions
        if let acceptedTypes = descriptor?.acceptsMimeTypes,
           let mimeType = mimeType,
           !acceptedTypes.contains(mimeType) && !acceptedTypes.contains("*/*") {
            throw NDKError.unsupportedMimeType(mimeType)
        }

        // Construct upload URL
        let uploadPath = descriptor?.uploadUrl ?? "/upload"
        let uploadURL = baseURL.appendingPathComponent(uploadPath)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = HTTPConstants.methodPut
        request.httpBody = data

        // Set headers
        if let mimeType = mimeType {
            request.setValue(mimeType, forHTTPHeaderField: HTTPConstants.headerContentType)
        }

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: HTTPConstants.headerAuthorization)

        do {
            let (responseData, httpResponse) = try await networkClient.fetchAndValidateData(for: request)
            
            // The network client already handles common status codes, but we need specific Blossom handling
            switch httpResponse.statusCode {
            case HTTPStatusCode.ok, HTTPStatusCode.created:
                let uploadDescriptor = try JSONCoding.decode(BlossomUploadDescriptor.self, from: responseData)

                // Verify SHA256 matches
                guard uploadDescriptor.sha256 == sha256Hex else {
                    throw NDKError.invalidSHA256(sha256Hex)
                }

                return BlossomBlob(
                    sha256: uploadDescriptor.sha256,
                    url: uploadDescriptor.url,
                    size: uploadDescriptor.size,
                    type: uploadDescriptor.type,
                    uploaded: Date(nostrTimestamp: uploadDescriptor.uploaded)
                )
                
            default:
                // This shouldn't happen as fetchAndValidateData handles errors
                throw createServerError(response: httpResponse, data: responseData, serverURL: serverURL)
            }
        } catch NDKError.invalidResponse {
            // Map generic errors to Blossom-specific ones where needed
            throw NDKError.uploadFailed(reason: "Invalid response from Blossom server")
        } catch NDKError.rateLimited {
            throw NDKError.uploadFailed(reason: "Rate limited by Blossom server")
        } catch NDKError.unauthorized {
            throw NDKError.unauthorized(relay: serverURL, message: ErrorMessageConstants.Messages.blossomAuthorizationFailed)
        } catch NDKError.invalidRequest where descriptor?.maxUploadSize != nil {
            throw NDKError.fileTooLarge(maxSize: descriptor?.maxUploadSize ?? 0)
        } catch NDKError.invalidRequest {
            throw NDKError.unsupportedMimeType(mimeType ?? "unknown")
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.networkError(for: serverURL, operation: "Blossom upload", error: error)
        }
    }

    // MARK: - BUD-03: List

    /// List blobs on a Blossom server
    public func list(
        from serverURL: String,
        auth: BlossomAuth,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> [BlossomBlob] {
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

        // Add query parameters
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

        var request = URLRequest(url: listURL)
        request.httpMethod = HTTPConstants.methodGet
        request.setValue(HTTPConstants.contentTypeApplicationJSON, forHTTPHeaderField: HTTPConstants.headerAccept)

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: HTTPConstants.headerAuthorization)

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
        auth: BlossomAuth
    ) async throws {
        let baseURL = try URLUtils.validateURL(serverURL)

        let deleteURL = baseURL.appendingPathComponent(sha256)

        var request = URLRequest(url: deleteURL)
        request.httpMethod = HTTPConstants.methodDelete

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: HTTPConstants.headerAuthorization)

        do {
            let (_, httpResponse) = try await networkClient.fetchAndValidateData(for: request)
            
            switch httpResponse.statusCode {
            case HTTPStatusCode.ok, HTTPStatusCode.noContent:
                // Success
                return
                
            default:
                // This shouldn't happen as fetchAndValidateData handles errors
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

    /// Download a blob from a Blossom server
    public func download(
        sha256: String,
        from serverURL: String
    ) async throws -> Data {
        let url = try URLUtils.validateURL("\(serverURL)/\(sha256)")

        var request = URLRequest(url: url)
        request.httpMethod = HTTPConstants.methodGet

        do {
            let data = try await networkClient.fetchData(with: request)
            
            // Verify SHA256
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

    // MARK: - Convenience Methods

    /// Upload with automatic auth creation and metadata extraction
    public func uploadWithAuth(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        signer: NDKSigner,
        ndk: NDK,
        expiration: Date? = nil
    ) async throws -> BlossomBlob {
        // Calculate SHA256
        let sha256Hex = Crypto.sha256(data).hexString

        // Determine MIME type if not provided
        let finalMimeType = mimeType ?? BlossomMediaProcessor.inferMimeType(from: data)

        // Extract media metadata if it's an image
        var dimensions: (width: Int, height: Int)?

        if BlossomMediaProcessor.isProcessableImageType(finalMimeType) {
            dimensions = BlossomMediaProcessor.processImage(data)
        }

        // Create auth
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: sha256Hex,
            size: Int64(data.count),
            mimeType: finalMimeType,
            signer: signer,
            ndk: ndk,
            expiration: expiration
        )

        // Upload the file
        let blob = try await upload(
            data: data,
            mimeType: finalMimeType,
            to: serverURL,
            auth: auth
        )

        // Return blob with extracted metadata
        return BlossomBlob(
            sha256: blob.sha256,
            url: blob.url,
            size: blob.size,
            type: blob.type,
            uploaded: blob.uploaded,
            dimensions: dimensions
        )
    }

    /// Delete with automatic auth creation
    public func deleteWithAuth(
        sha256: String,
        from serverURL: String,
        signer: NDKSigner,
        ndk: NDK,
        reason: String? = nil
    ) async throws {
        let auth = try await BlossomAuth.createDeleteAuth(
            sha256: sha256,
            signer: signer,
            ndk: ndk,
            reason: reason
        )

        try await delete(sha256: sha256, from: serverURL, auth: auth)
    }

    /// List with automatic auth creation
    public func listWithAuth(
        from serverURL: String,
        signer: NDKSigner,
        ndk: NDK,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> [BlossomBlob] {
        let auth = try await BlossomAuth.createListAuth(
            signer: signer,
            ndk: ndk,
            since: since,
            until: until
        )

        return try await list(from: serverURL, auth: auth, since: since, until: until)
    }
}
