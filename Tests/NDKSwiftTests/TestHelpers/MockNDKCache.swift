import Foundation
@testable import NDKSwift

// Mock cache adapter for testing
actor MockNDKCache: NDKCache {
    private var storedEvents: [String: NDKEvent] = [:]
    private var storedProfiles: [String: NDKUserProfile] = [:]
    private var eventsByFilter: [String: Set<String>] = [:] // Filter hash -> event IDs
    
    // Tracking for test assertions
    var saveEventCallCount = 0
    var fetchEventsCallCount = 0
    var saveProfileCallCount = 0
    var fetchProfileCallCount = 0
    var lastSavedEvent: NDKEvent?
    var lastFetchedFilter: NDKFilter?
    
    func saveEvent(_ event: NDKEvent) async throws {
        saveEventCallCount += 1
        lastSavedEvent = event
        
        storedEvents[event.id] = event
        
        // Update filter mappings for efficient querying
        updateFilterMappings(for: event)
    }
    
    func saveEvents(_ events: [NDKEvent]) async throws {
        for event in events {
            try await saveEvent(event)
        }
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        fetchEventsCallCount += 1
        lastFetchedFilter = filter
        
        // Simple filter matching for testing
        var results: [NDKEvent] = []
        
        for event in storedEvents.values {
            if matchesFilter(event, filter) {
                results.append(event)
            }
        }
        
        // Apply limit if specified
        if let limit = filter.limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        return results
    }
    
    func getEvent(id: String) async -> NDKEvent? {
        return storedEvents[id]
    }
    
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        saveProfileCallCount += 1
        storedProfiles[pubkey] = profile
    }
    
    func getProfile(pubkey: String) async -> NDKUserProfile? {
        fetchProfileCallCount += 1
        return storedProfiles[pubkey]
    }
    
    func deleteEvent(id: String) async throws {
        storedEvents.removeValue(forKey: id)
    }
    
    func clear() async throws {
        storedEvents.removeAll()
        storedProfiles.removeAll()
        eventsByFilter.removeAll()
    }
    
    // Helper methods for testing
    func getAllEvents() async -> [NDKEvent] {
        Array(storedEvents.values)
    }
    
    func getEventCount() async -> Int {
        storedEvents.count
    }
    
    func hasEvent(withId id: String) async -> Bool {
        storedEvents[id] != nil
    }
    
    func reset() async {
        storedEvents.removeAll()
        storedProfiles.removeAll()
        eventsByFilter.removeAll()
        saveEventCallCount = 0
        fetchEventsCallCount = 0
        saveProfileCallCount = 0
        fetchProfileCallCount = 0
        lastSavedEvent = nil
        lastFetchedFilter = nil
    }
    
    // Private helper methods
    private func matchesFilter(_ event: NDKEvent, _ filter: NDKFilter) -> Bool {
        // Check IDs
        if let ids = filter.ids, !ids.isEmpty {
            guard ids.contains(event.id) else { return false }
        }
        
        // Check authors
        if let authors = filter.authors, !authors.isEmpty {
            guard authors.contains(event.pubkey) else { return false }
        }
        
        // Check kinds
        if let kinds = filter.kinds, !kinds.isEmpty {
            guard kinds.contains(event.kind) else { return false }
        }
        
        // Check time range
        if let since = filter.since {
            guard event.createdAt >= since else { return false }
        }
        
        if let until = filter.until {
            guard event.createdAt <= until else { return false }
        }
        
        // Check tags
        if let tags = filter.tags {
            for (tagName, tagValues) in tags {
                let eventTagValues = event.tags
                    .filter { $0.count > 0 && $0[0] == tagName }
                    .compactMap { $0.count > 1 ? $0[1] : nil }
                
                let hasMatchingTag = tagValues.contains { requiredValue in
                    eventTagValues.contains(requiredValue)
                }
                
                if !hasMatchingTag {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func updateFilterMappings(for event: NDKEvent) {
        // This would be more sophisticated in a real implementation
        // For testing, we'll just track by kind
        let filterKey = "kind:\(event.kind)"
        if eventsByFilter[filterKey] == nil {
            eventsByFilter[filterKey] = []
        }
        eventsByFilter[filterKey]?.insert(event.id)
    }
}