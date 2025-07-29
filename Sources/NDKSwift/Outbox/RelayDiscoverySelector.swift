import Foundation

/// Strategy for selecting which relays to connect to when relay information is discovered
public protocol RelayDiscoverySelectionStrategy {
    /// Select which relays to connect to from discovered relay information
    /// - Parameters:
    ///   - discoveredRelays: The relays that were discovered for specific authors
    ///   - authors: The authors whose relay information was discovered
    ///   - existingRelays: Relays already being used for the subscription
    ///   - connectedRelays: Currently connected relays
    ///   - maxRelays: Maximum number of relays to select (default: 2)
    /// - Returns: Set of relay URLs that should be connected to
    func selectRelaysToConnect(
        discoveredRelays: Set<RelayURL>,
        for authors: Set<String>,
        existingRelays: Set<RelayURL>,
        connectedRelays: Set<RelayURL>,
        maxRelays: Int
    ) async -> Set<RelayURL>
}

/// Default implementation that prioritizes already-connected relays and overlapping relays
struct DefaultRelayDiscoverySelector: RelayDiscoverySelectionStrategy {
    private let tracker: NDKOutboxTracker
    private let ranker: NDKRelayRanker?
    
    init(tracker: NDKOutboxTracker, ranker: NDKRelayRanker? = nil) {
        self.tracker = tracker
        self.ranker = ranker
    }
    
    func selectRelaysToConnect(
        discoveredRelays: Set<RelayURL>,
        for authors: Set<String>,
        existingRelays: Set<RelayURL>,
        connectedRelays: Set<RelayURL>,
        maxRelays: Int = 2
    ) async -> Set<RelayURL> {
        // If we already have enough relays, don't add more
        if existingRelays.count >= maxRelays {
            return []
        }
        
        // Calculate how many more relays we need
        let relaysNeeded = maxRelays - existingRelays.count
        guard relaysNeeded > 0 else { return [] }
        
        // Filter out relays we're already using
        let candidateRelays = discoveredRelays.subtracting(existingRelays)
        guard !candidateRelays.isEmpty else { return [] }
        
        // Prioritize relays that are already connected
        let connectedCandidates = candidateRelays.intersection(connectedRelays)
        
        // If we have enough connected candidates, use them
        if connectedCandidates.count >= relaysNeeded {
            return Set(Array(connectedCandidates).prefix(relaysNeeded))
        }
        
        // Start with all connected candidates
        var selectedRelays = connectedCandidates
        
        // If we need more relays, analyze the remaining candidates
        if selectedRelays.count < relaysNeeded {
            let remainingCandidates = candidateRelays.subtracting(connectedCandidates)
            
            // Score remaining candidates by how many authors they serve
            var relayScores: [(relay: RelayURL, score: Int)] = []
            
            for relay in remainingCandidates {
                var score = 0
                
                // Count how many of our authors use this relay
                for author in authors {
                    if let relayInfo = await tracker.getRelaysSyncFor(pubkey: author) {
                        let allRelays = relayInfo.readRelays.union(relayInfo.writeRelays)
                        if allRelays.contains(where: { $0.url == relay }) {
                            score += 1
                        }
                    }
                }
                
                relayScores.append((relay: relay, score: score))
            }
            
            // Sort by score (descending) and take what we need
            relayScores.sort { $0.score > $1.score }
            let additionalRelaysNeeded = relaysNeeded - selectedRelays.count
            let topRelays = relayScores.prefix(additionalRelaysNeeded).map { $0.relay }
            selectedRelays.formUnion(topRelays)
        }
        
        return selectedRelays
    }
}

/// Overlap-optimized selector that prioritizes relays serving multiple authors
struct OverlapOptimizedRelaySelector: RelayDiscoverySelectionStrategy {
    private let tracker: NDKOutboxTracker
    
    init(tracker: NDKOutboxTracker) {
        self.tracker = tracker
    }
    
    func selectRelaysToConnect(
        discoveredRelays: Set<RelayURL>,
        for authors: Set<String>,
        existingRelays: Set<RelayURL>,
        connectedRelays: Set<RelayURL>,
        maxRelays: Int = 2
    ) async -> Set<RelayURL> {
        let correlationId = UUID().uuidString.prefix(8)
        
        NDKLogger.log(.debug, category: .outbox, 
                     "🔍 [OverlapOptimized] Starting relay selection - discovered: \(discoveredRelays.count), existing: \(existingRelays.count), needed: \(maxRelays)",
                     correlationId: String(correlationId))
        
        // If we already have enough relays, don't add more
        if existingRelays.count >= maxRelays {
            NDKLogger.log(.debug, category: .outbox,
                         "✅ [OverlapOptimized] Already have \(existingRelays.count) relays (max: \(maxRelays)), no additional relays needed",
                         correlationId: String(correlationId))
            return []
        }
        
        let relaysNeeded = maxRelays - existingRelays.count
        guard relaysNeeded > 0 else { return [] }
        
        // Filter out relays we're already using
        let candidateRelays = discoveredRelays.subtracting(existingRelays)
        guard !candidateRelays.isEmpty else {
            NDKLogger.log(.debug, category: .outbox,
                         "📊 [OverlapOptimized] No new candidate relays after filtering existing ones",
                         correlationId: String(correlationId))
            return []
        }
        
        NDKLogger.log(.debug, category: .outbox,
                     "📊 [OverlapOptimized] Need \(relaysNeeded) more relays, have \(candidateRelays.count) candidates",
                     correlationId: String(correlationId))
        
        // Build a map of relay -> Set of authors it serves
        var relayToAuthors: [RelayURL: Set<String>] = [:]
        
        for author in authors {
            if let relayInfo = await tracker.getRelaysSyncFor(pubkey: author) {
                let allRelays = relayInfo.readRelays.union(relayInfo.writeRelays)
                for relay in allRelays {
                    if candidateRelays.contains(relay.url) {
                        relayToAuthors[relay.url, default: []].insert(author)
                    }
                }
            }
        }
        
        NDKLogger.log(.debug, category: .outbox,
                     "📊 [OverlapOptimized] Relay coverage analysis complete - \(relayToAuthors.count) relays serve our authors",
                     correlationId: String(correlationId))
        
        // Log relay coverage details
        for (relay, authorsServed) in relayToAuthors.prefix(5) {
            let isConnected = connectedRelays.contains(relay)
            NDKLogger.log(.trace, category: .outbox,
                         "   • \(relay): serves \(authorsServed.count) authors \(isConnected ? "[CONNECTED]" : "[NOT CONNECTED]")",
                         correlationId: String(correlationId))
        }
        
        // Sort relays by:
        // 1. Number of authors they serve (more is better)
        // 2. Whether they're already connected (connected is better)
        let sortedRelays = relayToAuthors.sorted { (lhs, rhs) in
            let lhsCount = lhs.value.count
            let rhsCount = rhs.value.count
            
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            
            // If equal author count, prefer connected relays
            let lhsConnected = connectedRelays.contains(lhs.key)
            let rhsConnected = connectedRelays.contains(rhs.key)
            
            if lhsConnected != rhsConnected {
                return lhsConnected
            }
            
            // Otherwise, maintain stable sort
            return lhs.key < rhs.key
        }
        
        // Select top relays up to the needed count
        let selectedRelays = sortedRelays.prefix(relaysNeeded).map { $0.key }
        let selectedSet = Set(selectedRelays)
        
        NDKLogger.log(.info, category: .outbox,
                     "✅ [OverlapOptimized] Selected \(selectedSet.count) relays: \(selectedSet)",
                     correlationId: String(correlationId))
        
        // Log why these relays were chosen
        for relay in selectedSet {
            let authorCount = relayToAuthors[relay]?.count ?? 0
            let isConnected = connectedRelays.contains(relay)
            NDKLogger.log(.debug, category: .outbox,
                         "   ✓ \(relay): serves \(authorCount) authors, connected: \(isConnected)",
                         correlationId: String(correlationId))
        }
        
        return selectedSet
    }
}