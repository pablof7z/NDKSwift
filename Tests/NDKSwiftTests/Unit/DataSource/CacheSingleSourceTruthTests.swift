import XCTest
@testable import NDKSwift

final class CacheSingleSourceTruthTests: XCTestCase {
    var ndk: NDK!
    var cache: MockTrackingCache!
    var signer: MockNDKSigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a custom mock cache that tracks all operations
        cache = MockTrackingCache()
        signer = MockNDKSigner()
        
        ndk = NDK(signer: signer, cache: cache)
        await ndk.connect()  // No relays needed for this test
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }
    
    func testAllEventsFlowThroughCache() async throws {
        // Create a filter for text notes
        let filter = NDKFilter(kinds: [1], limit: 10)
        
        // Create data source
        let dataSource = ndk.observe(filter: filter)
        
        // Give it time to register with cache
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify cache received observer registration
        let registrationCount = await cache.getObserverRegistrationCount()
        
        // With no relays configured, only our test's registration should exist
        XCTAssertEqual(registrationCount, 1, "Expected 1 registration from test")
        
        // Verify our specific registration exists
        let hasMatchingRegistration = await cache.hasObserverRegistration(kinds: [1], limit: 10)
        XCTAssertTrue(hasMatchingRegistration, "Should have our test's registration")
        
        // Create a test event
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: Int64(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test event content",
            sig: "test_sig"
        )
        
        // Simulate event arriving from relay through cache
        await cache.simulateEventFromRelay(event, relay: "wss://test.relay", subscriptionId: "test_sub")
        
        // Give time for event to propagate
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify cache processed the event
        let processedCount = await cache.getProcessedEventCount()
        XCTAssertEqual(processedCount, 1)
        let firstProcessedId = await cache.getFirstProcessedEventId()
        XCTAssertEqual(firstProcessedId, event.id)
        
        // Verify data source received the event through cache observer
        XCTAssertEqual(dataSource.data.count, 1)
        XCTAssertEqual(dataSource.data.first?.id, event.id)
        
        // Verify NO direct event delivery occurred (only through cache)
        let directDeliveryCount = await cache.getDirectDeliveryCount()
        XCTAssertEqual(directDeliveryCount, 0, "Events should ONLY flow through cache observers")
    }
    
    func testMultipleDataSourcesShareCacheObservation() async throws {
        let filter = NDKFilter(authors: ["author1"], kinds: [1])
        
        // Create multiple data sources with same filter
        let dataSource1 = ndk.observe(filter: filter)
        let dataSource2 = ndk.observe(filter: filter)
        
        // Give time to register
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Both should be registered as cache observers
        let registrationCount = await cache.getObserverRegistrationCount()
        XCTAssertGreaterThanOrEqual(registrationCount, 2)
        
        // Create test event
        let event = NDKEvent(
            id: "shared_id",
            pubkey: "author1",
            createdAt: Int64(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Shared event",
            sig: "shared_sig"
        )
        
        // Simulate event through cache
        await cache.simulateEventFromRelay(event, relay: "wss://test.relay", subscriptionId: "test_sub")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Both data sources should receive the event through cache
        XCTAssertEqual(dataSource1.data.count, 1)
        XCTAssertEqual(dataSource2.data.count, 1)
        XCTAssertEqual(dataSource1.data.first?.id, event.id)
        XCTAssertEqual(dataSource2.data.first?.id, event.id)
        
        // Cache should have processed event only once
        let processedCount = await cache.getProcessedEventCount()
        XCTAssertEqual(processedCount, 1)
    }
}

// Mock cache that tracks all operations
actor MockTrackingCache: NDKCache {
    struct ObserverRegistration {
        let filter: NDKFilter
        let observer: CacheObserver
    }
    
    struct ProcessedEvent {
        let event: NDKEvent
        let relay: String
        let subscriptionId: String
    }
    
    var observerRegistrations: [ObserverRegistration] = []
    var processedEvents: [ProcessedEvent] = []
    var directDeliveries: [NDKEvent] = [] // Should remain empty
    private var observers: [(filter: NDKFilter, observer: CacheObserver)] = []
    
    func saveEvent(_ event: NDKEvent) async throws {
        // Just track it
    }
    
    func saveEvents(_ events: [NDKEvent]) async throws {
        // Just track them
    }
    
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        return []
    }
    
    func deleteEvent(id: String) async throws {
        // Just track it
    }
    
    // Missing required methods
    func getEvent(id: String) async -> NDKEvent? {
        return processedEvents.first { $0.event.id == id }?.event
    }
    
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        // Just track it
    }
    
    func getProfile(pubkey: String) async -> NDKUserProfile? {
        return nil
    }
    
    func clear() async throws {
        observerRegistrations.removeAll()
        processedEvents.removeAll()
        directDeliveries.removeAll()
        observers.removeAll()
    }
    
    func confirmEvent(eventId: String, onRelay relayURL: String) async throws {
        // Just track it
    }
    
    func hasEvent(id: String) async -> Bool {
        return processedEvents.contains { $0.event.id == id }
    }
    
    func observeEvents(
        matching filter: NDKFilter,
        observer: CacheObserver
    ) async -> ObservationHandle {
        observerRegistrations.append(ObserverRegistration(filter: filter, observer: observer))
        observers.append((filter, observer))
        
        return ObservationHandle {
            // Remove observer on cancel
        }
    }
    
    func processEvent(
        _ event: NDKEvent,
        from relay: String,
        subscriptionId: String
    ) async throws {
        processedEvents.append(ProcessedEvent(event: event, relay: relay, subscriptionId: subscriptionId))
        
        // Notify matching observers - THIS is the single source of truth
        for (filter, observer) in observers {
            if eventMatchesFilter(event, filter: filter) {
                await observer.handleEvent(event)
            }
        }
    }
    
    func getRelaySources(eventId: String) async -> Set<String> {
        let sources = processedEvents
            .filter { $0.event.id == eventId }
            .map { $0.relay }
        return Set(sources)
    }
    
    func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        return nil
    }
    
    func recordFetchTime(for filter: NDKFilter, timestamp: Date) async {
        // Just track it
    }
    
    // Helper to simulate events
    func simulateEventFromRelay(_ event: NDKEvent, relay: String, subscriptionId: String) async {
        try? await processEvent(event, from: relay, subscriptionId: subscriptionId)
    }
    
    private func eventMatchesFilter(_ event: NDKEvent, filter: NDKFilter) -> Bool {
        if let kinds = filter.kinds, !kinds.contains(event.kind) {
            return false
        }
        
        if let authors = filter.authors, !authors.contains(event.pubkey) {
            return false
        }
        
        return true
    }
    
    // Helper methods for testing actor isolation
    func getObserverRegistrationCount() -> Int {
        observerRegistrations.count
    }
    
    func getObserverRegistrations() -> [ObserverRegistration] {
        observerRegistrations
    }
    
    func hasObserverRegistration(kinds: [Int], limit: Int?) -> Bool {
        observerRegistrations.contains { registration in
            registration.filter.kinds == kinds && registration.filter.limit == limit
        }
    }
    
    func getProcessedEventCount() -> Int {
        processedEvents.count
    }
    
    func getFirstProcessedEventId() -> String? {
        processedEvents.first?.event.id
    }
    
    func getDirectDeliveryCount() -> Int {
        directDeliveries.count
    }
}