import Foundation

extension NDK {
    /// Start an authenticated session with data requirements
    /// - Parameters:
    ///   - signer: The signer for authentication
    ///   - config: Session configuration
    /// - Returns: The session data manager
    @discardableResult
    public func startSession(
        signer: NDKSigner,
        config: NDKSessionConfiguration = NDKSessionConfiguration()
    ) async throws -> NDKSessionData {
        // Set the signer
        self.signer = signer
        
        // Get public key
        let pubkey = try await signer.pubkey
        
        // Create session data
        let sessionData = NDKSessionData(pubkey: pubkey, ndk: self)
        
        // Store session data on NDK instance
        self.sessionData = sessionData
        
        // Load required data based on strategy
        switch config.preloadStrategy {
        case .blocking:
            // Wait for all data before returning
            await sessionData.load(config.dataRequirements)
            
        case .progressive:
            // Start loading in background
            Task {
                await sessionData.load(config.dataRequirements)
            }
            
        case .lazy:
            // Don't load anything yet
            break
        }
        
        return sessionData
    }
    
    /// Observe events with a reactive filter
    /// - Parameter reactiveFilter: Filter that updates with dependencies
    /// - Returns: AsyncStream of events
    public func observe(_ reactiveFilter: ReactiveFilter) -> AsyncStream<NDKEvent> {
        NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Starting observe with dependencies: \(reactiveFilter.dependencies)")
        
        var continuation: AsyncStream<NDKEvent>.Continuation!
        let stream = AsyncStream<NDKEvent> { cont in
            continuation = cont
        }
        
        // Generate unique ID for tracking
        let subscriptionId = UUID().uuidString
        NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Created subscription ID: \(subscriptionId)")
        
        Task {
            await withTaskCancellationHandler {
                // Use stored session data if available
                guard let sessionData = self.sessionData else {
                    NDKLogger.log(.error, category: .subscription, "❌ [ReactiveFilter] No session data available - did you call startSession()?")
                    continuation.finish()
                    return
                }
                
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Using session data for pubkey: \(sessionData.pubkey.prefix(8))...")
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Session data state - follows: \(sessionData.followList.count), mutes: \(sessionData.muteList.count)")
                
                // Ensure required dependencies are loaded
                var requiredData = reactiveFilter.dependencies
                requiredData.insert(.muteList)  // Always load mute list for filtering
                
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Ensuring dependencies are loaded: \(requiredData)")
                await sessionData.load(requiredData)
                
                // Build initial filter
                let filter = reactiveFilter.builder(sessionData)
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Built filter with \(filter.authors?.count ?? 0) authors, kinds: \(filter.kinds ?? [])")
                
                // Create data source with meaningful subscription ID
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Creating NDKDataSource...")
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
                let dataSource = NDKDataSource<NDKEvent>(ndk: self, filter: filter, subscriptionId: subscriptionId)
                
                // Register with swap manager
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Registering with SubscriptionSwapManager...")
                await SubscriptionSwapManager.shared.register(
                    id: subscriptionId,
                    dataSource: dataSource,
                    reactiveFilter: reactiveFilter,
                    sessionData: sessionData
                )
                
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Starting to iterate over dataSource.events...")
                var eventCount = 0
                
                // Stream events with mute and optional WOT filtering
                for await event in dataSource.events {
                    eventCount += 1
                    NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Received event #\(eventCount) from \(event.pubkey.prefix(8))...")
                    
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
                    
                    NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Yielding event to stream")
                    continuation.yield(event)
                }
                
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Event stream finished")
                continuation.finish()
            } onCancel: {
                NDKLogger.log(.debug, category: .subscription, "🔍 [ReactiveFilter] Subscription cancelled, unregistering...")
                Task {
                    await SubscriptionSwapManager.shared.unregister(id: subscriptionId)
                }
            }
        }
        
        return stream
    }
}