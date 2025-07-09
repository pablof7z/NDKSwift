import Foundation
#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Blossom client for interacting with Blossom servers
public actor BlossomClient {
    private let urlSession: URLSession
    private var serverCache: [String: BlossomServerDescriptor] = [:]

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - BUD-01: Server Discovery

    /// Discover Blossom server capabilities
    public func discoverServer(_ serverURL: String) async throws -> BlossomServerDescriptor {
        // Check cache first
        if let cached = serverCache[serverURL] {
            return cached
        }

        guard let baseURL = URL(string: serverURL) else {
            throw NDKError.invalidURL(serverURL)
        }

        let wellKnownURL = baseURL.appendingPathComponent(".well-known/blossom")

        var request = URLRequest(url: wellKnownURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Blossom server")
            }

            guard httpResponse.statusCode == 200 else {
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: nil)
            }

            let descriptor = try JSONDecoder().decode(BlossomServerDescriptor.self, from: data)

            // Cache the descriptor
            serverCache[serverURL] = descriptor

            return descriptor
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.connectionFailed(relay: serverURL, message: "Network error", underlying: error)
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
        guard let baseURL = URL(string: serverURL) else {
            throw NDKError.invalidURL(serverURL)
        }

        // Calculate SHA256
        let sha256 = SHA256.hash(data: data)
        let sha256Hex = sha256.compactMap { String(format: "%02x", $0) }.joined()

        // Check if we need to discover the server first
        let descriptor = try? await discoverServer(serverURL)

        // Validate file size if server has limits
        if let maxSize = descriptor?.maxUploadSize, data.count > maxSize {
            throw NDKError.fileTooLarge(maxSize: maxSize)
        }

        // Validate mime type if server has restrictions
        if let acceptedTypes = descriptor?.acceptsMimeTypes,
           let mimeType = mimeType,
           !acceptedTypes.contains(mimeType) && !acceptedTypes.contains("*/*") {
            throw NDKError.unsupportedMimeType(mimeType ?? "unknown")
        }

        // Construct upload URL
        let uploadPath = descriptor?.uploadUrl ?? "/upload"
        let uploadURL = baseURL.appendingPathComponent(uploadPath)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data

        // Set headers
        if let mimeType = mimeType {
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        }

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (responseData, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Blossom server")
            }

            switch httpResponse.statusCode {
            case 200, 201:
                let uploadDescriptor = try JSONDecoder().decode(BlossomUploadDescriptor.self, from: responseData)

                // Verify SHA256 matches
                guard uploadDescriptor.sha256 == sha256Hex else {
                    throw NDKError.invalidSHA256(sha256Hex)
                }

                return BlossomBlob(
                    sha256: uploadDescriptor.sha256,
                    url: uploadDescriptor.url,
                    size: uploadDescriptor.size,
                    type: uploadDescriptor.type,
                    uploaded: Date(timeIntervalSince1970: TimeInterval(uploadDescriptor.uploaded))
                )

            case 401:
                throw NDKError.unauthorized(relay: serverURL, message: "Blossom authorization failed")

            case 413:
                throw NDKError.fileTooLarge(maxSize: descriptor?.maxUploadSize ?? Int64.max)

            case 415:
                throw NDKError.unsupportedMimeType(mimeType ?? "unknown")

            default:
                let errorMessage = String(data: responseData, encoding: .utf8)
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: errorMessage)
            }
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.connectionFailed(relay: serverURL, message: "Network error", underlying: error)
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
        guard let baseURL = URL(string: serverURL) else {
            throw NDKError.invalidURL(serverURL)
        }

        let descriptor = try? await discoverServer(serverURL)
        let listPath = descriptor?.listUrl ?? "/list"

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(listPath), resolvingAgainstBaseURL: true)!

        // Add query parameters
        var queryItems: [URLQueryItem] = []
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(Int(since.timeIntervalSince1970))))
        }
        if let until = until {
            queryItems.append(URLQueryItem(name: "until", value: String(Int(until.timeIntervalSince1970))))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        guard let listURL = urlComponents.url else {
            throw NDKError.invalidURL(serverURL)
        }

        var request = URLRequest(url: listURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Blossom server")
            }

            switch httpResponse.statusCode {
            case 200:
                let listResponse = try JSONDecoder().decode(BlossomListResponse.self, from: data)

                return listResponse.blobs.map { item in
                    BlossomBlob(
                        sha256: item.sha256,
                        url: "\(serverURL)/\(item.sha256)",
                        size: item.size,
                        type: item.type,
                        uploaded: Date(timeIntervalSince1970: TimeInterval(item.uploaded))
                    )
                }

            case 401:
                throw NDKError.unauthorized(relay: serverURL, message: "Blossom authorization failed")

            default:
                let errorMessage = String(data: data, encoding: .utf8)
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: errorMessage)
            }
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.connectionFailed(relay: serverURL, message: "Network error", underlying: error)
        }
    }

    // MARK: - BUD-04: Delete

    /// Delete a blob from a Blossom server
    public func delete(
        sha256: String,
        from serverURL: String,
        auth: BlossomAuth
    ) async throws {
        guard let baseURL = URL(string: serverURL) else {
            throw NDKError.invalidURL(serverURL)
        }

        let deleteURL = baseURL.appendingPathComponent(sha256)

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"

        let authHeader = try auth.authorizationHeaderValue()
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Blossom server")
            }

            switch httpResponse.statusCode {
            case 200, 204:
                // Success
                return

            case 401:
                throw NDKError.unauthorized(relay: serverURL, message: "Blossom authorization failed")

            case 404:
                throw NDKError.blobNotFound(sha256: sha256)

            default:
                let errorMessage = String(data: data, encoding: .utf8)
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: errorMessage)
            }
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.connectionFailed(relay: serverURL, message: "Network error", underlying: error)
        }
    }

    // MARK: - Download

    /// Download a blob from a Blossom server
    public func download(
        sha256: String,
        from serverURL: String
    ) async throws -> Data {
        guard let url = URL(string: "\(serverURL)/\(sha256)") else {
            throw NDKError.invalidURL(serverURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NDKError.invalidResponse(from: "Blossom server")
            }

            switch httpResponse.statusCode {
            case 200:
                // Verify SHA256
                let downloadedSHA256 = SHA256.hash(data: data)
                let downloadedHex = downloadedSHA256.compactMap { String(format: "%02x", $0) }.joined()

                guard downloadedHex == sha256 else {
                    throw NDKError.invalidSHA256(sha256)
                }

                return data

            case 404:
                throw NDKError.blobNotFound(sha256: sha256)

            default:
                let errorMessage = String(data: data, encoding: .utf8)
                throw NDKError.serverError(relay: serverURL, code: httpResponse.statusCode, message: errorMessage)
            }
        } catch let error as NDKError {
            throw error
        } catch {
            throw NDKError.connectionFailed(relay: serverURL, message: "Network error", underlying: error)
        }
    }

    // MARK: - Convenience Methods

    /// Upload with automatic auth creation
    public func uploadWithAuth(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        signer: NDKSigner,
        expiration: Date? = nil
    ) async throws -> BlossomBlob {
        // Calculate SHA256
        let sha256 = SHA256.hash(data: data)
        let sha256Hex = sha256.compactMap { String(format: "%02x", $0) }.joined()

        // Create auth
        let auth = try await BlossomAuth.createUploadAuth(
            sha256: sha256Hex,
            size: Int64(data.count),
            mimeType: mimeType,
            signer: signer,
            expiration: expiration
        )

        return try await upload(
            data: data,
            mimeType: mimeType,
            to: serverURL,
            auth: auth
        )
    }

    /// Delete with automatic auth creation
    public func deleteWithAuth(
        sha256: String,
        from serverURL: String,
        signer: NDKSigner,
        reason: String? = nil
    ) async throws {
        let auth = try await BlossomAuth.createDeleteAuth(
            sha256: sha256,
            signer: signer,
            reason: reason
        )

        try await delete(sha256: sha256, from: serverURL, auth: auth)
    }

    /// List with automatic auth creation
    public func listWithAuth(
        from serverURL: String,
        signer: NDKSigner,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> [BlossomBlob] {
        let auth = try await BlossomAuth.createListAuth(
            signer: signer,
            since: since,
            until: until
        )

        return try await list(from: serverURL, auth: auth, since: since, until: until)
    }
}
