import Foundation
import NDKSwift

@MainActor
class RelayManager: ObservableObject {
    struct RelayInfo: Identifiable, Codable {
        let id = UUID()
        var url: String
        var isActive: Bool = true
        var isConnected: Bool = false
        var lastSeen: Date?
        
        enum CodingKeys: String, CodingKey {
            case url, isActive
        }
    }
    
    @Published var relays: [RelayInfo] = []
    private var ndk: NDK?
    private var stateObserverTasks: [String: Task<Void, Never>] = [:]
    
    private let defaultRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.snort.social",
        "wss://relay.nostr.band",
        "wss://nostr.wine",
        "wss://relay.primal.net"
    ]
    
    init() {
        loadRelays()
    }
    
    deinit {
        // Cancel all observer tasks
        for task in stateObserverTasks.values {
            task.cancel()
        }
    }
    
    func setNDK(_ ndk: NDK) {
        self.ndk = ndk
        
        // Cancel existing observers
        for task in stateObserverTasks.values {
            task.cancel()
        }
        stateObserverTasks.removeAll()
        
        // Set up observers for all relays
        Task {
            let allRelays = await ndk.relays
            for relay in allRelays {
                setupRelayObserver(relay)
            }
        }
        
        updateConnectionStatus()
    }
    
    private func setupRelayObserver(_ relay: NDKRelay) {
        let url = relay.url
        
        // Cancel any existing observer for this relay
        stateObserverTasks[url]?.cancel()
        
        // Create new observer task
        let task = Task {
            for await state in relay.stateStream {
                await MainActor.run {
                    if let index = relays.firstIndex(where: { $0.url == url }) {
                        relays[index].isConnected = state.connectionState == .connected
                        if relays[index].isConnected {
                            relays[index].lastSeen = Date()
                        }
                    }
                }
            }
        }
        
        stateObserverTasks[url] = task
    }
    
    func addRelay(_ url: String) {
        let normalizedUrl = normalizeRelayUrl(url)
        guard !relays.contains(where: { $0.url == normalizedUrl }) else { return }
        
        let relay = RelayInfo(url: normalizedUrl)
        relays.append(relay)
        saveRelays()
        
        if let ndk = ndk {
            Task {
                let ndkRelay = await ndk.addRelay(normalizedUrl)
                setupRelayObserver(ndkRelay)
                // Connect to the newly added relay
                try? await ndkRelay.connect()
                updateConnectionStatus()
            }
        }
    }
    
    func removeRelay(_ relay: RelayInfo) {
        relays.removeAll { $0.id == relay.id }
        saveRelays()
        
        // Cancel observer for this relay
        stateObserverTasks[relay.url]?.cancel()
        stateObserverTasks.removeValue(forKey: relay.url)
        
        if let ndk = ndk {
            Task {
                await ndk.removeRelay(relay.url)
            }
        }
    }
    
    func toggleRelay(_ relay: RelayInfo) {
        guard let index = relays.firstIndex(where: { $0.id == relay.id }) else { return }
        relays[index].isActive.toggle()
        saveRelays()
        
        if let ndk = ndk {
            Task {
                if relays[index].isActive {
                    let ndkRelay = await ndk.addRelay(relay.url)
                    setupRelayObserver(ndkRelay)
                    // Connect to the newly activated relay
                    try? await ndkRelay.connect()
                } else {
                    // Cancel observer when deactivating
                    stateObserverTasks[relay.url]?.cancel()
                    stateObserverTasks.removeValue(forKey: relay.url)
                    await ndk.removeRelay(relay.url)
                }
                updateConnectionStatus()
            }
        }
    }
    
    func resetToDefaults() {
        relays = defaultRelays.map { RelayInfo(url: $0) }
        saveRelays()
        
        // Cancel all observers
        for task in stateObserverTasks.values {
            task.cancel()
        }
        stateObserverTasks.removeAll()
        
        if let ndk = ndk {
            Task {
                // Remove all existing relays
                for relay in await ndk.relays {
                    await ndk.removeRelay(relay.url)
                }
                
                // Add default relays and set up observers
                for relay in relays where relay.isActive {
                    let ndkRelay = await ndk.addRelay(relay.url)
                    setupRelayObserver(ndkRelay)
                }
                // Connect to all relays
                await ndk.pool.connectAll()
                await updateConnectionStatus()
            }
        }
    }
    
    private func updateConnectionStatus() {
        guard let ndk = ndk else { return }
        
        Task {
            let allRelays = await ndk.relays
            var connectedRelays: [NDKRelay] = []
            for relay in allRelays {
                if await relay.isConnected {
                    connectedRelays.append(relay)
                }
            }
            
            await MainActor.run {
                for i in relays.indices {
                    relays[i].isConnected = connectedRelays.contains { $0.url == relays[i].url }
                    if relays[i].isConnected {
                        relays[i].lastSeen = Date()
                    }
                }
            }
        }
    }
    
    private func normalizeRelayUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("wss://") && !normalized.hasPrefix("ws://") {
            normalized = "wss://\(normalized)"
        }
        if !normalized.hasSuffix("/") {
            normalized += "/"
        }
        return normalized
    }
    
    private func loadRelays() {
        if let data = UserDefaults.standard.data(forKey: "relay_list"),
           let decoded = try? JSONDecoder().decode([RelayInfo].self, from: data) {
            relays = decoded
        } else {
            relays = defaultRelays.map { RelayInfo(url: $0) }
        }
    }
    
    private func saveRelays() {
        if let encoded = try? JSONEncoder().encode(relays) {
            UserDefaults.standard.set(encoded, forKey: "relay_list")
        }
    }
}