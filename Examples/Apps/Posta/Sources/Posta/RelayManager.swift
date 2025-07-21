import Foundation
import NDKSwift
import Combine

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
    private var relayCollection: NDKRelayCollection?
    private var cancellables = Set<AnyCancellable>()
    
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
        // Cleanup handled by NDKRelayCollection
    }
    
    func setNDK(_ ndk: NDK) {
        self.ndk = ndk
        
        // Create relay collection for observing state
        self.relayCollection = ndk.createRelayCollection()
        
        // Observe relay collection changes
        Task {
            await observeRelayCollection()
            await updateConnectionStatus()
        }
    }
    
    private func observeRelayCollection() async {
        guard let collection = relayCollection else { return }
        
        // Observe changes from NDKRelayCollection
        collection.$relays
            .sink { [weak self] ndkRelays in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Update our relay info based on NDK relay states
                    for ndkRelay in ndkRelays {
                        if let index = self.relays.firstIndex(where: { $0.url == ndkRelay.url }) {
                            self.relays[index].isConnected = ndkRelay.isConnected
                            if ndkRelay.isConnected {
                                self.relays[index].lastSeen = ndkRelay.lastConnectedAt
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func addRelay(_ url: String) {
        let normalizedUrl = normalizeRelayUrl(url)
        guard !relays.contains(where: { $0.url == normalizedUrl }) else { return }
        
        let relay = RelayInfo(url: normalizedUrl)
        relays.append(relay)
        saveRelays()
        
        if let collection = relayCollection {
            Task {
                await collection.addRelay(normalizedUrl)
            }
        }
    }
    
    func removeRelay(_ relay: RelayInfo) {
        relays.removeAll { $0.id == relay.id }
        saveRelays()
        
        if let collection = relayCollection {
            Task {
                await collection.removeRelay(relay.url)
            }
        }
    }
    
    func toggleRelay(_ relay: RelayInfo) {
        guard let index = relays.firstIndex(where: { $0.id == relay.id }) else { return }
        relays[index].isActive.toggle()
        saveRelays()
        
        if let collection = relayCollection {
            Task {
                if relays[index].isActive {
                    await collection.addRelay(relay.url)
                } else {
                    await collection.removeRelay(relay.url)
                }
            }
        }
    }
    
    func resetToDefaults() {
        relays = defaultRelays.map { RelayInfo(url: $0) }
        saveRelays()
        
        if let ndk = ndk, let collection = relayCollection {
            Task {
                // Remove all existing relays
                for relay in await ndk.relays {
                    await collection.removeRelay(relay.url)
                }
                
                // Add default relays
                for relay in relays where relay.isActive {
                    await collection.addRelay(relay.url)
                }
            }
        }
    }
    
    private func updateConnectionStatus() async {
        // Update connection status from relay collection
        guard let collection = relayCollection else { return }
        await collection.refresh()
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
           let decoded = try? JSONCoding.decoder.decode([RelayInfo].self, from: data) {
            relays = decoded
        } else {
            relays = defaultRelays.map { RelayInfo(url: $0) }
        }
    }
    
    private func saveRelays() {
        if let encoded = try? JSONCoding.encoder.encode(relays) {
            UserDefaults.standard.set(encoded, forKey: "relay_list")
        }
    }
}