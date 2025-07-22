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
    
    // Media metadata (calculated client-side for images)
    public let blurhash: String?
    public let dimensions: (width: Int, height: Int)?

    public init(
        sha256: String,
        url: String,
        size: Int64,
        type: String? = nil,
        uploaded: Date = Date(),
        blurhash: String? = nil,
        dimensions: (width: Int, height: Int)? = nil
    ) {
        self.sha256 = sha256
        self.url = url
        self.size = size
        self.type = type
        self.uploaded = uploaded
        self.blurhash = blurhash
        self.dimensions = dimensions
    }
    
    /// Get dimensions as NIP-92 format string (e.g., "1920x1080")
    public var dimensionsString: String? {
        guard let dimensions = dimensions else { return nil }
        return "\(dimensions.width)x\(dimensions.height)"
    }
    
    // Custom coding to handle tuple
    enum CodingKeys: String, CodingKey {
        case sha256, url, size, type, uploaded, blurhash
        case dimensionWidth, dimensionHeight
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha256 = try container.decode(String.self, forKey: .sha256)
        url = try container.decode(String.self, forKey: .url)
        size = try container.decode(Int64.self, forKey: .size)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        uploaded = try container.decode(Date.self, forKey: .uploaded)
        blurhash = try container.decodeIfPresent(String.self, forKey: .blurhash)
        
        if let width = try container.decodeIfPresent(Int.self, forKey: .dimensionWidth),
           let height = try container.decodeIfPresent(Int.self, forKey: .dimensionHeight) {
            dimensions = (width: width, height: height)
        } else {
            dimensions = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(url, forKey: .url)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encode(uploaded, forKey: .uploaded)
        try container.encodeIfPresent(blurhash, forKey: .blurhash)
        try container.encodeIfPresent(dimensions?.width, forKey: .dimensionWidth)
        try container.encodeIfPresent(dimensions?.height, forKey: .dimensionHeight)
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
            ["size", String(size)]
        ]

        if let mimeType = mimeType {
            tags.append(["type", mimeType])
        }

        if let expiration = expiration {
            tags.append(["expiration", String(Timestamp.from(expiration))])
        }

        let event = try await NDKEventBuilder()
            .content("Authorize upload")
            .kind(EventKind.blossomAuth)
            .tags(tags)
            .build(signer: signer)

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
            ["x", sha256]
        ]

        let event = try await NDKEventBuilder()
            .content(reason ?? "Delete blob")
            .kind(EventKind.blossomAuth)
            .tags(tags)
            .build(signer: signer)

        return BlossomAuth(event: event)
    }

    /// Create authorization event for list
    public static func createListAuth(
        signer: NDKSigner,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> BlossomAuth {
        var tags: [[String]] = [
            ["t", "list"]
        ]

        if let since = since {
            tags.append(["since", String(Timestamp.from(since))])
        }

        if let until = until {
            tags.append(["until", String(Timestamp.from(until))]) 
        }

        let event = try await NDKEventBuilder()
            .content("List blobs")
            .kind(EventKind.blossomAuth)
            .tags(tags)
            .build(signer: signer)

        return BlossomAuth(event: event)
    }

    /// Get base64-encoded authorization header value
    public func authorizationHeaderValue() throws -> String {
        let eventJSON = try event.serialize()
        let eventData = eventJSON.data(using: .utf8)!
        return "Nostr " + eventData.base64EncodedString()
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
