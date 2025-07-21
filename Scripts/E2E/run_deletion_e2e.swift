#!/usr/bin/env swift

import Foundation
@testable import NDKSwift
import XCTest

// Simple E2E test runner for deletion tests
@main
struct DeletionE2ERunner {
    static func main() async throws {
        NDKLogger.log(.info, category: .general, "Starting Event Deletion E2E Tests")
        
        let tests = EventDeletionE2ETests()
        
        do {
            // Run setup
            try await tests.setUp()
            
            // Run each test
            NDKLogger.log(.info, category: .general, "\n=== Running testBasicEventDeletionE2E ===")
            try await tests.testBasicEventDeletionE2E()
            NDKLogger.log(.info, category: .general, "✅ testBasicEventDeletionE2E passed")
            
            NDKLogger.log(.info, category: .general, "\n=== Running testDeletionAuthorValidationE2E ===")
            try await tests.testDeletionAuthorValidationE2E()
            NDKLogger.log(.info, category: .general, "✅ testDeletionAuthorValidationE2E passed")
            
            NDKLogger.log(.info, category: .general, "\n=== Running testMultipleEventDeletionE2E ===")
            try await tests.testMultipleEventDeletionE2E()
            NDKLogger.log(.info, category: .general, "✅ testMultipleEventDeletionE2E passed")
            
            NDKLogger.log(.info, category: .general, "\n=== Running testCrossInstanceDeletionSyncE2E ===")
            try await tests.testCrossInstanceDeletionSyncE2E()
            NDKLogger.log(.info, category: .general, "✅ testCrossInstanceDeletionSyncE2E passed")
            
            NDKLogger.log(.info, category: .general, "\n=== Running testDeletionTombstoneE2E ===")
            try await tests.testDeletionTombstoneE2E()
            NDKLogger.log(.info, category: .general, "✅ testDeletionTombstoneE2E passed")
            
            NDKLogger.log(.info, category: .general, "\n✅ All deletion E2E tests passed!")
            
        } catch {
            NDKLogger.log(.error, category: .general, "❌ Test failed with error: \(error)")
            exit(1)
        }
    }
}

// Include the test class
final class EventDeletionE2ETests: XCTestCase {
    
    // Real relays for E2E testing
    let testRelays = ["wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol"]
    let timeout: TimeInterval = 30.0
    
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = true
        NDKLogger.enabledCategories = [.event, .relay, .network, .subscription]
    }
    
    // MARK: - Basic Deletion Flow
    
    func testBasicEventDeletionE2E() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .event, "🧪 Starting testBasicEventDeletionE2E at \(startTime)")
        
        // Create NDK instances
        let publisher = NDK(cache: MemoryCache())
        let subscriber = NDK(cache: MemoryCache())
        
        // Create signers
        let authorSigner = try NDKPrivateKeySigner.generate()
        publisher.signer = authorSigner
        
        // Add relays
        for relay in testRelays {
            await publisher.addRelay(relay)
            await subscriber.addRelay(relay)
        }
        
        await publisher.connect()
        await subscriber.connect()
        
        NDKLogger.log(.debug, category: .event, "⏱️ Connected to relays after \(Date().timeIntervalSince(startTime))s")
        
        // Create and publish an event
        let eventCreationTime = Date()
        let (textEvent, publishedRelays) = try await publisher.publish { builder in
            builder
                .content("Test event for deletion E2E test - \(UUID().uuidString)")
                .kind(EventKind.textNote)
        }
        
        NDKLogger.log(.info, category: .event, "📤 Published event \(textEvent.id) to \(publishedRelays.count) relays after \(Date().timeIntervalSince(eventCreationTime))s")
        
        // Wait for event to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Verify event exists on subscriber
        let fetchTime = Date()
        let filter = NDKFilter(ids: [textEvent.id])
        let dataSource = subscriber.observe(filter: filter, maxAge: 3600)
        
        var fetchedEvents: [NDKEvent] = []
        for await event in dataSource.events {
            fetchedEvents.append(event)
            if event.id == textEvent.id {
                break
            }
        }
        
        XCTAssertEqual(fetchedEvents.count, 1, "Should fetch the published event")
        XCTAssertEqual(fetchedEvents.first?.id, textEvent.id)
        NDKLogger.log(.debug, category: .event, "✅ Verified event exists after \(Date().timeIntervalSince(fetchTime))s")
        
        // Create and publish deletion event
        let deletionTime = Date()
        let (deletionEvent, deletionRelays) = try await publisher.publish { builder in
            builder
                .content("Deletion of event \(textEvent.id)")
                .kind(EventKind.deletion)
                .tag(["e", textEvent.id])
                .tag(["k", String(textEvent.kind)])
        }
        
        NDKLogger.log(.info, category: .event, "🗑️ Published deletion event \(deletionEvent.id) to \(deletionRelays.count) relays after \(Date().timeIntervalSince(deletionTime))s")
        
        // Wait for deletion to propagate
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify event is deleted
        let verifyTime = Date()
        let verifyDataSource = subscriber.observe(filter: filter, maxAge: 3600)
        
        var fetchedAfterDeletion: [NDKEvent] = []
        for await event in verifyDataSource.events {
            fetchedAfterDeletion.append(event)
            // Wait a bit to ensure we get all events
            try await Task.sleep(nanoseconds: 500_000_000)
            break // Exit after waiting
        }
        
        XCTAssertEqual(fetchedAfterDeletion.count, 0, "Event should be deleted")
        NDKLogger.log(.info, category: .event, "✅ Verified event deletion after \(Date().timeIntervalSince(verifyTime))s")
        
        // Disconnect
        await publisher.disconnect()
        await subscriber.disconnect()
        
        NDKLogger.log(.info, category: .event, "✅ testBasicEventDeletionE2E completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    // MARK: - Author Validation
    
    func testDeletionAuthorValidationE2E() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .event, "🧪 Starting testDeletionAuthorValidationE2E at \(startTime)")
        
        // Create NDK instances
        let originalAuthor = NDK(cache: MemoryCache())
        let maliciousActor = NDK(cache: MemoryCache())
        let observer = NDK(cache: MemoryCache())
        
        // Create signers
        let authorSigner = try NDKPrivateKeySigner.generate()
        let maliciousSigner = try NDKPrivateKeySigner.generate()
        
        originalAuthor.signer = authorSigner
        maliciousActor.signer = maliciousSigner
        
        // Add relays to all instances
        for relay in testRelays {
            await originalAuthor.addRelay(relay)
            await maliciousActor.addRelay(relay)
            await observer.addRelay(relay)
        }
        
        await originalAuthor.connect()
        await maliciousActor.connect()
        await observer.connect()
        
        NDKLogger.log(.debug, category: .event, "⏱️ All instances connected after \(Date().timeIntervalSince(startTime))s")
        
        // Original author publishes event
        let eventTime = Date()
        let (textEvent, _) = try await originalAuthor.publish { builder in
            builder
                .content("Protected event - \(UUID().uuidString)")
                .kind(EventKind.textNote)
        }
        
        NDKLogger.log(.info, category: .event, "📤 Original author published event \(textEvent.id) after \(Date().timeIntervalSince(eventTime))s")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Malicious actor tries to delete the event
        let maliciousTime = Date()
        let (maliciousDeletion, _) = try await maliciousActor.publish { builder in
            builder
                .content("Trying to delete someone else's event")
                .kind(EventKind.deletion)
                .tag(["e", textEvent.id])
                .tag(["k", String(textEvent.kind)])
        }
        
        NDKLogger.log(.warning, category: .event, "🦹 Malicious deletion attempt published after \(Date().timeIntervalSince(maliciousTime))s")
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Verify event still exists (deletion should be rejected)
        let verifyTime = Date()
        let filter = NDKFilter(ids: [textEvent.id])
        let dataSource = observer.observe(filter: filter, maxAge: 3600)
        
        var fetchedEvents: [NDKEvent] = []
        for await event in dataSource.events {
            fetchedEvents.append(event)
            if event.id == textEvent.id {
                break
            }
        }
        
        XCTAssertEqual(fetchedEvents.count, 1, "Event should still exist after invalid deletion attempt")
        NDKLogger.log(.info, category: .event, "✅ Event protected from unauthorized deletion after \(Date().timeIntervalSince(verifyTime))s")
        
        // Now original author deletes their own event
        let legitimateTime = Date()
        let (legitimateDeletion, _) = try await originalAuthor.publish { builder in
            builder
                .content("Deleting my own event")
                .kind(EventKind.deletion)
                .tag(["e", textEvent.id])
                .tag(["k", String(textEvent.kind)])
        }
        
        NDKLogger.log(.info, category: .event, "🗑️ Legitimate deletion published after \(Date().timeIntervalSince(legitimateTime))s")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Verify event is now deleted
        let finalVerifyTime = Date()
        let finalDataSource = observer.observe(filter: filter, maxAge: 3600)
        
        var finalFetch: [NDKEvent] = []
        for await event in finalDataSource.events {
            finalFetch.append(event)
            // Wait a bit to ensure we check properly
            try await Task.sleep(nanoseconds: 500_000_000)
            break
        }
        
        XCTAssertEqual(finalFetch.count, 0, "Event should be deleted by original author")
        NDKLogger.log(.info, category: .event, "✅ Event successfully deleted by author after \(Date().timeIntervalSince(finalVerifyTime))s")
        
        // Disconnect all
        await originalAuthor.disconnect()
        await maliciousActor.disconnect()
        await observer.disconnect()
        
        NDKLogger.log(.info, category: .event, "✅ testDeletionAuthorValidationE2E completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    // MARK: - Multiple Event Deletion
    
    func testMultipleEventDeletionE2E() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .event, "🧪 Starting testMultipleEventDeletionE2E at \(startTime)")
        
        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        for relay in testRelays {
            await ndk.addRelay(relay)
        }
        await ndk.connect()
        
        // Create multiple events
        let eventCount = 5
        var events: [NDKEvent] = []
        
        let creationTime = Date()
        for i in 0..<eventCount {
            let (event, _) = try await ndk.publish { builder in
                builder
                    .content("Batch deletion test event #\(i) - \(UUID().uuidString)")
                    .kind(EventKind.textNote)
            }
            events.append(event)
        }
        
        NDKLogger.log(.info, category: .event, "📤 Published \(eventCount) events after \(Date().timeIntervalSince(creationTime))s")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Create deletion event for all
        let deletionTime = Date()
        let builder = ndk.event()
            .content("Deleting multiple events")
            .kind(EventKind.deletion)
        
        // Add all event IDs to deletion
        for event in events {
            builder.tag(["e", event.id])
            builder.tag(["k", String(event.kind)])
        }
        
        let deletionEvent = try await builder.build()
        let deletionRelays = try await ndk.publish(deletionEvent)
        
        NDKLogger.log(.info, category: .event, "🗑️ Published batch deletion event to \(deletionRelays.count) relays after \(Date().timeIntervalSince(deletionTime))s")
        
        // Wait for deletion propagation
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Verify all events are deleted
        let verifyTime = Date()
        let eventIds = events.map { $0.id }
        let filter = NDKFilter(ids: eventIds)
        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
        
        var remainingEvents: [NDKEvent] = []
        let collectStart = Date()
        for await event in dataSource.events {
            remainingEvents.append(event)
            // Give it time to collect any events
            if Date().timeIntervalSince(collectStart) > 2.0 {
                break
            }
        }
        
        XCTAssertEqual(remainingEvents.count, 0, "All events should be deleted")
        NDKLogger.log(.info, category: .event, "✅ Verified batch deletion after \(Date().timeIntervalSince(verifyTime))s")
        
        await ndk.disconnect()
        
        NDKLogger.log(.info, category: .event, "✅ testMultipleEventDeletionE2E completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    // MARK: - Cross-Instance Deletion Sync
    
    func testCrossInstanceDeletionSyncE2E() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .event, "🧪 Starting testCrossInstanceDeletionSyncE2E at \(startTime)")
        
        // Create three NDK instances with the same user
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        
        let instance1 = NDK(cache: MemoryCache())
        let instance2 = NDK(cache: MemoryCache())
        let instance3 = NDK(cache: MemoryCache())
        
        instance1.signer = signer
        instance2.signer = signer
        instance3.signer = signer
        
        // Connect all to same relays
        for instance in [instance1, instance2, instance3] {
            for relay in testRelays {
                await instance.addRelay(relay)
            }
            await instance.connect()
        }
        
        NDKLogger.log(.debug, category: .event, "⏱️ All instances connected after \(Date().timeIntervalSince(startTime))s")
        
        // Instance 1 publishes an event
        let eventTime = Date()
        let (event, _) = try await instance1.publish { builder in
            builder
                .content("Cross-instance deletion test - \(UUID().uuidString)")
                .kind(EventKind.textNote)
        }
        
        NDKLogger.log(.info, category: .event, "📤 Instance 1 published event \(event.id) after \(Date().timeIntervalSince(eventTime))s")
        
        // Set up real-time subscriptions on instances 2 and 3
        let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.textNote])
        var receivedOnInstance2 = false
        var receivedOnInstance3 = false
        var deletedOnInstance2 = false
        var deletedOnInstance3 = false
        
        // Subscribe on instance 2
        Task {
            let subscription2Time = Date()
            let dataSource2 = instance2.observe(filter: filter)
            for await receivedEvent in dataSource2.events {
                if receivedEvent.id == event.id {
                    receivedOnInstance2 = true
                    NDKLogger.log(.debug, category: .event, "📨 Instance 2 received event after \(Date().timeIntervalSince(subscription2Time))s")
                }
            }
        }
        
        // Subscribe on instance 3
        Task {
            let subscription3Time = Date()
            let dataSource3 = instance3.observe(filter: filter)
            for await receivedEvent in dataSource3.events {
                if receivedEvent.id == event.id {
                    receivedOnInstance3 = true
                    NDKLogger.log(.debug, category: .event, "📨 Instance 3 received event after \(Date().timeIntervalSince(subscription3Time))s")
                }
            }
        }
        
        // Wait for event to be received
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Instance 2 deletes the event
        let deletionTime = Date()
        let (deletionEvent, _) = try await instance2.publish { builder in
            builder
                .content("Deleting event from instance 2")
                .kind(EventKind.deletion)
                .tag(["e", event.id])
                .tag(["k", String(event.kind)])
        }
        
        NDKLogger.log(.info, category: .event, "🗑️ Instance 2 published deletion after \(Date().timeIntervalSince(deletionTime))s")
        
        // Wait for deletion propagation
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Check if events are deleted on other instances
        let checkTime = Date()
        let eventFilter = NDKFilter(ids: [event.id])
        
        // Check instance 2
        let dataSource2 = instance2.observe(filter: eventFilter, maxAge: 3600)
        var fetch2: [NDKEvent] = []
        for await e in dataSource2.events {
            fetch2.append(e)
            try await Task.sleep(nanoseconds: 500_000_000)
            break
        }
        
        // Check instance 3
        let dataSource3 = instance3.observe(filter: eventFilter, maxAge: 3600)
        var fetch3: [NDKEvent] = []
        for await e in dataSource3.events {
            fetch3.append(e)
            try await Task.sleep(nanoseconds: 500_000_000)
            break
        }
        
        deletedOnInstance2 = fetch2.isEmpty
        deletedOnInstance3 = fetch3.isEmpty
        
        NDKLogger.log(.debug, category: .event, "📊 Deletion check after \(Date().timeIntervalSince(checkTime))s - Instance2: \(deletedOnInstance2), Instance3: \(deletedOnInstance3)")
        
        XCTAssertTrue(deletedOnInstance2, "Event should be deleted on instance 2")
        XCTAssertTrue(deletedOnInstance3, "Event should be deleted on instance 3")
        
        // Disconnect all
        await instance1.disconnect()
        await instance2.disconnect()
        await instance3.disconnect()
        
        NDKLogger.log(.info, category: .event, "✅ testCrossInstanceDeletionSyncE2E completed in \(Date().timeIntervalSince(startTime))s")
    }
    
    // MARK: - Tombstone Mechanism Test
    
    func testDeletionTombstoneE2E() async throws {
        let startTime = Date()
        NDKLogger.log(.info, category: .event, "🧪 Starting testDeletionTombstoneE2E at \(startTime)")
        
        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        for relay in testRelays {
            await ndk.addRelay(relay)
        }
        await ndk.connect()
        
        // Create an event ID and content deterministically
        let content = "Tombstone test event - \(UUID().uuidString)"
        let timestamp = Timestamp.now
        
        // Build the event locally first to get its ID
        let localEvent = try await ndk.event()
            .content(content)
            .kind(EventKind.textNote)
            .createdAt(timestamp)
            .build()
        
        // First, publish the deletion event (before the actual event)
        let deletionTime = Date()
        let (deletionEvent, _) = try await ndk.publish { builder in
            builder
                .content("Pre-deleting event \(localEvent.id)")
                .kind(EventKind.deletion)
                .tag(["e", localEvent.id])
                .tag(["k", String(EventKind.textNote)])
        }
        
        NDKLogger.log(.info, category: .event, "🗑️ Published deletion event BEFORE original event after \(Date().timeIntervalSince(deletionTime))s")
        
        // Wait for deletion to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Now publish the original event
        let eventTime = Date()
        let publishedRelays = try await ndk.publish(localEvent)
        NDKLogger.log(.info, category: .event, "📤 Published original event AFTER deletion to \(publishedRelays.count) relays after \(Date().timeIntervalSince(eventTime))s")
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Verify event is not retrievable (tombstone should prevent it)
        let verifyTime = Date()
        let filter = NDKFilter(ids: [localEvent.id])
        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
        
        var fetchedEvents: [NDKEvent] = []
        let collectStart = Date()
        for await event in dataSource.events {
            fetchedEvents.append(event)
            // Give enough time to ensure we'd get the event if it existed
            if Date().timeIntervalSince(collectStart) > 2.0 {
                break
            }
        }
        
        XCTAssertEqual(fetchedEvents.count, 0, "Event should be blocked by tombstone")
        NDKLogger.log(.info, category: .event, "✅ Tombstone mechanism prevented deleted event from appearing after \(Date().timeIntervalSince(verifyTime))s")
        
        await ndk.disconnect()
        
        NDKLogger.log(.info, category: .event, "✅ testDeletionTombstoneE2E completed in \(Date().timeIntervalSince(startTime))s")
    }
}

// Lightweight XCTest assertion functions for standalone script
func XCTAssertEqual<T: Equatable>(_ expression1: T, _ expression2: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if expression1 != expression2 {
        NDKLogger.log(.error, category: .general, "❌ XCTAssertEqual failed: \(expression1) != \(expression2) - \(message)")
        fatalError("Test assertion failed at \(file):\(line)")
    }
}

func XCTAssertNotNil(_ expression: Any?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if expression == nil {
        NDKLogger.log(.error, category: .general, "❌ XCTAssertNotNil failed: value is nil - \(message)")
        fatalError("Test assertion failed at \(file):\(line)")
    }
}

func XCTAssertTrue(_ expression: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !expression {
        NDKLogger.log(.error, category: .general, "❌ XCTAssertTrue failed: expression is false - \(message)")
        fatalError("Test assertion failed at \(file):\(line)")
    }
}

func XCTAssertGreaterThan<T: Comparable>(_ expression1: T, _ expression2: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !(expression1 > expression2) {
        NDKLogger.log(.error, category: .general, "❌ XCTAssertGreaterThan failed: \(expression1) <= \(expression2) - \(message)")
        fatalError("Test assertion failed at \(file):\(line)")
    }
}

func XCTFail(_ message: String = "", file: StaticString = #file, line: UInt = #line) {
    NDKLogger.log(.error, category: .general, "❌ XCTFail: \(message)")
    fatalError("Test failed at \(file):\(line)")
}

// XCTestCase extension for standalone script
extension XCTestCase {
    override func setUp() async throws {
        // Default setup
    }
    
    override func tearDown() async throws {
        // Default teardown
    }
    
    func expectation(description: String) -> XCTestExpectation {
        return XCTestExpectation(description: description)
    }
    
    func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {
        // Simple implementation for standalone script
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    }
}

class XCTestCase {}

class XCTestExpectation {
    let description: String
    var isFulfilled = false
    
    init(description: String) {
        self.description = description
    }
    
    func fulfill() {
        isFulfilled = true
    }
}