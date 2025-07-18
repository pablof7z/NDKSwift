import Foundation
import CashuSwift

/// Comprehensive in-memory cache implementation for testing and temporary use
public actor MemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    private var unpublishedEventRelays: [String: Set<String>] = [:]
    private var eventCreationTimes: [String: Date] = [:]
    private var decryptedContent: LRUCache<String, String>
    private var mintInfos: [String: (info: NDKMintInfo, timestamp: Date)] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var mintKeysets: [String: [(keyset: CashuSwift.Keyset, timestamp: Date)]] = [:]
    
    public init() {
        // Initialize LRU cache with 1000 item limit for decrypted content
        self.decryptedContent = LRUCache(capacity: 1000)
    }
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        let eventId = event.id
        events[eventId] = event
        print("[MemoryCache] Saved event \(eventId)")
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        let event = events[id]
        print("[MemoryCache] Retrieved event \(id): \(event != nil ? "found" : "not found")")
        return event
    }
    
    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []
        
        for event in events.values {
            if filter.matches(event: event) {
                results.append(event)
            }
        }
        
        // Apply limit if specified
        if let limit = filter.limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        // Sort by created_at descending
        // Extract created_at values for sorting
        let sortedResults = await withTaskGroup(of: (NDKEvent, Timestamp).self) { group in
            for event in results {
                group.addTask {
                    let timestamp = event.createdAt
                    return (event, timestamp)
                }
            }
            
            var eventWithTimestamps: [(NDKEvent, Timestamp)] = []
            for await result in group {
                eventWithTimestamps.append(result)
            }
            
            // Sort by timestamp descending
            eventWithTimestamps.sort { $0.1 > $1.1 }
            
            return eventWithTimestamps.map { $0.0 }
        }
        
        results = sortedResults
        
        print("[MemoryCache] Query returned \(results.count) events")
        return results
    }
    
    public func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
        print("[MemoryCache] Deleted event \(id)")
    }
    
    // MARK: - Profile Operations
    
    public func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        profiles[pubkey] = profile
        print("[MemoryCache] Saved profile for \(pubkey)")
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        let profile = profiles[pubkey]
        print("[MemoryCache] Retrieved profile for \(pubkey): \(profile != nil ? "found" : "not found")")
        return profile
    }
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        events.removeAll()
        profiles.removeAll()
        eventConfirmations.removeAll()
        mintInfos.removeAll()
        keysets.removeAll()
        mintKeysets.removeAll()
        await decryptedContent.clear()
        print("[MemoryCache] Cleared all cache data")
    }
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        events[eventId] = event
        eventConfirmations[eventId] = .optimistic
        unpublishedEventRelays[eventId] = relays
        eventCreationTimes[eventId] = Date()
        print("[MemoryCache] Added unpublished event \(eventId) for relays: \(relays.joined(separator: ", "))")
    }
    
    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if let existingState = eventConfirmations[eventId] {
            switch existingState {
            case .optimistic:
                eventConfirmations[eventId] = .confirmed(fromRelay: relay)
                print("[MemoryCache] Confirmed event \(eventId) on relay \(relay)")
            case .confirmed:
                print("[MemoryCache] Event \(eventId) already confirmed")
            }
        } else {
            // Event not found, might have been confirmed directly
            eventConfirmations[eventId] = .confirmed(fromRelay: relay)
            print("[MemoryCache] Marked event \(eventId) as confirmed on relay \(relay)")
        }
    }
    
    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return eventConfirmations[eventId]
    }
    
    public func getUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Date().addingTimeInterval(-maxAge)
        var results: [(event: NDKEvent, targetRelays: Set<String>)] = []
        
        for (eventId, confirmationState) in eventConfirmations {
            // Only include optimistic events
            guard case .optimistic = confirmationState else { continue }
            
            // Check age constraint
            if let creationTime = eventCreationTimes[eventId], creationTime < cutoffTime {
                continue
            }
            
            // Get the event and relays
            guard let event = events[eventId],
                  let targetRelays = unpublishedEventRelays[eventId] else { continue }
            
            results.append((event: event, targetRelays: targetRelays))
        }
        
        // Sort by creation time (newest first)
        results.sort { lhs, rhs in
            let lhsTime = eventCreationTimes[lhs.event.id] ?? Date.distantPast
            let rhsTime = eventCreationTimes[rhs.event.id] ?? Date.distantPast
            return lhsTime > rhsTime
        }
        
        // Apply limit if specified
        if let limit = limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        print("[MemoryCache] Found \(results.count) unpublished events (maxAge: \(maxAge)s)")
        return results
    }
    
    // MARK: - Decrypted Content Cache
    
    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        let key = "\(eventId):\(viewerPubkey)"
        return await decryptedContent.get(key)
    }
    
    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        let key = "\(eventId):\(viewerPubkey)"
        await decryptedContent.set(key, value: content)
        print("[MemoryCache] Cached decrypted content for event \(eventId) viewer \(viewerPubkey)")
    }
    
    public func clearDecryptedContent() async {
        await decryptedContent.clear()
        print("[MemoryCache] Cleared all decrypted content")
    }
    
    public func clearDecryptedContent(for viewerPubkey: String) async {
        // Get all keys that end with the viewer pubkey
        let allItems = await decryptedContent.allItems()
        for (key, _) in allItems where key.hasSuffix(":\(viewerPubkey)") {
            await decryptedContent.remove(key)
        }
        print("[MemoryCache] Cleared decrypted content for viewer \(viewerPubkey)")
    }
    
    // MARK: - Debug Helpers
    
    public func eventCount() async -> Int {
        return events.count
    }
    
    public func profileCount() async -> Int {
        return profiles.count
    }
    
    public func unconfirmedEventCount() async -> Int {
        return eventConfirmations.values.filter { !$0.isConfirmed }.count
    }
    
    // MARK: - Mint Cache Operations
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mintInfos[url] = (info, Date())
        print("[MemoryCache] Saved mint info for \(url)")
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        let info = mintInfos[url]?.info
        print("[MemoryCache] Retrieved mint info for \(url): \(info != nil ? "found" : "not found")")
        return info
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = mintInfos[url] else { return true }
        let isStale = Date().timeIntervalSince(entry.timestamp) > maxAge
        print("[MemoryCache] Mint info for \(url) is \(isStale ? "stale" : "fresh")")
        return isStale
    }
    
    public func invalidateMintCache(url: String) async throws {
        mintInfos.removeValue(forKey: url)
        mintKeysets.removeValue(forKey: url)
        print("[MemoryCache] Invalidated mint cache for \(url)")
    }
    
    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        keysets[keyset.keysetID] = keyset
        
        var mintList = mintKeysets[mintUrl] ?? []
        mintList.append((keyset, Date()))
        mintKeysets[mintUrl] = mintList
        
        print("[MemoryCache] Saved keyset \(keyset.keysetID) for mint \(mintUrl)")
    }
    
    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let timestamp = Date()
        var mintList = mintKeysets[mintUrl] ?? []
        
        for keyset in keysets {
            self.keysets[keyset.keysetID] = keyset
            mintList.append((keyset, timestamp))
        }
        
        mintKeysets[mintUrl] = mintList
        print("[MemoryCache] Saved \(keysets.count) keysets for mint \(mintUrl)")
    }
    
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        let keyset = keysets[id]
        print("[MemoryCache] Retrieved keyset \(id): \(keyset != nil ? "found" : "not found")")
        return keyset
    }
    
    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        let keysets = mintKeysets[mintUrl]?.map { $0.keyset } ?? []
        print("[MemoryCache] Retrieved \(keysets.count) keysets for mint \(mintUrl)")
        return keysets
    }
    
    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        let activeKeysets = mintKeysets[mintUrl]?
            .map { $0.keyset }
            .filter { $0.unit == unit && $0.active } ?? []
        print("[MemoryCache] Retrieved \(activeKeysets.count) active keysets for mint \(mintUrl) unit \(unit)")
        return activeKeysets
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        guard let entries = mintKeysets[mintUrl], !entries.isEmpty else { 
            print("[MemoryCache] No keysets found for mint \(mintUrl), considering stale")
            return true 
        }
        
        let oldestTimestamp = entries.map { $0.timestamp }.min() ?? Date()
        let isStale = Date().timeIntervalSince(oldestTimestamp) > maxAge
        print("[MemoryCache] Keysets for mint \(mintUrl) are \(isStale ? "stale" : "fresh")")
        return isStale
    }
}