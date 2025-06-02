import Foundation

// MARK: - NDK Extensions for Blossom

extension NDK {
    /// Blossom client instance
    private static let blossomClientKey = "blossomClient"
    
    /// Get or create the Blossom client
    public var blossomClient: BlossomClient {
        if let existing = extensionData[Self.blossomClientKey] as? BlossomClient {
            return existing
        }
        
        let client = BlossomClient()
        extensionData[Self.blossomClientKey] = client
        return client
    }
    
    /// Upload a file to Blossom servers
    public func uploadToBlossom(
        data: Data,
        mimeType: String? = nil,
        servers: [String]? = nil,
        expiration: Date? = nil
    ) async throws -> [BlossomBlob] {
        guard let signer = signer else {
            throw NDKError.signingFailed
        }
        
        // Use provided servers or discover from relay list
        let targetServers: [String]
        if let servers = servers {
            targetServers = servers
        } else {
            targetServers = await discoverBlossomServers()
        }
        
        guard !targetServers.isEmpty else {
            throw BlossomError.invalidURL
        }
        
        var uploadedBlobs: [BlossomBlob] = []
        var lastError: Error?
        
        // Try uploading to multiple servers
        for server in targetServers {
            do {
                let blob = try await blossomClient.uploadWithAuth(
                    data: data,
                    mimeType: mimeType,
                    to: server,
                    signer: signer,
                    expiration: expiration
                )
                uploadedBlobs.append(blob)
            } catch {
                lastError = error
                print("Failed to upload to \(server): \(error)")
            }
        }
        
        if uploadedBlobs.isEmpty {
            throw lastError ?? BlossomError.uploadFailed("Failed to upload to any server")
        }
        
        return uploadedBlobs
    }
    
    /// Discover Blossom servers from relay configurations
    private func discoverBlossomServers() async -> [String] {
        // In a real implementation, this would:
        // 1. Query relays for NIP-89 application handler events
        // 2. Look for Blossom server announcements
        // 3. Check user's preferred servers from kind 10096 events
        
        // For now, return some known Blossom servers
        return [
            "https://blossom.primal.net",
            "https://media.nostr.band",
            "https://nostr.build"
        ]
    }
}

// MARK: - NDKEvent Extensions for Blossom

extension NDKEvent {
    /// Create a file metadata event (NIP-94) with Blossom URLs
    public static func createFileMetadata(
        blobs: [BlossomBlob],
        description: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        var tags: [[String]] = []
        
        // Add URL tags for each blob
        for blob in blobs {
            tags.append(["url", blob.url])
            tags.append(["x", blob.sha256])
            tags.append(["size", String(blob.size)])
            
            if let mimeType = blob.type {
                tags.append(["m", mimeType])
            }
        }
        
        // Add other metadata
        if let description = description {
            tags.append(["alt", description])
        }
        
        let pubkey = try await signer.pubkey
        var event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.fileMetadata,
            tags: tags,
            content: description ?? ""
        )
        
        // Generate ID and sign
        _ = try event.generateID()
        event.sig = try await signer.sign(event)
        
        return event
    }
    
    /// Extract Blossom URLs from a file metadata event
    public func extractBlossomURLs() -> [(url: String, sha256: String)] {
        guard kind == EventKind.fileMetadata else { return [] }
        
        var urls: [(url: String, sha256: String)] = []
        let urlTags = tags.filter { $0.first == "url" }
        let sha256Tags = tags.filter { $0.first == "x" }
        
        for (index, urlTag) in urlTags.enumerated() {
            guard urlTag.count > 1 else { continue }
            
            let url = urlTag[1]
            let sha256 = index < sha256Tags.count && sha256Tags[index].count > 1 
                ? sha256Tags[index][1] 
                : ""
            
            urls.append((url: url, sha256: sha256))
        }
        
        return urls
    }
    
    /// Create an image event with Blossom upload
    public static func createImageEvent(
        imageData: Data,
        mimeType: String,
        caption: String? = nil,
        ndk: NDK
    ) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.signingFailed
        }
        
        // Upload to Blossom
        let blobs = try await ndk.uploadToBlossom(
            data: imageData,
            mimeType: mimeType
        )
        
        guard let firstBlob = blobs.first else {
            throw BlossomError.uploadFailed("No blobs returned")
        }
        
        // Create image event with imeta tags
        var tags: [[String]] = []
        
        // Add imeta tag
        var imetaTag = ["imeta"]
        imetaTag.append("url \(firstBlob.url)")
        imetaTag.append("x \(firstBlob.sha256)")
        imetaTag.append("size \(firstBlob.size)")
        
        if let type = firstBlob.type {
            imetaTag.append("m \(type)")
        }
        
        // Add alt text if provided
        if let caption = caption {
            imetaTag.append("alt \(caption)")
            tags.append(["alt", caption])
        }
        
        tags.append(imetaTag)
        
        let pubkey = try await signer.pubkey
        var event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.image,
            tags: tags,
            content: caption ?? firstBlob.url
        )
        
        // Generate ID and sign
        _ = try event.generateID()
        event.sig = try await signer.sign(event)
        
        return event
    }
}

// MARK: - Extension Data Storage

extension NDK {
    /// Storage for extension data
    private static var _extensionData = [String: Any]()
    
    /// Access extension data
    fileprivate var extensionData: [String: Any] {
        get { Self._extensionData }
        set { Self._extensionData = newValue }
    }
}