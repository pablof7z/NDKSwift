import Foundation

/// Thread-safe actor that manages a pool of relay connections
public actor NDKPool {
    private weak var ndk: NDK?
    private var relayMap: [String: NDKRelay] = [:]
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    // MARK: - Relay Management
    
    /// Add a relay to the pool
    @discardableResult
    public func addRelay(_ url: RelayURL) async -> NDKRelay {
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        
        // Check if already exists
        if let existing = relayMap[normalizedUrl] {
            return existing
        }
        
        // Create new relay
        let relay = NDKRelay(url: normalizedUrl)
        if let ndk = ndk {
            relay.setNDK(ndk)
        }
        relayMap[normalizedUrl] = relay
        
        // Set up connection state observer to publish queued events
        await relay.observeConnectionState { [weak self, weak relay] state in
            guard let self = self, let relay = relay else { return }
            if case .connected = state {
                Task {
                    await self.handleRelayConnected(relay)
                }
            }
        }
        
        return relay
    }
    
    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) async {
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        if let relay = relayMap.removeValue(forKey: normalizedUrl) {
            await relay.disconnect()
        }
    }
    
    /// Get all relays
    public var relays: [NDKRelay] {
        Array(relayMap.values)
    }
    
    /// Get connected relays
    public func connectedRelays() async -> [NDKRelay] {
        await relays.asyncFilter { relay in
            await relay.connectionState == .connected
        }
    }
    
    /// Get a specific relay by URL
    public func getRelay(for url: RelayURL) async -> NDKRelay? {
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        return relayMap[normalizedUrl]
    }
    
    /// Get a snapshot of all relay states for quick status checks
    /// Returns a dictionary mapping relay URLs to their current connection states
    public func getRelayStateSnapshot() async -> [RelayURL: NDKRelayConnectionState] {
        var snapshot: [RelayURL: NDKRelayConnectionState] = [:]
        for relay in relays {
            snapshot[relay.url] = await relay.connectionState
        }
        return snapshot
    }
    
    /// Get connection summary (connected count, total count)
    public func getConnectionSummary() async -> (connected: Int, total: Int) {
        let states = await getRelayStateSnapshot()
        let connected = states.values.filter { $0 == .connected }.count
        return (connected: connected, total: states.count)
    }
    
    /// Connect to all relays
    public func connectAll() async {
        print("[NDKPool] Connecting to all relays...")
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        try await relay.connect()
                    } catch {
                        print("[NDKPool] Failed to connect to \(relay.url): \(error)")
                    }
                }
            }
        }
        print("[NDKPool] connectAll() completed")
    }
    
    /// Disconnect from all relays
    public func disconnectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    await relay.disconnect()
                }
            }
        }
    }
    
    /// Publish an event to all connected relays
    public func publishEvent(_ event: NDKEvent) async -> Set<NDKRelay> {
        var publishedRelays = Set<NDKRelay>()
        
        await withTaskGroup(of: (NDKRelay, Bool).self) { group in
            for relay in await connectedRelays() {
                group.addTask {
                    do {
                        let result = try await relay.publish(event)
                        return (relay, result.success)
                    } catch {
                        print("[NDKPool] Failed to publish to \(relay.url): \(error)")
                        return (relay, false)
                    }
                }
            }
            
            for await (relay, success) in group {
                if success {
                    publishedRelays.insert(relay)
                }
            }
        }
        
        return publishedRelays
    }
    
    // MARK: - Private Helpers
    
    private func handleRelayConnected(_ relay: NDKRelay) async {
        guard let ndk = ndk else { return }
        await ndk.eventManager.publishQueuedEvents(for: relay)
    }
}

// Helper extension for async filter
extension Array {
    func asyncFilter(_ isIncluded: (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
        }
        return result
    }
}