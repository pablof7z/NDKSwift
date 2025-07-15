import Foundation
import CashuSwift

/// Full in-memory cache implementation for testing or temporary use
/// This implementation provides all NDKCache functionality including events, profiles, and mint data
public actor FullInMemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var mintInfos: [String: (info: NDKMintInfo, timestamp: Date)] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var mintKeysets: [String: [(keyset: CashuSwift.Keyset, timestamp: Date)]] = [:]
    
    public init() {}
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        events[event.id] = event
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        return events[id]
    }
    
    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []
        for event in events.values {
            if filter.matches(event: event) {
                results.append(event)
            }
        }
        return results
    }
    
    public func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
    }
    
    // MARK: - Profile Operations
    
    public func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        profiles[pubkey] = profile
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        return profiles[pubkey]
    }
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        try await saveEvent(event)
    }
    
    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        // No-op for in-memory cache
    }
    
    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return nil
    }
    
    public func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        return []
    }
    
    // MARK: - Decrypted Content Cache
    
    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        return nil
    }
    
    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        // No-op for in-memory cache
    }
    
    public func clearDecryptedContent() async {
        // No-op for in-memory cache
    }
    
    public func clearDecryptedContent(for viewerPubkey: String) async {
        // No-op for in-memory cache
    }
    
    // MARK: - Mint Cache Operations
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mintInfos[url] = (info, Date())
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        return mintInfos[url]?.info
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = mintInfos[url] else { return true }
        return Date().timeIntervalSince(entry.timestamp) > maxAge
    }
    
    public func invalidateMintCache(url: String) async throws {
        mintInfos.removeValue(forKey: url)
        mintKeysets.removeValue(forKey: url)
    }
    
    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        keysets[keyset.keysetID] = keyset
        
        var mintList = mintKeysets[mintUrl] ?? []
        mintList.append((keyset, Date()))
        mintKeysets[mintUrl] = mintList
    }
    
    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let timestamp = Date()
        var mintList = mintKeysets[mintUrl] ?? []
        
        for keyset in keysets {
            self.keysets[keyset.keysetID] = keyset
            mintList.append((keyset, timestamp))
        }
        
        mintKeysets[mintUrl] = mintList
    }
    
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return keysets[id]
    }
    
    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        return mintKeysets[mintUrl]?.map { $0.keyset } ?? []
    }
    
    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        return mintKeysets[mintUrl]?
            .map { $0.keyset }
            .filter { $0.unit == unit && $0.active } ?? []
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        guard let entries = mintKeysets[mintUrl], !entries.isEmpty else { return true }
        
        // Check the timestamp of the oldest keyset
        let oldestTimestamp = entries.map { $0.timestamp }.min() ?? Date()
        return Date().timeIntervalSince(oldestTimestamp) > maxAge
    }
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        events.removeAll()
        profiles.removeAll()
        mintInfos.removeAll()
        keysets.removeAll()
        mintKeysets.removeAll()
    }
}