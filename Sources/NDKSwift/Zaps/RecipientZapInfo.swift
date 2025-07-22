import Foundation

/// All zap-related information for a recipient, fetched once and cached
public struct RecipientZapInfo {
    public let pubkey: String
    public let profile: NDKUserProfile?              // From kind:0
    public let nutzapPreferences: NDKNutzapPreferences? // From kind:10019
    public let fetchedAt: Date
    
    // MARK: - Computed Properties
    
    /// Lightning address from profile (lud16 or lud06)
    public var lightningAddress: String? {
        profile?.lud16 ?? profile?.lud06
    }
    
    /// Whether the recipient supports Lightning zaps
    public var hasLightningSupport: Bool {
        lightningAddress != nil
    }
    
    /// Whether the recipient supports Nutzaps
    public var hasNutzapSupport: Bool {
        guard let preferences = nutzapPreferences else { return false }
        // Must have at least one mint configured
        return preferences.hasMints
    }
    
    /// All supported zap types
    public var supportedZapTypes: Set<ZapType> {
        var types = Set<ZapType>()
        if hasLightningSupport { types.insert(.lightning) }
        if hasNutzapSupport { types.insert(.nutzap) }
        return types
    }
    
    /// Check if a specific zap type is supported
    public func supports(_ zapType: ZapType) -> Bool {
        supportedZapTypes.contains(zapType)
    }
    
    /// Get all nutzap mints if available
    public var nutzapMints: [NDKNutzapPreferences.MintConfig] {
        get async {
            await nutzapPreferences?.mints ?? []
        }
    }
    
    /// Get all nutzap mint URLs
    public var nutzapMintURLs: [URL] {
        get async {
            await nutzapMints.map { $0.url }
        }
    }
    
    /// Get nutzap P2PK pubkey if available
    public var nutzapP2PKPubkey: String? {
        get async {
            await nutzapPreferences?.p2pkPubkey
        }
    }
    
    /// Get all relays associated with nutzap mints
    /// Returns empty set if no specific relays configured (will use user's relays)
    public var nutzapRelays: Set<String> {
        get async {
            var allRelays = Set<String>()
            for mint in await nutzapMints {
                allRelays.formUnion(mint.relays)
            }
            return allRelays
        }
    }
    
    /// Check if the cached data is still fresh
    public func isFresh(maxAge: TimeInterval = TimeConstants.day) -> Bool {
        Date().timeIntervalSince(fetchedAt) < maxAge
    }
}

// MARK: - Factory Methods

extension RecipientZapInfo {
    /// Create from fetched events
    static func from(
        pubkey: String,
        events: [NDKEvent]
    ) async -> RecipientZapInfo {
        var profile: NDKUserProfile?
        var nutzapPreferences: NDKNutzapPreferences?
        
        for event in events {
            switch event.kind {
            case EventKind.metadata:
                if let decodedProfile = JSONCoding.safeDecode(NDKUserProfile.self, from: event.content) {
                    profile = decodedProfile
                }
                
            case EventKind.nutzapPreferences:
                nutzapPreferences = NDKNutzapPreferences(event: event)
                
            default:
                break
            }
        }
        
        return RecipientZapInfo(
            pubkey: pubkey,
            profile: profile,
            nutzapPreferences: nutzapPreferences,
            fetchedAt: Date()
        )
    }
}