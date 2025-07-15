import Foundation
@testable import NDKSwift

/// Mock implementation of NDKCache for testing
actor MockCache: NDKCache {
    var savedEvents: [NDKEvent] = []
    var unpublishedEvents: [(event: NDKEvent, relays: Set<String>)] = []
    var confirmedEvents: [(eventId: String, relay: String)] = []
    var profiles: [String: NDKUserProfile] = [:]
    var shouldFailSave = false
    var shouldFailUnpublished = false
    var shouldFailConfirm = false
    
    // MARK: - Event Operations
    
    func saveEvent(_ event: NDKEvent) async throws {
        if shouldFailSave {
            throw NDKError.cacheFailed(operation: "save", underlying: nil)
        }
        savedEvents.append(event)
    }
    
    func getEvent(id: String) async -> NDKEvent? {
        savedEvents.first { $0.id == id }
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        // Simple filtering implementation for tests
        var results = savedEvents
        
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
    
    func deleteEvent(id eventId: String) async throws {
        savedEvents.removeAll { $0.id == eventId }
        unpublishedEvents.removeAll { $0.event.id == eventId }
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
        if shouldFailUnpublished {
            throw NDKError.cacheFailed(operation: "unpublished save", underlying: nil)
        }
        unpublishedEvents.append((event, relays))
    }
    
    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if shouldFailConfirm {
            throw NDKError.cacheFailed(operation: "confirm", underlying: nil)
        }
        
        confirmedEvents.append((eventId, relay))
        
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
        // Check if event is in unpublished events
        if unpublishedEvents.contains(where: { $0.event.id == eventId }) {
            // Check if it has any confirmations
            if let confirmedRelay = confirmedEvents.first(where: { $0.eventId == eventId })?.relay {
                return .confirmed(fromRelay: confirmedRelay)
            } else {
                return .optimistic
            }
        }
        
        // Check if event has any confirmations
        if let confirmedRelay = confirmedEvents.first(where: { $0.eventId == eventId })?.relay {
            return .confirmed(fromRelay: confirmedRelay)
        }
        
        return nil
    }
    
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, relays: Set<String>)] {
        let cutoffTime = Date().timeIntervalSince1970 - maxAge
        var results = unpublishedEvents.filter { $0.event.createdAt >= Int64(cutoffTime) }
        
        if let limit = limit {
            results = Array(results.prefix(limit))
        }
        
        return results
    }
    
    // MARK: - Decrypted Content Support
    
    func saveDecryptedContent(_ content: String, for eventId: String, scheme: NDKEncryptionScheme) async throws {
        // Not implemented in mock
    }
    
    func getDecryptedContent(for eventId: String, scheme: NDKEncryptionScheme) async -> String? {
        // Not implemented in mock
        return nil
    }
    
    // MARK: - Relay Management
    
    // Not implemented in mock cache
    
    // MARK: - Utility
    
    func reset() {
        savedEvents.removeAll()
        unpublishedEvents.removeAll()
        confirmedEvents.removeAll()
        profiles.removeAll()
        shouldFailSave = false
        shouldFailUnpublished = false
        shouldFailConfirm = false
    }
    
    func clear() async throws {
        savedEvents.removeAll()
        unpublishedEvents.removeAll()
        confirmedEvents.removeAll()
        profiles.removeAll()
    }
}