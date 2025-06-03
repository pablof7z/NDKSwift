import Foundation

/// Represents relay information for a specific user in the outbox model
public struct NDKOutboxItem: Codable, Equatable {
    /// The user's public key
    public let pubkey: String
    
    /// Relays the user reads from
    public let readRelays: Set<RelayInfo>
    
    /// Relays the user writes to
    public let writeRelays: Set<RelayInfo>
    
    /// When this information was last fetched
    public let fetchedAt: Date
    
    /// Optional metadata about relay list source (kind 10002 vs kind 3)
    public let source: RelayListSource
    
    public init(
        pubkey: String,
        readRelays: Set<RelayInfo>,
        writeRelays: Set<RelayInfo>,
        fetchedAt: Date = Date(),
        source: RelayListSource = .unknown
    ) {
        self.pubkey = pubkey
        self.readRelays = readRelays
        self.writeRelays = writeRelays
        self.fetchedAt = fetchedAt
        self.source = source
    }
    
    /// Get all unique relay URLs (both read and write)
    public var allRelayURLs: Set<String> {
        let readURLs = readRelays.map { $0.url }
        let writeURLs = writeRelays.map { $0.url }
        return Set(readURLs + writeURLs)
    }
    
    /// Check if this item has expired based on TTL
    public func isExpired(ttl: TimeInterval) -> Bool {
        return Date().timeIntervalSince(fetchedAt) > ttl
    }
}

/// Information about a specific relay
public struct RelayInfo: Codable, Hashable, Equatable {
    /// The relay URL (normalized)
    public let url: String
    
    /// Optional relay metadata
    public let metadata: RelayMetadata?
    
    public init(url: String, metadata: RelayMetadata? = nil) {
        self.url = url
        self.metadata = metadata
    }
    
    // Hashable conformance only considers URL
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    public static func == (lhs: RelayInfo, rhs: RelayInfo) -> Bool {
        return lhs.url == rhs.url
    }
}

/// Metadata about a relay
public struct RelayMetadata: Codable, Equatable {
    /// Relay health score (0-1)
    public let score: Double?
    
    /// Last successful connection time
    public let lastConnectedAt: Date?
    
    /// Average response time in milliseconds
    public let avgResponseTime: Double?
    
    /// Number of failed attempts
    public let failureCount: Int
    
    /// Whether authentication is required
    public let authRequired: Bool
    
    /// Whether payment is required
    public let paymentRequired: Bool
    
    public init(
        score: Double? = nil,
        lastConnectedAt: Date? = nil,
        avgResponseTime: Double? = nil,
        failureCount: Int = 0,
        authRequired: Bool = false,
        paymentRequired: Bool = false
    ) {
        self.score = score
        self.lastConnectedAt = lastConnectedAt
        self.avgResponseTime = avgResponseTime
        self.failureCount = failureCount
        self.authRequired = authRequired
        self.paymentRequired = paymentRequired
    }
}

/// Source of relay list information
public enum RelayListSource: String, Codable {
    /// NIP-65 relay list (kind 10002)
    case nip65 = "nip65"
    
    /// Contact list (kind 3)
    case contactList = "contactList"
    
    /// Manually configured
    case manual = "manual"
    
    /// Unknown source
    case unknown = "unknown"
}