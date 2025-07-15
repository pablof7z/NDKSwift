import Foundation
import CashuSwift
@testable import NDKSwift

/// Simple mock implementation of NDKCache for testing
/// Implements all required methods with minimal functionality
actor SimpleMockCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var unpublishedEvents: [(event: NDKEvent, relays: Set<String>)] = []
    private var confirmations: [String: Set<String>] = [:] // eventId -> relayUrls
    
    // MARK: - Event Operations
    
    func saveEvent(_ event: NDKEvent) async throws {
        events[event.id] = event
    }
    
    func getEvent(id: String) async -> NDKEvent? {
        events[id]
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results = Array(events.values)
        
        if let ids = filter.ids {
            results = results.filter { ids.contains($0.id) }
        }
        
        if let authors = filter.authors {
            results = results.filter { authors.contains($0.pubkey) }
        }
        
        if let kinds = filter.kinds {
            results = results.filter { kinds.contains($0.kind) }
        }
        
        if let limit = filter.limit {
            results = Array(results.prefix(limit))
        }
        
        return results
    }
    
    func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
    }
    
    // MARK: - Profile Operations
    
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        profiles[pubkey] = profile
    }
    
    func getProfile(pubkey: String) async -> NDKUserProfile? {
        profiles[pubkey]
    }
    
    // MARK: - Optimistic Publishing Support
    
    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        unpublishedEvents.append((event, relays))
    }
    
    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if confirmations[eventId] != nil {
            confirmations[eventId]?.insert(relay)
        } else {
            confirmations[eventId] = [relay]
        }
        
        // Remove from unpublished if all relays confirmed
        if let index = unpublishedEvents.firstIndex(where: { $0.event.id == eventId }) {
            var remainingRelays = unpublishedEvents[index].relays
            remainingRelays.remove(relay)
            
            if remainingRelays.isEmpty {
                unpublishedEvents.remove(at: index)
            } else {
                unpublishedEvents[index].relays = remainingRelays
            }
        }
    }
    
    func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        if let confirmedRelays = confirmations[eventId], !confirmedRelays.isEmpty {
            return .confirmed(fromRelay: confirmedRelays.first!)
        }
        
        if unpublishedEvents.contains(where: { $0.event.id == eventId }) {
            return .optimistic
        }
        
        return nil
    }
    
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Date().timeIntervalSince1970 - maxAge
        var results = unpublishedEvents.filter { $0.event.createdAt >= Int64(cutoffTime) }
        
        if let limit = limit {
            results = Array(results.prefix(limit))
        }
        
        // Convert to expected tuple format
        return results.map { (event: $0.event, targetRelays: $0.relays) }
    }
    
    // MARK: - Decrypted Content Cache
    
    func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        nil // Not implemented in mock
    }
    
    func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        // Not implemented in mock
    }
    
    func clearDecryptedContent() async {
        // Not implemented in mock
    }
    
    func clearDecryptedContent(for viewerPubkey: String) async {
        // Not implemented in mock
    }
    
    // MARK: - Mint Cache Operations
    
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        // Not implemented in mock
    }
    
    func getMintInfo(url: String) async -> NDKMintInfo? {
        nil // Not implemented in mock
    }
    
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        true // Always stale in mock
    }
    
    func invalidateMintCache(url: String) async throws {
        // Not implemented in mock
    }
    
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        // Not implemented in mock
    }
    
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        // Not implemented in mock
    }
    
    func getKeyset(id: String, mintUrl: String) async -> CashuSwift.Keyset? {
        nil // Not implemented in mock
    }
    
    func getActiveKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        [] // Not implemented in mock
    }
    
    func getAllKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        [] // Not implemented in mock
    }
    
    func markKeysetInactive(id: String, mintUrl: String) async throws {
        // Not implemented in mock
    }
    
    // MARK: - Utility
    
    func clear() async throws {
        events.removeAll()
        profiles.removeAll()
        unpublishedEvents.removeAll()
        confirmations.removeAll()
    }
    
    func reset() async {
        events.removeAll()
        profiles.removeAll()
        unpublishedEvents.removeAll()
        confirmations.removeAll()
    }
}