import Foundation

// MARK: - Blossom Types

/// Represents a Blossom server
public struct BlossomServer: Codable, Sendable {
    public let url: String
    public let name: String?
    public let description: String?
    public let supportedMimeTypes: [String]?
    public let maxFileSize: Int64?

    public init(
        url: String,
        name: String? = nil,
        description: String? = nil,
        supportedMimeTypes: [String]? = nil,
        maxFileSize: Int64? = nil
    ) {
        self.url = url
        self.name = name
        self.description = description
        self.supportedMimeTypes = supportedMimeTypes
        self.maxFileSize = maxFileSize
    }
}

/// Represents a blob/file in Blossom
public struct BlossomBlob: Codable, Sendable {
    public let sha256: String
    public let url: String
    public let size: Int64
    public let type: String?
    public let uploaded: Date

    public init(
        sha256: String,
        url: String,
        size: Int64,
        type: String? = nil,
        uploaded: Date = Date()
    ) {
        self.sha256 = sha256
        self.url = url
        self.size = size
        self.type = type
        self.uploaded = uploaded
    }
}

/// Upload descriptor for BUD-02
public struct BlossomUploadDescriptor: Codable {
    public let url: String
    public let sha256: String
    public let size: Int64
    public let type: String?
    public let uploaded: Int64

    enum CodingKeys: String, CodingKey {
        case url
        case sha256
        case size
        case type
        case uploaded
    }
}

/// List response for BUD-03
public struct BlossomListResponse: Codable {
    public let blobs: [BlossomListItem]

    public struct BlossomListItem: Codable {
        public let sha256: String
        public let size: Int64
        public let type: String?
        public let uploaded: Int64
    }
}

/// Authorization for Blossom operations
public struct BlossomAuth {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create authorization event for upload
    public static func createUploadAuth(
        sha256: String,
        size: Int64,
        mimeType: String? = nil,
        signer: NDKSigner,
        expiration: Date? = nil
    ) async throws -> BlossomAuth {
        var tags: [[String]] = [
            ["t", "upload"],
            ["x", sha256],
            ["size", String(size)],
        ]

        if let mimeType = mimeType {
            tags.append(["type", mimeType])
        }

        if let expiration = expiration {
            tags.append(["expiration", String(Int(expiration.timeIntervalSince1970))])
        }

        let pubkey = try await signer.pubkey
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24242, // Blossom auth kind
            tags: tags,
            content: "Authorize upload"
        )

        // Generate ID and sign
        _ = try event.generateID()
        event.sig = try await signer.sign(event)

        return BlossomAuth(event: event)
    }

    /// Create authorization event for delete
    public static func createDeleteAuth(
        sha256: String,
        signer: NDKSigner,
        reason: String? = nil
    ) async throws -> BlossomAuth {
        let tags: [[String]] = [
            ["t", "delete"],
            ["x", sha256],
        ]

        let pubkey = try await signer.pubkey
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24242,
            tags: tags,
            content: reason ?? "Delete blob"
        )

        // Generate ID and sign
        _ = try event.generateID()
        event.sig = try await signer.sign(event)

        return BlossomAuth(event: event)
    }

    /// Create authorization event for list
    public static func createListAuth(
        signer: NDKSigner,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> BlossomAuth {
        var tags: [[String]] = [
            ["t", "list"],
        ]

        if let since = since {
            tags.append(["since", String(Int(since.timeIntervalSince1970))])
        }

        if let until = until {
            tags.append(["until", String(Int(until.timeIntervalSince1970))])
        }

        let pubkey = try await signer.pubkey
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24242,
            tags: tags,
            content: "List blobs"
        )

        // Generate ID and sign
        _ = try event.generateID()
        event.sig = try await signer.sign(event)

        return BlossomAuth(event: event)
    }

    /// Get base64-encoded authorization header value
    public func authorizationHeaderValue() throws -> String {
        let eventJSON = try event.serialize()
        let eventData = eventJSON.data(using: .utf8)!
        return "Nostr " + eventData.base64EncodedString()
    }
}

/// Blossom error types
public enum BlossomError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String?)
    case fileTooLarge
    case unsupportedMimeType
    case blobNotFound
    case uploadFailed(String)
    case networkError(Error)
    case invalidSHA256

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Blossom server URL"
        case .invalidResponse:
            return "Invalid response from Blossom server"
        case .unauthorized:
            return "Unauthorized - invalid or expired authorization"
        case let .serverError(code, message):
            return "Server error \(code): \(message ?? "Unknown error")"
        case .fileTooLarge:
            return "File exceeds maximum size limit"
        case .unsupportedMimeType:
            return "File type not supported by this server"
        case .blobNotFound:
            return "Blob not found on server"
        case let .uploadFailed(message):
            return "Upload failed: \(message)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case .invalidSHA256:
            return "Invalid SHA256 hash"
        }
    }
}

/// Blossom server descriptor (from /.well-known/blossom)
public struct BlossomServerDescriptor: Codable {
    public let name: String?
    public let description: String?
    public let icon: String?
    public let acceptsMimeTypes: [String]?
    public let maxUploadSize: Int64?
    public let uploadUrl: String?
    public let listUrl: String?
    public let deleteUrl: String?
    public let mirrorUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case icon
        case acceptsMimeTypes = "accepts_mime_types"
        case maxUploadSize = "max_upload_size"
        case uploadUrl = "upload_url"
        case listUrl = "list_url"
        case deleteUrl = "delete_url"
        case mirrorUrl = "mirror_url"
    }
}
