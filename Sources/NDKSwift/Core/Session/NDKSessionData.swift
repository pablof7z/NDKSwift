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
    
    /// Mute list state
    public private(set) var muteListState: DataState<Set<String>> = .loading
    
    /// Computed mute list (muted pubkeys)
    public var muteList: Set<String> {
        muteListState.data ?? []
    }
    
    /// Latest mute list event ID for delta detection
    private var latestMuteListEventId: String?
    
    /// Blocked relays state
    public private(set) var blockedRelaysState: DataState<Set<String>> = .loading
    
    /// Computed blocked relays
    public var blockedRelays: Set<String> {
        blockedRelaysState.data ?? []
    }
    
    /// Latest blocked relays event ID for delta detection
    private var latestBlockedRelaysEventId: String?
    
    /// Lazy-loaded Web of Trust scores
    private var _wotScores: [String: Int]?
    private var wotLastUpdated: Date?
    private var wotTimer: Timer?
    
    /// Whether session is ready (all required data loaded)
    public private(set) var isReady = false
    
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
        // Create a combined filter for all lists to minimize subscriptions
        var kinds = Set<Int>()
        var needsFollowList = false
        var needsMuteList = false
        var needsBlockedRelays = false
        
        for requirement in requirements {
            switch requirement {
            case .followList:
                // Only load if not already available
                if !followListState.isAvailable {
                    kinds.insert(EventKind.contacts)
                    needsFollowList = true
                }
            case .muteList:
                // Only load if not already available
                if !muteListState.isAvailable {
                    kinds.insert(EventKind.muteList)
                    needsMuteList = true
                }
            case .blockedRelays:
                // Only load if not already available
                if !blockedRelaysState.isAvailable {
                    kinds.insert(EventKind.blockedRelays)
                    needsBlockedRelays = true
                }
            case .webOfTrust:
                // WOT is lazy-loaded on first access
                // But we need follow list first
                if !followListState.isAvailable {
                    kinds.insert(EventKind.contacts)
                    needsFollowList = true
                }
            case .relayList:
                kinds.insert(EventKind.relayList)
            }
        }
        
        if !kinds.isEmpty {
            await loadLists(kinds: kinds, 
                          needsFollowList: needsFollowList,
                          needsMuteList: needsMuteList, 
                          needsBlockedRelays: needsBlockedRelays)
        }
        
        // Mark session as ready
        isReady = true
    }
    
    // MARK: - List Management
    
    /// Active data source for all lists
    private var listsDataSource: NDKDataSource<NDKEvent>?
    
    private func loadLists(kinds: Set<Int>, needsFollowList: Bool, needsMuteList: Bool, needsBlockedRelays: Bool) async {
        guard let ndk = ndk else { return }
        
        // If we already have an active data source loading lists, skip
        if listsDataSource != nil {
            NDKLogger.log(.debug, category: .subscription, "⏭️ Lists data source already active, skipping duplicate creation")
            return
        }
        
        // First, check cache for existing events to optimize the filter
        var latestTimestamps: [Int: Timestamp] = [:]
        
        // Check for each kind we need
        for kind in kinds {
            let cacheFilter = NDKFilter(
                authors: [pubkey],
                kinds: [kind],
                limit: 1
            )
            
            // Get the latest event from cache
            if let cachedEvents = try? await ndk.cache.queryEvents(cacheFilter),
               let cachedEvent = cachedEvents.first {
                latestTimestamps[kind] = cachedEvent.createdAt
                
                // Process the cached event immediately
                switch cachedEvent.kind {
                case EventKind.contacts where needsFollowList:
                    NDKLogger.log(.info, category: .subscription, "📦 Processing cached follow list event - id: \(cachedEvent.id), timestamp: \(cachedEvent.createdAt)")
                    processFollowListEvent(cachedEvent, fromCache: true)
                case EventKind.muteList where needsMuteList:
                    NDKLogger.log(.info, category: .subscription, "📦 Processing cached mute list event - id: \(cachedEvent.id), timestamp: \(cachedEvent.createdAt)")
                    processMuteListEvent(cachedEvent, fromCache: true)
                case EventKind.blockedRelays where needsBlockedRelays:
                    NDKLogger.log(.info, category: .subscription, "📦 Processing cached blocked relays event - id: \(cachedEvent.id), timestamp: \(cachedEvent.createdAt)")
                    processBlockedRelaysEvent(cachedEvent, fromCache: true)
                default:
                    break
                }
            }
        }
        
        // Find the newest timestamp among all kinds (or nil if no cached events)
        let newestTimestamp = latestTimestamps.values.max()
        
        // Create filter with 'since' optimization if we have cached events
        var filter = NDKFilter(
            authors: [pubkey],
            kinds: Array(kinds),
            limit: kinds.count  // We want the latest of each kind
        )
        
        // If we have cached events, only fetch newer ones
        if let timestamp = newestTimestamp {
            // Add 1 second to avoid re-fetching the same events
            filter.since = timestamp + 1
            NDKLogger.log(.debug, category: .subscription, "🎯 Optimizing session data fetch - only fetching events newer than \(timestamp)")
        }
        
        // Create data source for continuous updates with meaningful subscription ID
        let subscriptionId = "session_lists_\(pubkey.prefix(8))"
        let dataSource = NDKDataSource<NDKEvent>(ndk: ndk, filter: filter, subscriptionId: subscriptionId)
        self.listsDataSource = dataSource
        
        // Start processing events in background - don't block
        Task {
            // Process events as they arrive from the data source
            for await event in dataSource.events {
                switch event.kind {
                case EventKind.contacts where needsFollowList:
                    processFollowListEvent(event, fromCache: false)
                case EventKind.muteList where needsMuteList:
                    processMuteListEvent(event, fromCache: false)
                case EventKind.blockedRelays where needsBlockedRelays:
                    processBlockedRelaysEvent(event, fromCache: false)
                default:
                    break
                }
            }
        }
    }
    
    private func processFollowListEvent(_ event: NDKEvent, fromCache: Bool) {
        // Check for delta by event ID
        guard event.id != latestFollowListEventId else {
            NDKLogger.log(.debug, category: .subscription, "⏭️ Skipping duplicate follow list event - id: \(event.id)")
            return
        }
        
        let follows = extractFollows(from: event)
        
        // Update state based on whether this is initial load or update
        if latestFollowListEventId == nil {
            NDKLogger.log(.info, category: .subscription, "✅ Follow list loaded - \(follows.count) follows, fromCache: \(fromCache)")
            followListState = .ready(follows, fromCache: fromCache)
        } else {
            if case .ready(let current, _) = followListState {
                NDKLogger.log(.info, category: .subscription, "🔄 Follow list updating - from \(current.count) to \(follows.count) follows")
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
    
    // MARK: - Mute List Management
    
    private func processMuteListEvent(_ event: NDKEvent, fromCache: Bool) {
        // Check for delta by event ID
        guard event.id != latestMuteListEventId else { return }
        
        let mutedPubkeys = extractMutedPubkeys(from: event)
        
        // Update state based on whether this is initial load or update
        if latestMuteListEventId == nil {
            muteListState = .ready(mutedPubkeys, fromCache: fromCache)
        } else {
            if case .ready(let current, _) = muteListState {
                muteListState = .updating(current: current, changes: mutedPubkeys)
            }
        }
        
        latestMuteListEventId = event.id
        
        // Update to ready state after processing
        muteListState = .ready(mutedPubkeys, fromCache: fromCache)
    }
    
    private func extractMutedPubkeys(from event: NDKEvent) -> Set<String> {
        // Use NDKList to parse the mute list
        let muteList = NDKList.from(event)
        return Set(muteList.userPubkeys)
    }
    
    // MARK: - Blocked Relays Management
    
    private func processBlockedRelaysEvent(_ event: NDKEvent, fromCache: Bool) {
        // Check for delta by event ID
        guard event.id != latestBlockedRelaysEventId else { return }
        
        let blockedUrls = extractBlockedRelays(from: event)
        
        // Update state based on whether this is initial load or update
        if latestBlockedRelaysEventId == nil {
            blockedRelaysState = .ready(blockedUrls, fromCache: fromCache)
        } else {
            if case .ready(let current, _) = blockedRelaysState {
                blockedRelaysState = .updating(current: current, changes: blockedUrls)
            }
        }
        
        latestBlockedRelaysEventId = event.id
        
        // Update to ready state after processing
        blockedRelaysState = .ready(blockedUrls, fromCache: fromCache)
    }
    
    private func extractBlockedRelays(from event: NDKEvent) -> Set<String> {
        // Use NDKList to parse the blocked relays list
        let blockedList = NDKList.from(event)
        // Normalize relay URLs for consistent comparison
        let normalizedUrls = blockedList.urls.compactMap { url in
            URLNormalizer.tryNormalizeRelayUrl(url)
        }
        return Set(normalizedUrls)
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
        let subscriptionId = "session_wot_\(pubkey.prefix(8))"
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 300, // 5 minute cache
            subscriptionId: subscriptionId
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
    
    // MARK: - Efficient Lookups (O(1))
    
    /// Check if a pubkey is muted
    /// - Parameter pubkey: Public key to check
    /// - Returns: Whether the pubkey is muted
    public func isMuted(_ pubkey: String) -> Bool {
        return muteList.contains(pubkey)
    }
    
    /// Check if a relay is blocked
    /// - Parameter relayUrl: Relay URL to check (will be normalized)
    /// - Returns: Whether the relay is blocked
    public func isRelayBlocked(_ relayUrl: String) -> Bool {
        // Normalize the URL before checking
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relayUrl) ?? relayUrl
        return blockedRelays.contains(normalizedUrl)
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