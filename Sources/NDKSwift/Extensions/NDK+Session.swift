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
        
        // Store session data in a global place if needed
        // For now, the session data is returned to the caller
        
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
        var continuation: AsyncStream<NDKEvent>.Continuation!
        let stream = AsyncStream<NDKEvent> { cont in
            continuation = cont
        }
        
        // Generate unique ID for tracking
        let subscriptionId = UUID().uuidString
        
        Task {
            await withTaskCancellationHandler {
                // Get current session data from signer
                guard let signer = self.signer else {
                    continuation.finish()
                    return
                }
                
                let pubkey = try? await signer.pubkey
                guard let pubkey = pubkey else {
                    continuation.finish()
                    return
                }
                
                // Create session data
                let sessionData = NDKSessionData(pubkey: pubkey, ndk: self)
                await sessionData.load([.followList])
                
                // Build initial filter
                let filter = reactiveFilter.builder(sessionData)
                
                // Create data source
                let dataSource = NDKDataSource<NDKEvent>(ndk: self, filter: filter)
                
                // Register with swap manager
                await SubscriptionSwapManager.shared.register(
                    id: subscriptionId,
                    dataSource: dataSource,
                    reactiveFilter: reactiveFilter,
                    sessionData: sessionData
                )
                
                // Handle cleanup
                // Cleanup will be handled by cancellation handler
                
                // Stream events with optional WOT filtering
                for await event in dataSource.events {
                    // Apply WOT filter if configured
                    if let wotConfig = reactiveFilter.wotConfig {
                        guard sessionData.passesWOTFilter(
                            event.pubkey,
                            config: wotConfig
                        ) else {
                            continue
                        }
                    }
                    
                    continuation.yield(event)
                }
                
                continuation.finish()
            } onCancel: {
                Task {
                    await SubscriptionSwapManager.shared.unregister(id: subscriptionId)
                }
            }
        }
        
        return stream
    }
    
    /// Fetch events with a reactive filter (one-time)
    /// - Parameter reactiveFilter: Filter that uses current dependencies
    /// - Returns: Array of events
    public func fetchEvents(_ reactiveFilter: ReactiveFilter) async throws -> [NDKEvent] {
        // Get current session data from signer
        guard let signer = self.signer else {
            return []
        }
        
        let pubkey = try await signer.pubkey
        
        // Create session data
        let sessionData = NDKSessionData(pubkey: pubkey, ndk: self)
        await sessionData.load([.followList])
        
        // Build filter with current data
        let filter = reactiveFilter.builder(sessionData)
        
        // Use data source to fetch events with proper cache handling
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: self,
            filter: filter,
            maxAge: 300, // 5 minute cache
            cachePolicy: .cacheWithNetwork
        )
        
        // Collect events with timeout
        let events = await dataSource.collect(timeout: 5.0)
        
        // Apply WOT filter if configured
        if let wotConfig = reactiveFilter.wotConfig {
            return events.filter { event in
                sessionData.passesWOTFilter(event.pubkey, config: wotConfig)
            }
        }
        
        return events
    }
}