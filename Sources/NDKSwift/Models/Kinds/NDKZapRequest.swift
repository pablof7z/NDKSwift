import Foundation

/// NIP-57 Zap Request (kind: 9734)
/// A zap request is an event that is not published to relays, but sent to a recipient's
/// lightning wallet callback URL to request an invoice.
public struct NDKZapRequest {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create a new zap request
    public static func create(
        ndk: NDK,
        recipient: NDKUser,
        amountMillisats: Int64,
        comment: String? = nil,
        relays: [String],
        zappedEvent: NDKEvent? = nil,
        zappedEventCoordinate: String? = nil
    ) async throws -> NDKZapRequest {
        let event = NDKEvent(
            pubkey: "", // Will be set by signer
            kind: EventKind.zapRequest,
            content: comment ?? ""
        )
        
        var tags: [[String]] = []
        
        // Required tags
        tags.append(["p", recipient.pubkey])
        tags.append(["relays"] + relays)
        tags.append(["amount", String(amountMillisats)])
        
        // Optional: lnurl tag
        if let profile = try? await recipient.fetchProfile(),
           let lnurl = profile.lud06 ?? profile.lud16 {
            let encoded = try encodeLNURL(lnurl)
            tags.append(["lnurl", encoded])
        }
        
        // Optional: zapped event
        if let zappedEvent = zappedEvent {
            let eventId = await zappedEvent.id
            if let eventId = eventId {
                tags.append(["e", eventId])
            }
        }
        
        // Optional: zapped event coordinate (for addressable events)
        if let coordinate = zappedEventCoordinate {
            tags.append(["a", coordinate])
        }
        
        for tag in tags {
            event.addTag(tag)
        }
        try await event.sign()
        
        return NDKZapRequest(event: event)
    }
    
    // MARK: - Computed Properties
    
    /// Amount in millisatoshis
    public var amountMillisats: Int64? {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "amount" })?[safe: 1].flatMap { Int64($0) }
        }
    }
    
    /// Amount in satoshis
    public var amountSats: Int64? {
        get async {
            let millis = await amountMillisats
            return millis.map { $0 / 1000 }
        }
    }
    
    /// Optional comment
    public var comment: String? {
        get async {
            let content = await event.content
            return content.isEmpty ? nil : content
        }
    }
    
    /// Recipient's pubkey
    public var recipientPubkey: String? {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "p" })?[safe: 1]
        }
    }
    
    /// Relays where the zap receipt should be published
    public var relays: [String] {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "relays" })?.dropFirst().map { String($0) } ?? []
        }
    }
    
    /// LNURL if present
    public var lnurl: String? {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "lnurl" })?[safe: 1]
        }
    }
    
    /// Zapped event ID if this is zapping an event
    public var zappedEventId: String? {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "e" })?[safe: 1]
        }
    }
    
    /// Zapped event coordinate for addressable events
    public var zappedEventCoordinate: String? {
        get async {
            let tags = await event.tags
            return tags.first(where: { $0.first == "a" })?[safe: 1]
        }
    }
    
    /// Encode as JSON for sending to LNURL callback
    public func encodeForCallback() throws -> String {
        let jsonData = try JSONEncoder().encode(event)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }
}

// MARK: - LNURL Encoding

private func encodeLNURL(_ input: String) throws -> String {
    // Handle both lud06 (LNURL) and lud16 (Lightning Address) formats
    if input.lowercased().starts(with: "lnurl") {
        // Already encoded
        return input
    } else if input.contains("@") {
        // Lightning address format: convert to URL
        let parts = input.split(separator: "@")
        guard parts.count == 2 else {
            throw NDKError.invalidInput(message: "Invalid lightning address format")
        }
        let username = String(parts[0])
        let domain = String(parts[1])
        let url = "https://\(domain)/.well-known/lnurlp/\(username)"
        
        // Encode to bech32
        guard let data = url.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Failed to encode URL")
        }
        
        return try Bech32.encode(hrp: "lnurl", data: Array(data))
    } else {
        // Assume it's a URL that needs encoding
        guard let data = input.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Failed to encode URL")
        }
        
        return try Bech32.encode(hrp: "lnurl", data: Array(data))
    }
}
