import Foundation
import Observation

// MARK: - Saved Feed Sources Manager

/// Manages saved follow packs and relays for feed source selection
@Observable
@MainActor
public final class SavedFeedSourcesManager {
    // MARK: - UserDefaults Keys

    private static let packsKey = "com.ndkswift.Chirp.savedPacks"
    private static let relaysKey = "com.ndkswift.Chirp.savedRelays"
    private static let activeSourceKey = "com.ndkswift.Chirp.activeFeedSource"

    // MARK: - Published State

    public private(set) var savedPacks: [SavedPack] = []
    public private(set) var savedRelays: [SavedRelay] = []
    public var activeSource: FeedSource = .follows {
        didSet { persistActiveSource() }
    }

    // MARK: - Initialization

    public init() {
        load()
    }

    // MARK: - Pack Management

    func savePack(_ pack: FollowPack) {
        let savedPack = SavedPack(
            id: pack.id,
            name: pack.name,
            description: pack.description,
            imageURL: pack.imageURL,
            pubkeys: pack.pubkeys,
            creatorPubkey: pack.creatorPubkey
        )

        guard !savedPacks.contains(where: { $0.id == savedPack.id }) else { return }
        savedPacks.append(savedPack)
        persistPacks()
    }

    public func removePack(id: String) {
        savedPacks.removeAll { $0.id == id }
        persistPacks()

        // Reset to follows if we removed the active pack
        if case .pack(let pack) = activeSource, pack.id == id {
            activeSource = .follows
        }
    }

    public func isPacked(_ packId: String) -> Bool {
        savedPacks.contains { $0.id == packId }
    }

    // MARK: - Relay Management

    func saveRelay(_ relay: RankedRelay) {
        let savedRelay = SavedRelay(
            url: relay.url,
            displayName: relay.displayName,
            description: relay.description,
            iconURL: relay.iconURL
        )

        guard !savedRelays.contains(where: { $0.url == savedRelay.url }) else { return }
        savedRelays.append(savedRelay)
        persistRelays()
    }

    public func saveRelay(url: String, displayName: String, description: String?, iconURL: String?) {
        let savedRelay = SavedRelay(
            url: url,
            displayName: displayName,
            description: description,
            iconURL: iconURL
        )

        guard !savedRelays.contains(where: { $0.url == savedRelay.url }) else { return }
        savedRelays.append(savedRelay)
        persistRelays()
    }

    public func removeRelay(url: String) {
        savedRelays.removeAll { $0.url == url }
        persistRelays()

        // Reset to follows if we removed the active relay
        if case .relay(let relay) = activeSource, relay.url == url {
            activeSource = .follows
        }
    }

    public func isRelaySaved(_ url: String) -> Bool {
        savedRelays.contains { $0.url == url }
    }

    // MARK: - Persistence

    private func load() {
        loadPacks()
        loadRelays()
        loadActiveSource()
    }

    private func loadPacks() {
        guard let data = UserDefaults.standard.data(forKey: Self.packsKey),
              let packs = try? JSONDecoder().decode([SavedPack].self, from: data) else {
            return
        }
        savedPacks = packs
    }

    private func loadRelays() {
        guard let data = UserDefaults.standard.data(forKey: Self.relaysKey),
              let relays = try? JSONDecoder().decode([SavedRelay].self, from: data) else {
            return
        }
        savedRelays = relays
    }

    private func loadActiveSource() {
        guard let data = UserDefaults.standard.data(forKey: Self.activeSourceKey),
              let source = try? JSONDecoder().decode(FeedSource.self, from: data) else {
            activeSource = .follows
            return
        }

        // Validate the source still exists
        switch source {
        case .follows:
            activeSource = source
        case .pack(let pack):
            if savedPacks.contains(where: { $0.id == pack.id }) {
                activeSource = source
            } else {
                activeSource = .follows
            }
        case .relay(let relay):
            if savedRelays.contains(where: { $0.url == relay.url }) {
                activeSource = source
            } else {
                activeSource = .follows
            }
        }
    }

    private func persistPacks() {
        guard let data = try? JSONEncoder().encode(savedPacks) else { return }
        UserDefaults.standard.set(data, forKey: Self.packsKey)
    }

    private func persistRelays() {
        guard let data = try? JSONEncoder().encode(savedRelays) else { return }
        UserDefaults.standard.set(data, forKey: Self.relaysKey)
    }

    private func persistActiveSource() {
        guard let data = try? JSONEncoder().encode(activeSource) else { return }
        UserDefaults.standard.set(data, forKey: Self.activeSourceKey)
    }
}
