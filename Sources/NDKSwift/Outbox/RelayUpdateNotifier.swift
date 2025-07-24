import Foundation

/// Manages notifications for relay list updates and coordinates subscription updates
public actor RelayUpdateNotifier {
    private let ndk: NDK
    
    /// Tracks active subscriptions that use outbox model
    private var outboxSubscriptions: [String: OutboxSubscriptionInfo] = [:]
    
    /// Relay update events stream
    private let (relayUpdateStream, relayUpdateContinuation) = AsyncStream<RelayUpdateEvent>.makeStream()
    
    /// Public stream for monitoring relay updates
    public var relayUpdates: AsyncStream<RelayUpdateEvent> {
        relayUpdateStream
    }
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Register an outbox subscription for updates
    func registerSubscription(
        id: String,
        filter: NDKFilter,
        unknownAuthors: Set<String>
    ) {
        let info = OutboxSubscriptionInfo(
            id: id,
            originalFilter: filter,
            unknownAuthors: unknownAuthors,
            createdAt: Date()
        )
        outboxSubscriptions[id] = info
        
        NDKLogger.log(.debug, category: .outbox, "📝 Registered subscription '\(id)' for relay updates - tracking \(unknownAuthors.count) unknown authors")
    }
    
    /// Unregister a subscription
    func unregisterSubscription(id: String) {
        outboxSubscriptions.removeValue(forKey: id)
        NDKLogger.log(.debug, category: .outbox, "🗑️ Unregistered subscription '\(id)' from relay updates")
        
        // Periodic cleanup of old subscriptions
        cleanupOldSubscriptions()
    }
    
    /// Clean up subscriptions older than 24 hours
    private func cleanupOldSubscriptions() {
        let cutoffDate = Date().addingTimeInterval(-TimeConstants.day) // 24 hours
        let oldSubscriptions = outboxSubscriptions.filter { $0.value.createdAt < cutoffDate }
        
        if !oldSubscriptions.isEmpty {
            NDKLogger.log(.info, category: .outbox, "🧹 Cleaning up \(oldSubscriptions.count) old subscriptions")
            for (id, _) in oldSubscriptions {
                outboxSubscriptions.removeValue(forKey: id)
            }
        }
    }
    
    /// Notify about newly discovered relay information
    func notifyRelayDiscovery(for pubkey: String, relays: RelayDiscoveryInfo) async {
        NDKLogger.log(.info, category: .outbox, "🔔 Relay discovery notification for \(pubkey.prefix(8)): \(relays.readRelays.count) read, \(relays.writeRelays.count) write relays")
        
        // Find subscriptions that include this author
        let affectedSubscriptions = outboxSubscriptions.values.filter { subscription in
            subscription.unknownAuthors.contains(pubkey)
        }
        
        guard !affectedSubscriptions.isEmpty else {
            NDKLogger.log(.debug, category: .outbox, "📭 No active subscriptions interested in relay updates for \(pubkey.prefix(8))")
            return
        }
        
        NDKLogger.log(.info, category: .outbox, "📢 Found \(affectedSubscriptions.count) subscriptions to update for \(pubkey.prefix(8))")
        
        // Create update event
        let updateEvent = RelayUpdateEvent(
            pubkey: pubkey,
            relays: relays,
            affectedSubscriptionIds: affectedSubscriptions.map { $0.id }
        )
        
        // Notify listeners
        relayUpdateContinuation.yield(updateEvent)
        
        // Perform subscription updates
        for subscription in affectedSubscriptions {
            await updateSubscription(subscription, forAuthor: pubkey, relays: relays)
        }
    }
    
    /// Update a subscription with new relay information
    private func updateSubscription(
        _ subscriptionInfo: OutboxSubscriptionInfo,
        forAuthor pubkey: String,
        relays: RelayDiscoveryInfo
    ) async {
        let subscriptionId = subscriptionInfo.id
        
        NDKLogger.log(.info, category: .outbox, "🔄 Updating subscription '\(subscriptionId)' with new relays for \(pubkey.prefix(8))")
        
        // Create filter for just this author
        var authorFilter = subscriptionInfo.originalFilter
        authorFilter.authors = [pubkey]
        
        // Determine which relays to use (prefer read relays)
        let targetRelays = !relays.readRelays.isEmpty ? relays.readRelays : relays.writeRelays
        
        guard !targetRelays.isEmpty else {
            NDKLogger.log(.warning, category: .outbox, "⚠️ No relays found for \(pubkey.prefix(8)) - skipping update")
            return
        }
        
        // Create new subscription for this author on their specific relays
        let updateSubscriptionId = "\(subscriptionId)_update_\(pubkey.prefix(8))_\(Int(Date().timeIntervalSince1970))"
        
        NDKLogger.log(.debug, category: .outbox, "📡 Creating update subscription '\(updateSubscriptionId)' for \(targetRelays.count) relays")
        
        // Create the subscription through internal manager
        _ = await ndk.internalSubscriptionManager.createSubscription(
            id: updateSubscriptionId,
            filters: [authorFilter],
            relays: targetRelays
        )
        
        // Update the subscription info
        var updatedInfo = subscriptionInfo
        updatedInfo.unknownAuthors.remove(pubkey)
        updatedInfo.updateSubscriptionIds.insert(updateSubscriptionId)
        
        // Clean up old update subscription IDs (keep last 10)
        if updatedInfo.updateSubscriptionIds.count > 10 {
            let sortedIds = updatedInfo.updateSubscriptionIds.sorted()
            let idsToRemove = sortedIds.prefix(updatedInfo.updateSubscriptionIds.count - 10)
            updatedInfo.updateSubscriptionIds.subtract(idsToRemove)
        }
        
        outboxSubscriptions[subscriptionId] = updatedInfo
        
        NDKLogger.log(.info, category: .outbox, "✅ Subscription update complete - remaining unknown authors: \(updatedInfo.unknownAuthors.count)")
    }
    
    /// Get statistics about relay updates
    func getStats() -> RelayUpdateStats {
        let totalSubscriptions = outboxSubscriptions.count
        let totalUnknownAuthors = outboxSubscriptions.values.reduce(0) { $0 + $1.unknownAuthors.count }
        let totalUpdateSubscriptions = outboxSubscriptions.values.reduce(0) { $0 + $1.updateSubscriptionIds.count }
        
        return RelayUpdateStats(
            activeSubscriptions: totalSubscriptions,
            totalUnknownAuthors: totalUnknownAuthors,
            totalUpdateSubscriptions: totalUpdateSubscriptions
        )
    }
}

// MARK: - Supporting Types

/// Information about an outbox subscription
struct OutboxSubscriptionInfo {
    let id: String
    let originalFilter: NDKFilter
    var unknownAuthors: Set<String>
    let createdAt: Date
    var updateSubscriptionIds: Set<String> = []
}

/// Relay discovery information
public struct RelayDiscoveryInfo {
    public let readRelays: Set<RelayURL>
    public let writeRelays: Set<RelayURL>
    public let discoveredAt: Date
    
    public init(readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>, discoveredAt: Date = Date()) {
        self.readRelays = readRelays
        self.writeRelays = writeRelays
        self.discoveredAt = discoveredAt
    }
}

/// Event for relay updates
public struct RelayUpdateEvent {
    public let pubkey: String
    public let relays: RelayDiscoveryInfo
    public let affectedSubscriptionIds: [String]
    public let timestamp: Date = Date()
}

/// Statistics about relay updates
public struct RelayUpdateStats {
    public let activeSubscriptions: Int
    public let totalUnknownAuthors: Int
    public let totalUpdateSubscriptions: Int
}