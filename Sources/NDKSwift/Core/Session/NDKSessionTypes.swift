import Foundation

/// Types of data that can be loaded as part of a session
public enum SessionData: Hashable {
    case followList
    case webOfTrust(depth: Int = 2)
    case muteList
    case blockedRelays
    case relayList
}

/// Configuration for session data requirements
public struct NDKSessionConfiguration {
    /// Data requirements for the session
    public let dataRequirements: Set<SessionData>
    
    /// Strategy for preloading data
    public let preloadStrategy: PreloadStrategy
    
    public enum PreloadStrategy {
        case blocking       // Wait for all data before session ready
        case progressive    // Session ready with cache, update in background
        case lazy          // Load on demand
    }
    
    /// Initialize with data requirements
    /// - Parameters:
    ///   - dataRequirements: Set of data to load (defaults to followList)
    ///   - preloadStrategy: Loading strategy (defaults to progressive)
    public init(
        dataRequirements: Set<SessionData> = [.followList],
        preloadStrategy: PreloadStrategy = .progressive
    ) {
        self.dataRequirements = dataRequirements
        self.preloadStrategy = preloadStrategy
    }
}

/// Reactive filter that automatically updates when dependencies change
public struct ReactiveFilter {
    /// Dependencies that trigger filter updates
    public let dependencies: Set<SessionData>
    
    /// Builder function to create filter from session
    public let builder: (NDKSessionData) -> NDKFilter
    
    /// Configuration for Web of Trust filtering
    public let wotConfig: WOTConfiguration?
    
    /// Initialize reactive filter
    /// - Parameters:
    ///   - dependencies: Data dependencies
    ///   - wotConfig: Optional WOT configuration
    ///   - builder: Function to build filter from session data
    public init(
        dependencies: Set<SessionData>,
        wotConfig: WOTConfiguration? = nil,
        builder: @escaping (NDKSessionData) -> NDKFilter
    ) {
        self.dependencies = dependencies
        self.wotConfig = wotConfig
        self.builder = builder
    }
}

/// Web of Trust configuration
public struct WOTConfiguration {
    /// Minimum score required to pass filter
    public let minimumScore: Int
    
    /// Whether to automatically include direct follows
    public let includeDirectFollows: Bool
    
    /// Initialize WOT configuration
    /// - Parameters:
    ///   - minimumScore: Minimum connection score (default: 2)
    ///   - includeDirectFollows: Auto-include direct follows (default: true)
    public init(
        minimumScore: Int = 2,
        includeDirectFollows: Bool = true
    ) {
        self.minimumScore = minimumScore
        self.includeDirectFollows = includeDirectFollows
    }
}

/// State of session data
public enum DataState<T> {
    case loading
    case ready(T, fromCache: Bool)
    case updating(current: T, changes: T)
    case error(Error)
    
    /// Whether data is available (ready or updating)
    public var isAvailable: Bool {
        switch self {
        case .ready, .updating:
            return true
        case .loading, .error:
            return false
        }
    }
    
    /// Get current data if available
    public var data: T? {
        switch self {
        case .ready(let data, _):
            return data
        case .updating(let current, _):
            return current
        case .loading, .error:
            return nil
        }
    }
}