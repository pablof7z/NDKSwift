import Foundation

/// Service for discovering Cashu mints via Nostr (NIP-60)
public actor MintDiscovery {
    private let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Discovered mint with reputation information
    public struct DiscoveredMint: Sendable {
        public let announcement: NDKMintAnnouncement
        public let event: NDKEvent
        public let reputation: MintReputation
        
        public init(announcement: NDKMintAnnouncement, event: NDKEvent, reputation: MintReputation) {
            self.announcement = announcement
            self.event = event
            self.reputation = reputation
        }
    }
    
    /// Mint reputation based on announcement metadata
    public struct MintReputation: Sendable {
        public let publisherPubkey: String
        public let publishedAt: Date
        public let relaysFound: [String]
        public let trustScore: Double  // 0.0 - 1.0
        
        public init(publisherPubkey: String, publishedAt: Date, relaysFound: [String], trustScore: Double) {
            self.publisherPubkey = publisherPubkey
            self.publishedAt = publishedAt
            self.relaysFound = relaysFound
            self.trustScore = trustScore
        }
    }
    
    /// Discovers mints from Nostr events
    public func discoverMints(
        from relays: [String]? = nil,
        limit: Int = 100,
        units: [String]? = nil,
        since: Date? = nil
    ) async throws -> [DiscoveredMint] {
        // Prepare tags
        var tags: [String: Set<String>]? = nil
        if let units = units, !units.isEmpty {
            tags = ["unit": Set(units)]
        }
        
        // Create filter
        let filter = NDKFilter(
            kinds: [38000], // Mint announcement events
            since: since.map { Timestamp($0.timeIntervalSince1970) },
            limit: limit,
            tags: tags
        )
        
        // Fetch events
        let events = try await ndk.fetchEvents(filter)
        
        // Parse and score mints
        var discoveredMints: [DiscoveredMint] = []
        
        for event in events {
            guard let announcement = try? event.parseMintAnnouncement() else {
                continue
            }
            
            // Calculate reputation
            let reputation = await calculateReputation(for: event, announcement: announcement)
            
            let discovered = DiscoveredMint(
                announcement: announcement,
                event: event,
                reputation: reputation
            )
            
            discoveredMints.append(discovered)
        }
        
        // Sort by trust score (highest first)
        discoveredMints.sort { $0.reputation.trustScore > $1.reputation.trustScore }
        
        return discoveredMints
    }
    
    /// Discovers a specific mint by URL
    public func discoverMint(url: URL, from relays: [String]? = nil) async throws -> [DiscoveredMint] {
        let filter = NDKFilter(kinds: [38000], tags: ["u": Set([url.absoluteString])])
        
        let events = try await ndk.fetchEvents(filter)
        
        var discoveredMints: [DiscoveredMint] = []
        
        for event in events {
            guard let announcement = try? event.parseMintAnnouncement() else {
                continue
            }
            
            let reputation = await calculateReputation(for: event, announcement: announcement)
            
            let discovered = DiscoveredMint(
                announcement: announcement,
                event: event,
                reputation: reputation
            )
            
            discoveredMints.append(discovered)
        }
        
        return discoveredMints
    }
    
    /// Publishes a mint announcement to Nostr
    public func announceMint(_ announcement: NDKMintAnnouncement, to relays: [String]? = nil) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let pubkey = try await signer.pubkey
        let event = try await NDKEvent.mintAnnouncement(announcement: announcement, pubkey: pubkey, signer: signer)
        
        try await ndk.publish(event)
        
        return event
    }
    
    // MARK: - Private Methods
    
    private func calculateReputation(for event: NDKEvent, announcement: NDKMintAnnouncement) async -> MintReputation {
        var score = 0.5  // Base score
        
        // Increase score for well-formed announcements
        if announcement.name != nil { score += 0.1 }
        if announcement.description != nil { score += 0.1 }
        if announcement.pubkey != nil { score += 0.1 }
        if announcement.contact != nil && !announcement.contact!.isEmpty { score += 0.1 }
        
        // Decrease score for suspicious URLs
        if isSuspiciousMint(announcement.mintURL) {
            score -= 0.3
        }
        
        // Cap score between 0 and 1
        score = max(0, min(1, score))
        
        let reputation = MintReputation(
            publisherPubkey: event.pubkey,
            publishedAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            relaysFound: [], // TODO: Track which relays returned this event
            trustScore: score
        )
        
        return reputation
    }
    
    /// Checks if a mint URL appears suspicious
    public func isSuspiciousMint(_ mintURL: URL) -> Bool {
        // Check for localhost/local network
        if let host = mintURL.host {
            if host == "localhost" || host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasPrefix("10.") {
                return true
            }
        }
        
        // Check for non-HTTPS in production
        if mintURL.scheme != "https" && mintURL.host != "localhost" {
            return true
        }
        
        // Check for uncommon ports
        if let port = mintURL.port, ![80, 443, 3338, 8080, 8333].contains(port) {
            return true
        }
        
        return false
    }
}