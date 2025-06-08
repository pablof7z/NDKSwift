import XCTest
@testable import NDKSwift

final class EventDeduplicatorTests: XCTestCase {
    
    func testBasicDeduplication() async throws {
        let deduplicator = EventDeduplicator(config: .default)
        
        let eventId = "test_event_123"
        
        // First check - should not be duplicate
        let isDupe1 = await deduplicator.isDuplicate(eventId)
        XCTAssertFalse(isDupe1)
        
        // Mark as seen
        await deduplicator.markSeen(eventId)
        
        // Second check - should be duplicate
        let isDupe2 = await deduplicator.isDuplicate(eventId)
        XCTAssertTrue(isDupe2)
        
        // Check statistics
        let stats = await deduplicator.getStatistics()
        XCTAssertEqual(stats.totalChecks, 2)
        XCTAssertEqual(stats.duplicates, 1)
        XCTAssertEqual(stats.uniqueEvents, 1)
        XCTAssertEqual(stats.cacheHits, 1)
        XCTAssertEqual(stats.cacheMisses, 1)
    }
    
    func testProcessEvent() async throws {
        let deduplicator = EventDeduplicator(config: .default)
        
        let event = createTestEvent(id: "process_test_123")
        
        // First process - should return true (new event)
        let isNew1 = await deduplicator.processEvent(event)
        XCTAssertTrue(isNew1)
        
        // Second process - should return false (duplicate)
        let isNew2 = await deduplicator.processEvent(event)
        XCTAssertFalse(isNew2)
        
        // Third process - still duplicate
        let isNew3 = await deduplicator.processEvent(event)
        XCTAssertFalse(isNew3)
        
        let stats = await deduplicator.getStatistics()
        XCTAssertEqual(stats.uniqueEvents, 1)
        XCTAssertEqual(stats.duplicates, 2)
    }
    
    func testPerRelayTracking() async throws {
        let config = EventDeduplicationConfig(
            cacheSize: 1000,
            ttl: 3600,
            perRelayTracking: true
        )
        let deduplicator = EventDeduplicator(config: config)
        
        let eventId = "relay_test_123"
        let relay1 = "wss://relay1.test"
        let relay2 = "wss://relay2.test"
        
        // Mark seen from relay1
        await deduplicator.markSeen(eventId, from: relay1)
        
        // Check from relay1 - should be duplicate
        let isDupe1 = await deduplicator.isDuplicate(eventId, from: relay1)
        XCTAssertTrue(isDupe1)
        
        // Check from relay2 - should still be duplicate (global cache)
        let isDupe2 = await deduplicator.isDuplicate(eventId, from: relay2)
        XCTAssertTrue(isDupe2)
        
        // Clear global cache
        await deduplicator.clear()
        
        // Now test relay-specific behavior
        let newEventId = "relay_specific_456"
        await deduplicator.markSeen(newEventId, from: relay1)
        
        // Should be in both global and relay cache
        let sizes1 = await deduplicator.getCacheSizes()
        XCTAssertEqual(sizes1.global, 1)
        XCTAssertEqual(sizes1.perRelay[relay1], 1)
    }
    
    func testCacheSizeLimit() async throws {
        let config = EventDeduplicationConfig(
            cacheSize: 10, // Very small for testing
            ttl: nil, // No expiration
            perRelayTracking: false
        )
        let deduplicator = EventDeduplicator(config: config)
        
        // Add more events than cache size
        for i in 0..<20 {
            await deduplicator.markSeen("event_\(i)")
        }
        
        // Cache should have evicted oldest entries
        let sizes = await deduplicator.getCacheSizes()
        XCTAssertLessThanOrEqual(sizes.global, 10)
        
        // Oldest events should no longer be duplicates
        let isOldDupe = await deduplicator.isDuplicate("event_0")
        XCTAssertFalse(isOldDupe)
        
        // Recent events should still be duplicates
        let isRecentDupe = await deduplicator.isDuplicate("event_19")
        XCTAssertTrue(isRecentDupe)
    }
    
    func testStatistics() async throws {
        let deduplicator = EventDeduplicator(config: .default)
        
        // Process multiple events
        let events = (0..<100).map { createTestEvent(id: "stats_\($0)") }
        
        // Process each event twice
        for event in events {
            _ = await deduplicator.processEvent(event)
            _ = await deduplicator.processEvent(event) // Duplicate
        }
        
        let stats = await deduplicator.getStatistics()
        XCTAssertEqual(stats.totalChecks, 200)
        XCTAssertEqual(stats.uniqueEvents, 100)
        XCTAssertEqual(stats.duplicates, 100)
        XCTAssertEqual(stats.duplicateRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(stats.cacheHitRate, 0.5, accuracy: 0.01)
    }
    
    func testClearOperations() async throws {
        let config = EventDeduplicationConfig(
            cacheSize: 1000,
            ttl: nil,
            perRelayTracking: true
        )
        let deduplicator = EventDeduplicator(config: config)
        
        let relay1 = "wss://relay1.test"
        let relay2 = "wss://relay2.test"
        
        // Add events from multiple relays
        for i in 0..<10 {
            await deduplicator.markSeen("event_\(i)", from: relay1)
            await deduplicator.markSeen("event_\(i + 10)", from: relay2)
        }
        
        // Clear relay1
        await deduplicator.clearRelay(relay1)
        
        let sizes1 = await deduplicator.getCacheSizes()
        XCTAssertNil(sizes1.perRelay[relay1])
        XCTAssertNotNil(sizes1.perRelay[relay2])
        XCTAssertGreaterThan(sizes1.global, 0)
        
        // Clear all
        await deduplicator.clear()
        
        let sizes2 = await deduplicator.getCacheSizes()
        XCTAssertEqual(sizes2.global, 0)
        XCTAssertTrue(sizes2.perRelay.isEmpty)
    }
    
    func testConcurrentAccess() async throws {
        let deduplicator = EventDeduplicator(config: .highVolume)
        
        // Concurrent processing
        await withTaskGroup(of: Bool.self) { group in
            // Process 1000 unique events
            for i in 0..<1000 {
                group.addTask {
                    let event = self.createTestEvent(id: "concurrent_\(i)")
                    return await deduplicator.processEvent(event)
                }
            }
            
            // Process same events again (duplicates)
            for i in 0..<1000 {
                group.addTask {
                    let event = self.createTestEvent(id: "concurrent_\(i)")
                    return await deduplicator.processEvent(event)
                }
            }
            
            var newCount = 0
            for await isNew in group {
                if isNew {
                    newCount += 1
                }
            }
            
            XCTAssertEqual(newCount, 1000)
        }
        
        let stats = await deduplicator.getStatistics()
        XCTAssertEqual(stats.uniqueEvents, 1000)
        XCTAssertEqual(stats.duplicates, 1000)
    }
    
    func testConfigurationPresets() async {
        // Test default config
        let defaultConfig = EventDeduplicationConfig.default
        XCTAssertEqual(defaultConfig.cacheSize, 10000)
        XCTAssertEqual(defaultConfig.ttl, 3600)
        XCTAssertFalse(defaultConfig.perRelayTracking)
        
        // Test high volume config
        let highVolumeConfig = EventDeduplicationConfig.highVolume
        XCTAssertEqual(highVolumeConfig.cacheSize, 50000)
        XCTAssertEqual(highVolumeConfig.ttl, 1800)
        XCTAssertTrue(highVolumeConfig.perRelayTracking)
        
        // Test low memory config
        let lowMemoryConfig = EventDeduplicationConfig.lowMemory
        XCTAssertEqual(lowMemoryConfig.cacheSize, 1000)
        XCTAssertEqual(lowMemoryConfig.ttl, 600)
        XCTAssertFalse(lowMemoryConfig.perRelayTracking)
    }
    
    func testEventExtensions() async throws {
        let ndk = NDK()
        let event = createTestEvent(id: "extension_test")
        
        // First check - should not be duplicate
        let isDupe1 = await event.isDuplicate(in: ndk)
        XCTAssertFalse(isDupe1)
        
        // Mark as seen
        await event.markSeen(in: ndk)
        
        // Second check - should be duplicate
        let isDupe2 = await event.isDuplicate(in: ndk)
        XCTAssertTrue(isDupe2)
    }
    
    // MARK: - Helpers
    
    private func createTestEvent(id: String? = nil) -> NDKEvent {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test event"
        )
        event.id = id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        event.sig = "test_signature"
        return event
    }
}