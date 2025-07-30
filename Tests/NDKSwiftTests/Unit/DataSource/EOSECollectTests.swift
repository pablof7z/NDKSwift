import XCTest
@testable import NDKSwift

/// Tests for the new EOSE-based collect() behavior
final class EOSECollectTests: NDKTestCase {
    
    /// Test that collect() returns immediately when aggregated EOSE is received
    func testCollectReturnsOnAggregatedEOSE() async throws {
        // Setup
        let relays = await setupTestRelays(count: 3)
        let filter = NDKFilter(kinds: [EventKind.textNote], limit: 10)
        
        // Create a data source with closeOnEose
        let dataSource = ndk.observe(filter: filter, closeOnEose: true)
        
        // Track timing
        let startTime = Date()
        
        // Mock some events and EOSE
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Send a few events from different relays
            for i in 0..<3 {
                let event = try createTextNote(content: "Test \(i)")
                await dataSource.handleRelayUpdate(.event(event, relay: relays[i % relays.count].url))
            }
            
            // Send individual EOSE from each relay
            for relay in relays {
                await dataSource.handleRelayUpdate(.eose(relay: relay.url))
            }
            
            // The aggregated EOSE should be emitted automatically by EOSETracker
        }
        
        // Collect events - should return quickly after EOSE
        let events = await dataSource.collect(timeout: 10.0)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Verify
        XCTAssertEqual(events.count, 3, "Should have collected 3 events")
        XCTAssertLessThan(elapsedTime, 1.0, "Should return much faster than timeout (got \(elapsedTime)s)")
    }
    
    /// Test progressive timeout with partial EOSE
    func testProgressiveTimeoutWithPartialEOSE() async throws {
        // Setup with 4 relays
        let relays = await setupTestRelays(count: 4)
        let filter = NDKFilter(kinds: [EventKind.textNote])
        
        let dataSource = ndk.observe(filter: filter, closeOnEose: true)
        
        // Track timing
        let startTime = Date()
        
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Send event
            let event = try createTextNote(content: "Test")
            await dataSource.handleRelayUpdate(.event(event, relay: relays[0].url))
            
            // Send EOSE from 3 out of 4 relays (75%)
            for i in 0..<3 {
                await dataSource.handleRelayUpdate(.eose(relay: relays[i].url))
            }
            
            // With 75% EOSE, timeout should be ~250ms (1s * 0.25)
        }
        
        // Collect events
        let events = await dataSource.collect(timeout: 10.0)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Verify
        XCTAssertEqual(events.count, 1, "Should have collected 1 event")
        XCTAssertLessThan(elapsedTime, 0.5, "Should return within progressive timeout window")
        XCTAssertGreaterThan(elapsedTime, 0.15, "Should wait at least for initial delay + some timeout")
    }
    
    /// Test query fully filled with IDs
    func testQueryFullyFilledWithIDs() async throws {
        // Setup
        let relays = await setupTestRelays(count: 2)
        let eventIds = ["id1", "id2", "id3"]
        let filter = NDKFilter(ids: eventIds)
        
        let dataSource = ndk.observe(filter: filter, closeOnEose: true)
        
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Send all requested events from first relay
            for id in eventIds {
                let event = try createTextNote(content: "Test")
                event.id = id
                await dataSource.handleRelayUpdate(.event(event, relay: relays[0].url))
            }
            
            // Only need EOSE from one relay since we got all IDs
            await dataSource.handleRelayUpdate(.eose(relay: relays[0].url))
        }
        
        let startTime = Date()
        let events = await dataSource.collect(timeout: 10.0)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Verify - should return immediately after getting all IDs
        XCTAssertEqual(events.count, 3, "Should have collected all 3 requested events")
        XCTAssertLessThan(elapsedTime, 0.2, "Should return immediately after getting all IDs")
    }
    
    /// Test query fully filled with limit
    func testQueryFullyFilledWithLimit() async throws {
        // Setup
        let relays = await setupTestRelays(count: 3)
        let filter = NDKFilter(kinds: [EventKind.textNote], limit: 5)
        
        let dataSource = ndk.observe(filter: filter, closeOnEose: true)
        
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Send exactly the limit from first relay
            for i in 0..<5 {
                let event = try createTextNote(content: "Test \(i)")
                await dataSource.handleRelayUpdate(.event(event, relay: relays[0].url))
            }
            
            // EOSE from first relay should trigger completion
            await dataSource.handleRelayUpdate(.eose(relay: relays[0].url))
        }
        
        let startTime = Date()
        let events = await dataSource.collect(timeout: 10.0)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Verify
        XCTAssertEqual(events.count, 5, "Should have collected exactly the limit")
        XCTAssertLessThan(elapsedTime, 0.2, "Should return immediately after hitting limit")
    }
    
    /// Test replaceable events wait for all relays
    func testReplaceableEventsWaitForAllRelays() async throws {
        // Setup
        let relays = await setupTestRelays(count: 3)
        let filter = NDKFilter(
            authors: ["pubkey1"],
            kinds: [EventKind.profile] // Replaceable event
        )
        
        let dataSource = ndk.observe(filter: filter, closeOnEose: true)
        
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Send profile from first relay
            let profile1 = try createProfileEvent(name: "Old Name")
            profile1.createdAt = Timestamp.now - 100
            await dataSource.handleRelayUpdate(.event(profile1, relay: relays[0].url))
            await dataSource.handleRelayUpdate(.eose(relay: relays[0].url))
            
            // Wait a bit then send newer profile from second relay
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            let profile2 = try createProfileEvent(name: "New Name")
            profile2.createdAt = Timestamp.now
            await dataSource.handleRelayUpdate(.event(profile2, relay: relays[1].url))
            await dataSource.handleRelayUpdate(.eose(relay: relays[1].url))
            
            // Send EOSE from third relay
            await dataSource.handleRelayUpdate(.eose(relay: relays[2].url))
        }
        
        let events = await dataSource.collect(timeout: 10.0)
        
        // Verify - should have both profiles, allowing user to pick newest
        XCTAssertEqual(events.count, 2, "Should have collected both profile versions")
    }
    
    // MARK: - Helper Methods
    
    private func setupTestRelays(count: Int) async -> [MockRelay] {
        var relays: [MockRelay] = []
        for i in 0..<count {
            let relay = MockRelay(url: "wss://relay\(i).test", ndk: ndk)
            relays.append(relay)
            await ndk.pool.addRelay(relay)
        }
        return relays
    }
    
    private func createTextNote(content: String) throws -> NDKEvent {
        let event = NDKEvent(ndk: ndk)
        event.kind = EventKind.textNote
        event.content = content
        event.pubkey = "test_pubkey"
        event.createdAt = Timestamp.now
        event.tags = []
        event.id = IDGenerator.generateEventId()
        return event
    }
    
    private func createProfileEvent(name: String) throws -> NDKEvent {
        let event = NDKEvent(ndk: ndk)
        event.kind = EventKind.profile
        event.content = """
        {"name": "\(name)", "about": "Test profile"}
        """
        event.pubkey = "pubkey1"
        event.createdAt = Timestamp.now
        event.tags = []
        event.id = IDGenerator.generateEventId()
        return event
    }
}