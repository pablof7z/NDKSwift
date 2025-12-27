import Foundation

public extension NDK {
    /// Start an authenticated session with data requirements
    /// - Parameters:
    ///   - signer: The signer for authentication
    ///   - config: Session configuration
    /// - Returns: The session data manager
    @discardableResult
    func startSession(
        signer: NDKSigner,
        config: NDKSessionConfiguration = NDKSessionConfiguration()
    ) async throws -> NDKSessionData {
        NDKLogger.log(.info, category: .subscription, "🚀 [startSession] Starting session with strategy: \(config.preloadStrategy)")

        // Set the signer
        self.signer = signer

        // Get public key
        let pubkey = try await signer.pubkey
        NDKLogger.log(.info, category: .subscription, "🔑 [startSession] Got pubkey: \(pubkey.prefix(8))...")

        // Create session data
        let sessionData = NDKSessionData(pubkey: pubkey, ndk: self)

        // Store session data on NDK instance
        self.sessionData = sessionData
        NDKLogger.log(.info, category: .subscription, "💾 [startSession] Stored session data on NDK instance")

        // Load required data based on strategy
        switch config.preloadStrategy {
        case .blocking:
            // Wait for all data before returning
            NDKLogger.log(.info, category: .subscription, "⏳ [startSession] Loading data with blocking strategy")
            await sessionData.load(config.dataRequirements)

        case .progressive:
            // Load from cache immediately, then update from network in background
            NDKLogger.log(.info, category: .subscription, "⏳ [startSession] Loading data with progressive strategy")
            await sessionData.load(config.dataRequirements)

        case .lazy:
            // Don't load anything yet
            NDKLogger.log(.info, category: .subscription, "💤 [startSession] Lazy strategy - not loading data yet")
        }

        NDKLogger.log(.info, category: .subscription, "✅ [startSession] Session ready - follows: \(sessionData.followList.count)")
        NDKLogger.log(.info, category: .subscription, "🏁 [startSession] Returning sessionData to caller")

        return sessionData
    }

    /// Observe events with a reactive filter
    /// - Parameter reactiveFilter: Filter that updates with dependencies
    /// - Returns: AsyncStream of events
    func observe(_ reactiveFilter: ReactiveFilter) -> AsyncStream<NDKEvent> {
        NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Starting observe with dependencies: \(reactiveFilter.dependencies)")

        var continuation: AsyncStream<NDKEvent>.Continuation!
        let stream = AsyncStream<NDKEvent> { cont in
            continuation = cont
        }

        // Generate unique ID for tracking
        let subscriptionId = "reactive_\(IDGenerator.randomId(length: 8))"
        NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Created subscription ID: \(subscriptionId)")

        Task { [weak self] in
            await withTaskCancellationHandler {
                guard let self = self else {
                    continuation.finish()
                    return
                }
                // Use stored session data if available
                guard let sessionData = self.sessionData else {
                    NDKLogger.log(.error, category: .subscription, "❌ [ReactiveFilter] No session data available - did you call startSession()?")
                    continuation.finish()
                    return
                }

                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Using session data for pubkey: \(sessionData.pubkey.prefix(8))...")
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Session data state - follows: \(sessionData.followList.count), mutes: \(sessionData.muteList.count), contactListState: \(sessionData.contactListState)")

                // Ensure required dependencies are loaded
                var requiredData = reactiveFilter.dependencies
                requiredData.insert(.muteList) // Always load mute list for filtering

                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Ensuring dependencies are loaded: \(requiredData)")
                await sessionData.load(requiredData)

                // Log the state after loading
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] After load - follows: \(sessionData.followList.count), contactListState: \(sessionData.contactListState)")

                // Build initial filter
                let filter = reactiveFilter.builder(sessionData)
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Built filter with \(filter.authors?.count ?? 0) authors, kinds: \(filter.kinds ?? [])")

                // Create data source with meaningful subscription ID
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Creating NDKSubscription...")
                // Create a description based on dependencies
                let depDescription = reactiveFilter.dependencies.map { dep in
                    switch dep {
                    case .followList:
                        return "follows"
                    case .webOfTrust:
                        return "wot"
                    case .muteList:
                        return "mutes"
                    case .blockedRelays:
                        return "blocked"
                    case .relayList:
                        return "relays"
                    }
                }.sorted().joined(separator: "_")
                let subscriptionId = "reactive_\(depDescription)_\(sessionData.pubkey.prefix(8))"
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Creating NDKSubscription with subscriptionId: \(subscriptionId), filter: \(filter)")
                let dataSource = NDKSubscription<NDKEvent>(ndk: self, filter: filter, subscriptionId: subscriptionId)
                NDKLogger.log(.info, category: .subscription, "✅ [ReactiveFilter] NDKSubscription created successfully")

                // Register with swap manager
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Registering with SubscriptionSwapManager...")
                await SubscriptionSwapManager.shared.register(
                    id: subscriptionId,
                    dataSource: dataSource,
                    reactiveFilter: reactiveFilter,
                    sessionData: sessionData
                )
                NDKLogger.log(.info, category: .subscription, "✅ [ReactiveFilter] Registered with SubscriptionSwapManager")

                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Starting to iterate over dataSource.events...")
                var eventCount = 0

                // Stream events with mute and optional WOT filtering
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Starting to iterate dataSource.events...")
                for await batch in dataSource.events {
                    for event in batch {
                        eventCount += 1
                        NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Received event #\(eventCount) from \(event.pubkey.prefix(8))...")

                        // Skip muted pubkeys
                        if sessionData.isMuted(event.pubkey) {
                            NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Skipping muted pubkey: \(event.pubkey.prefix(8))...")
                            continue
                        }

                        // Apply WOT filter if configured
                        if let wotConfig = reactiveFilter.wotConfig {
                            guard sessionData.passesWOTFilter(
                                event.pubkey,
                                config: wotConfig
                            ) else {
                                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Event failed WOT filter")
                                continue
                            }
                        }

                        NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Yielding event to stream")
                        continuation.yield(event)
                    }
                }
                NDKLogger.log(.info, category: .subscription, "🔍 [ReactiveFilter] Finished iterating dataSource.events")

                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Event stream finished")
                continuation.finish()
            } onCancel: { [weak self] in
                _ = self // Capture self weakly but don't need to use it
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Subscription cancelled, unregistering...")
                Task {
                    await SubscriptionSwapManager.shared.unregister(id: subscriptionId)
                }
            }
        }

        return stream
    }
}
