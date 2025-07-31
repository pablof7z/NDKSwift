import Foundation

/// Options for configuring NDKSubscription behavior
public struct NDKSubscriptionOptions {
    /// Maximum age of events to return from cache (0 = no limit)
    public var maxAge: TimeInterval
    
    /// Cache policy for the data source
    public var cachePolicy: CachePolicy
    
    /// Specific relays to use (nil = use default relays)
    public var relays: Set<RelayURL>?
    
    /// Whether to use only specified relays (true) or combine with defaults (false)
    public var exclusiveRelays: Bool
    
    /// Custom subscription ID (nil = auto-generate)
    public var subscriptionId: String?
    
    /// Whether to close subscription on EOSE (nil = auto-determine based on filter)
    public var closeOnEose: Bool?
    
    /// Whether this subscription can be grouped with others
    public var groupable: Bool
    
    /// Delay before executing grouped subscriptions (nil uses default)
    public var groupableDelay: TimeInterval?
    
    /// Type of delay constraint
    public var groupableDelayType: NDKSubscriptionDelayType?
    
    /// Creates default data source options
    public init(
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        groupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil
    ) {
        self.maxAge = maxAge
        self.cachePolicy = cachePolicy
        self.relays = relays
        self.exclusiveRelays = exclusiveRelays
        self.subscriptionId = subscriptionId
        self.closeOnEose = closeOnEose
        self.groupable = groupable
        self.groupableDelay = groupableDelay
        self.groupableDelayType = groupableDelayType
    }
    
    /// Default options
    public static let `default` = NDKSubscriptionOptions()
    
    /// Cache-only options
    public static let cacheOnly = NDKSubscriptionOptions(cachePolicy: .cacheOnly)
    
    /// Network-only options
    public static let networkOnly = NDKSubscriptionOptions(cachePolicy: .networkOnly)
}