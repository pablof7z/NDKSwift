import Foundation

/// Extensions to NDKRelayPool for outbox model support
public extension NDKRelayPool {
    /// Get relay by URL
    func relay(for url: String) async -> NDKRelay? {
        return await getRelay(for: url)
    }

    /// Add a relay and optionally connect to it
    @discardableResult
    func addRelay(url: String) async -> NDKRelay? {
        let relay = addRelay(url)

        // Try to connect
        do {
            try await relay.connect()
            return relay
        } catch {
            // Connection failed, but relay is still added
            return relay
        }
    }

    /// Get permanent and connected relays
    func permanentAndConnectedRelays() async -> [NDKRelay] {
        // For now, return all connected relays
        // In the future, could distinguish between permanent and temporary relays
        return await connectedRelays()
    }
}

/// Extensions to NDKRelay for outbox model support
public extension NDKRelay {
    /// Subscribe to events on this relay
    func subscribe(
        filters: [NDKFilter],
        eventHandler: @escaping (NDKEvent) -> Void
    ) -> Task<Void, Error> {
        // Create subscription with this specific relay
        var options = NDKSubscriptionOptions()
        options.relays = Set([self])

        let subscription = NDKSubscription(
            filters: filters,
            options: options,
            ndk: nil
        )

        // Start task to handle events
        return Task {
            do {
                for try await event in subscription {
                    eventHandler(event)
                }
            } catch {
                // Subscription completed or failed
                throw error
            }
        }
    }
}
