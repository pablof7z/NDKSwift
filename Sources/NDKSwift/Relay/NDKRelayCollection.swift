import Foundation
import Combine

/// Observable collection of relay states for SwiftUI integration.
///
/// `NDKRelayCollection` provides a reactive view of relay connection states,
/// designed for SwiftUI integration. It observes the relay pool and publishes
/// updates when relay states change.
///
/// Example usage:
/// ```swift
/// struct RelayStatusView: View {
///     @ObservedObject var relayCollection: NDKRelayCollection
///     
///     var body: some View {
///         List(relayCollection.relays) { relay in
///             HStack {
///                 Text(relay.url)
///                 Spacer()
///                 Circle()
///                     .fill(relay.isConnected ? Color.green : Color.red)
///                     .frame(width: 10, height: 10)
///             }
///         }
///     }
/// }
/// ```
///
/// - Note: This is a lightweight wrapper that provides reactive updates without modifying core relay architecture
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
                // Extract error message if state is failed
                let errorMessage: String? = if case .failed(let message) = state.connectionState {
                    message
                } else {
                    nil
                }
                updateRelayInfo(url: url, state: state.connectionState, error: errorMessage)
            }
        }

        stateObservers[url] = task
    }

    private func updateRelayInfo(url: String, state: NDKRelayConnectionState, error: String? = nil) {
        if let index = relays.firstIndex(where: { $0.url == url }) {
            relays[index].state = state
            if state == .connected {
                relays[index].lastConnectedAt = Date()
                relays[index].lastError = nil // Clear error on successful connection
            } else if case .failed = state, let error = error {
                relays[index].lastError = error
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

    /// Monitor the relay pool for changes using event-driven approach
    private func startPoolObserver(_ ndk: NDK) async {
        poolObserverTask?.cancel()

        poolObserverTask = Task { @MainActor in
            // Get the relay changes stream from NDK
            let relayChangesStream = await ndk.relayChanges

            // Listen for relay pool changes
            for await change in relayChangesStream {
                switch change {
                case .relayAdded(let relay):
                    await handleRelayAdded(relay)

                case .relayRemoved(let url):
                    await handleRelayRemoved(url)

                case .relayConnected(_), .relayDisconnected(_):
                    // State changes are already handled by individual relay observers
                    // Pool events are primarily for external consumers like NostrManager
                    break
                }
            }
        }
    }

    /// Handle a relay being added to the pool
    private func handleRelayAdded(_ relay: NDKRelay) async {
        // Check if relay already exists to prevent duplicates from race conditions
        let alreadyExists = await MainActor.run {
            relays.contains { $0.url == relay.url }
        }

        guard !alreadyExists else {
            return
        }

        let state = await relay.connectionState
        let info = RelayInfo(relay: relay, state: state)

        await MainActor.run {
            relays.append(info)
            updateCounts()
        }

        // Start observing the new relay's state
        observeRelayState(relay)
    }

    /// Handle a relay being removed from the pool
    private func handleRelayRemoved(_ url: String) async {
        // Cancel observer for removed relay
        stateObservers[url]?.cancel()
        stateObservers.removeValue(forKey: url)

        await MainActor.run {
            relays.removeAll { $0.url == url }
            updateCounts()
        }
    }
}