import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class RelayManager {
    private(set) var ndk: NDK?
    var userAddedRelays: Set<String> = []
    
    private let defaultRelays = [
        RelayConstants.primal,
        RelayConstants.damus,
        RelayConstants.nostrBand,
        RelayConstants.nosLol
    ]
    
    private let userRelaysKey = "user_added_relays"
    
    init() {
        loadUserRelays()
    }
    
    func setNDK(_ ndk: NDK) {
        self.ndk = ndk
    }
    
    func getAllRelays() -> [String] {
        var relays = Set(defaultRelays)
        relays.formUnion(userAddedRelays)
        return Array(relays)
    }
    
    func addUserRelay(_ url: String) {
        let normalizedUrl = normalizeRelayUrl(url)
        userAddedRelays.insert(normalizedUrl)
        saveUserRelays()
        
        // Add to NDK if initialized
        if let ndk = ndk {
            Task {
                await ndk.addRelayAndConnect(normalizedUrl)
            }
        }
    }
    
    func removeUserRelay(_ url: String) {
        userAddedRelays.remove(url)
        saveUserRelays()
        
        // Remove from NDK if initialized and not a default relay
        if let ndk = ndk, !defaultRelays.contains(url) {
            Task {
                let allRelays = await ndk.relays
                if let relay = allRelays.first(where: { $0.url == url }) {
                    await relay.disconnect()
                    // Note: NDK doesn't have a removeRelay method, so we just disconnect
                }
            }
        }
    }
    
    func resetToDefaults() {
        userAddedRelays.removeAll()
        saveUserRelays()
        
        // Reconnect with only default relays
        if let ndk = ndk {
            Task {
                // Disconnect all non-default relays
                let allRelays = await ndk.relays
                for relay in allRelays where !defaultRelays.contains(relay.url) {
                    await relay.disconnect()
                }
            }
        }
    }
    
    private func normalizeRelayUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("wss://") && !normalized.hasPrefix("ws://") {
            normalized = "wss://\(normalized)"
        }
        // Note: NDK handles URL normalization internally, including trailing slashes
        return normalized
    }
    
    private func loadUserRelays() {
        if let savedRelays = UserDefaults.standard.array(forKey: userRelaysKey) as? [String] {
            userAddedRelays = Set(savedRelays)
        }
    }
    
    private func saveUserRelays() {
        UserDefaults.standard.set(Array(userAddedRelays), forKey: userRelaysKey)
    }
}