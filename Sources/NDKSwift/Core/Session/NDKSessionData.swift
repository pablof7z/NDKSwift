import Foundation
import Observation

/// Observable session data manager
@Observable
public class NDKSessionData {
    /// User's public key
    public let pubkey: String
    
    /// NDK instance
    private weak var ndk: NDK?
    
    /// Follow list state
    public private(set) var followListState: DataState<Set<String>> = .loading
    
    /// Computed follow list
    public var followList: Set<String> {
        followListState.data ?? []
    }
    
    /// Latest follow list event ID for delta detection
    private var latestFollowListEventId: String?
    
    /// Lazy-loaded Web of Trust scores
    private var _wotScores: [String: Int]?
    private var wotLastUpdated: Date?
    private var wotTimer: Timer?
    
    /// Whether session is ready (all required data loaded)
    public private(set) var isReady = false
    
    /// Active data source for follow list
    private var followListDataSource: NDKDataSource<NDKEvent>?
    
    /// Initialize session data
    /// - Parameters:
    ///   - pubkey: User's public key
    ///   - ndk: NDK instance
    init(pubkey: String, ndk: NDK) {
        self.pubkey = pubkey
        self.ndk = ndk
    }
    
    /// Load required session data
    /// - Parameter requirements: Data requirements from configuration
    func load(_ requirements: Set<SessionData>) async {
        for requirement in requirements {
            switch requirement {
            case .followList:
                await loadFollowList()
            case .webOfTrust:
                // WOT is lazy-loaded on first access
                break
            case .muteList, .relayList:
                // Future implementation
                break
            }
        }
        
        // Mark session as ready
        isReady = true
    }
    
    // MARK: - Follow List Management
    
    private func loadFollowList() async {
        guard let ndk = ndk else { return }
        
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts],
            limit: 1
        )
        
        // Create data source for continuous updates
        let dataSource = NDKDataSource<NDKEvent>(ndk: ndk, filter: filter)
        self.followListDataSource = dataSource
        
        // Process events as they arrive from the data source
        
        // Subscribe for updates
        for await event in dataSource.events {
            processFollowListEvent(event, fromCache: false)
        }
    }
    
    private func processFollowListEvent(_ event: NDKEvent, fromCache: Bool) {
        // Check for delta by event ID
        guard event.id != latestFollowListEventId else { return }
        
        let follows = extractFollows(from: event)
        
        // Update state based on whether this is initial load or update
        if latestFollowListEventId == nil {
            followListState = .ready(follows, fromCache: fromCache)
        } else {
            if case .ready(let current, _) = followListState {
                followListState = .updating(current: current, changes: follows)
            }
        }
        
        latestFollowListEventId = event.id
        
        // Trigger subscription updates if this is a change
        if !fromCache {
            Task {
                await triggerSubscriptionUpdates()
            }
        }
        
        // Update to ready state after processing
        followListState = .ready(follows, fromCache: fromCache)
    }
    
    private func extractFollows(from event: NDKEvent) -> Set<String> {
        var follows = Set<String>()
        
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "p" {
                follows.insert(tag[1])
            }
        }
        
        return follows
    }
    
    // MARK: - Web of Trust Management
    
    /// Get Web of Trust scores (lazy-loaded)
    public var webOfTrust: [String: Int] {
        if _wotScores == nil {
            loadWebOfTrust()
        }
        return _wotScores ?? [:]
    }
    
    private func loadWebOfTrust() {
        guard ndk != nil else { return }
        
        // Load from cache first
        if let cached = loadCachedWOT() {
            _wotScores = cached
        }
        
        // Start background sync
        Task {
            await syncWebOfTrust()
        }
        
        // Schedule periodic updates (24 hours)
        wotTimer?.invalidate()
        wotTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            Task {
                await self.syncWebOfTrust()
            }
        }
    }
    
    private func syncWebOfTrust() async {
        guard let ndk = ndk else { return }
        
        var scores: [String: Int] = [:]
        
        // Direct follows get maximum score
        for follow in followList {
            scores[follow] = Int.max
        }
        
        // Fetch follows of follows
        let filter = NDKFilter(
            authors: Array(followList),
            kinds: [EventKind.contacts]
        )
        
        // Use data source to fetch events
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 300 // 5 minute cache
        )
        
        // Collect events  
        let events = await dataSource.collect(timeout: 5.0)
        if !events.isEmpty {
            for event in events {
                let followsOfFollow = extractFollows(from: event)
                for pubkey in followsOfFollow {
                    if pubkey != self.pubkey { // Don't count self
                        scores[pubkey, default: 0] += 1
                    }
                }
            }
        }
        
        _wotScores = scores
        wotLastUpdated = Date()
        
        // Save to cache
        saveWOTToCache(scores)
    }
    
    /// Check if pubkey passes WOT filter
    /// - Parameters:
    ///   - pubkey: Public key to check
    ///   - config: WOT configuration
    /// - Returns: Whether pubkey passes filter
    public func passesWOTFilter(_ pubkey: String, config: WOTConfiguration) -> Bool {
        let score = webOfTrust[pubkey] ?? 0
        
        // Direct follows always pass if configured
        if config.includeDirectFollows && followList.contains(pubkey) {
            return true
        }
        
        return score >= config.minimumScore
    }
    
    // MARK: - Cache Management
    
    private func loadCachedWOT() -> [String: Int]? {
        // Implementation depends on cache adapter
        // For now, return nil (no cache)
        return nil
    }
    
    private func saveWOTToCache(_ scores: [String: Int]) {
        // Implementation depends on cache adapter
        // For now, no-op
    }
    
    // MARK: - Subscription Updates
    
    private func triggerSubscriptionUpdates() async {
        // Notify subscription manager about follow list change
        // This will be handled by SubscriptionSwapManager
        await SubscriptionSwapManager.shared.handleFollowListUpdate(self)
    }
    
    deinit {
        wotTimer?.invalidate()
        // DataSource cleanup handled automatically
    }
}