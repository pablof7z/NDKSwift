import Foundation
import Combine

/// Observable collection of relay states for SwiftUI integration
/// This is a lightweight wrapper that provides reactive updates without modifying core relay architecture
@MainActor
public final class NDKRelayCollection: ObservableObject {
    /// Relay information with observable state
    public struct RelayInfo: Identifiable {
        public let id: String
        public let url: String
        public var state: NDKRelayConnectionState
        public var isConnected: Bool { state == .connected }
        public var lastConnectedAt: Date?
        public var lastError: String?
        
        init(relay: NDKRelay, state: NDKRelayConnectionState) {
            self.id = relay.url
            self.url = relay.url
            self.state = state
        }
    }
    
    @Published public private(set) var relays: [RelayInfo] = []
    @Published public private(set) var connectedCount: Int = 0
    @Published public private(set) var totalCount: Int = 0
    
    private weak var ndk: NDK?
    private var stateObservers: [String: Task<Void, Never>] = [:]
    private var poolObserverTask: Task<Void, Never>?
    
    public init(ndk: NDK? = nil) {
        self.ndk = ndk
        if let ndk = ndk {
            Task {
                await observeRelays(ndk)
                await startPoolObserver(ndk)
            }
        }
    }
    
    deinit {
        // Cancel all tasks immediately without dispatching
        for task in stateObservers.values {
            task.cancel()
        }
        poolObserverTask?.cancel()
    }
    
    /// Update the NDK instance and start observing
    public func setNDK(_ ndk: NDK) {
        self.ndk = ndk
        Task {
            await observeRelays(ndk)
            await startPoolObserver(ndk)
        }
    }
    
    /// Manually refresh relay states
    public func refresh() async {
        guard let ndk = ndk else { return }
        await updateRelayStates(ndk)
    }
    
    private func observeRelays(_ ndk: NDK) async {
        // Cancel existing observers
        cancelAllObservers()
        
        // Get all relays and their current states
        let allRelays = await ndk.relays
        let stateSnapshot = await ndk.pool.getRelayStateSnapshot()
        
        // Quick initial state population using snapshot
        var initialRelays: [RelayInfo] = []
        for relay in allRelays {
            let state = stateSnapshot[relay.url] ?? .disconnected
            var info = RelayInfo(relay: relay, state: state)
            
            // Preserve existing metadata if we're refreshing
            if let existing = relays.first(where: { $0.url == relay.url }) {
                info.lastConnectedAt = existing.lastConnectedAt
                info.lastError = existing.lastError
            }
            
            initialRelays.append(info)
        }
        
        // Update UI immediately with snapshot data
        await MainActor.run {
            self.relays = initialRelays
            updateCounts()
        }
        
        // Set up state observers for each relay
        for relay in allRelays {
            observeRelayState(relay)
        }
    }
    
    private func observeRelayState(_ relay: NDKRelay) {
        let url = relay.url
        
        // Cancel existing observer
        stateObservers[url]?.cancel()
        
        // Create observer task
        let task = Task { @MainActor in
            for await state in relay.stateStream {
                updateRelayInfo(url: url, state: state.connectionState)
            }
        }
        
        stateObservers[url] = task
    }
    
    private func updateRelayInfo(url: String, state: NDKRelayConnectionState) {
        if let index = relays.firstIndex(where: { $0.url == url }) {
            relays[index].state = state
            if state == .connected {
                relays[index].lastConnectedAt = Date()
            }
        }
        updateCounts()
    }
    
    private func updateRelayStates(_ ndk: NDK) async {
        let allRelays = await ndk.relays
        var newRelays: [RelayInfo] = []
        
        for relay in allRelays {
            let state = await relay.connectionState
            var info = RelayInfo(relay: relay, state: state)
            
            // Preserve existing metadata
            if let existing = relays.first(where: { $0.url == relay.url }) {
                info.lastConnectedAt = existing.lastConnectedAt
                info.lastError = existing.lastError
            }
            
            newRelays.append(info)
        }
        
        await MainActor.run {
            self.relays = newRelays
            updateCounts()
        }
    }
    
    private func updateCounts() {
        connectedCount = relays.filter { $0.isConnected }.count
        totalCount = relays.count
    }
    
    private func cancelAllObservers() {
        for task in stateObservers.values {
            task.cancel()
        }
        stateObservers.removeAll()
        poolObserverTask?.cancel()
        poolObserverTask = nil
    }
    
    /// Add a relay and start observing it
    public func addRelay(_ url: String) async {
        guard let ndk = ndk else { return }
        let relay = await ndk.addRelay(url)
        
        // Add to our collection
        let state = await relay.connectionState
        let info = RelayInfo(relay: relay, state: state)
        
        await MainActor.run {
            relays.append(info)
            updateCounts()
        }
        
        // Start observing
        observeRelayState(relay)
        
        // Connect
        try? await relay.connect()
    }
    
    /// Remove a relay
    public func removeRelay(_ url: String) async {
        guard let ndk = ndk else { return }
        
        // Cancel observer
        stateObservers[url]?.cancel()
        stateObservers.removeValue(forKey: url)
        
        // Remove from collection
        await MainActor.run {
            relays.removeAll { $0.url == url }
            updateCounts()
        }
        
        // Remove from NDK
        await ndk.removeRelay(url)
    }
    
    /// Monitor the relay pool for changes
    private func startPoolObserver(_ ndk: NDK) async {
        poolObserverTask?.cancel()
        
        poolObserverTask = Task { @MainActor in
            // Keep track of known relay URLs
            var knownRelayUrls = Set(relays.map { $0.url })
            
            // Check for changes periodically
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    let currentRelays = await ndk.relays
                    let currentUrls = Set(currentRelays.map { $0.url })
                    
                    // Check for added relays
                    let addedUrls = currentUrls.subtracting(knownRelayUrls)
                    for url in addedUrls {
                        if let relay = currentRelays.first(where: { $0.url == url }) {
                            let state = await relay.connectionState
                            let info = RelayInfo(relay: relay, state: state)
                            relays.append(info)
                            observeRelayState(relay)
                        }
                    }
                    
                    // Check for removed relays
                    let removedUrls = knownRelayUrls.subtracting(currentUrls)
                    for url in removedUrls {
                        stateObservers[url]?.cancel()
                        stateObservers.removeValue(forKey: url)
                        relays.removeAll { $0.url == url }
                    }
                    
                    // Update counts if there were changes
                    if !addedUrls.isEmpty || !removedUrls.isEmpty {
                        updateCounts()
                        knownRelayUrls = currentUrls
                    }
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }
}