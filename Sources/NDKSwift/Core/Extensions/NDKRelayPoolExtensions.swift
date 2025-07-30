import Foundation

/// Extensions to NDKPool for outbox model support
public extension NDKPool {
    /// Get relay by URL
    func relay(for url: String) async -> NDKRelay? {
        return await getRelay(for: url)
    }


    /// Get permanent and connected relays
    func permanentAndConnectedRelays() async -> [NDKRelay] {
        // Return all connected relays
        // Future enhancement: distinguish between permanent and temporary relays
        return await connectedRelays()
    }
}
