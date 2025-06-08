import XCTest
@testable import NDKSwift

final class ThreadSafeCollectionsTests: XCTestCase {
    
    func testEventCollectionThreadSafety() async throws {
        let collection = EventCollection()
        
        // Concurrent event additions
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<1000 {
                group.addTask {
                    let event = NDKEvent(
                        pubkey: "test",
                        createdAt: Timestamp(Date().timeIntervalSince1970),
                        kind: 1,
                        tags: [],
                        content: "Event \(i)"
                    )
                    event.id = "event_\(i)"
                    return await collection.addEvent(event)
                }
            }
            
            // Collect results
            var addedCount = 0
            for await wasAdded in group {
                if wasAdded {
                    addedCount += 1
                }
            }
            
            XCTAssertEqual(addedCount, 1000)
        }
        
        // Verify final state
        let events = await collection.getEvents()
        XCTAssertEqual(events.count, 1000)
    }
    
    func testEventCollectionDeduplication() async throws {
        let collection = EventCollection()
        
        let event = NDKEvent(
            pubkey: "test",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Duplicate test"
        )
        event.id = "duplicate_event"
        
        // Add the same event multiple times concurrently
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await collection.addEvent(event)
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // Only one should have succeeded
        let successCount = results.filter { $0 }.count
        XCTAssertEqual(successCount, 1)
        
        let events = await collection.getEvents()
        XCTAssertEqual(events.count, 1)
    }
    
    func testCallbackCollectionThreadSafety() async throws {
        let callbacks = CallbackCollection<(Int) -> Void>()
        
        // Add callbacks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await callbacks.add { value in
                        // Simulate some work
                        _ = value * i
                    }
                }
            }
        }
        
        let count = await callbacks.count()
        XCTAssertEqual(count, 100)
    }
    
    func testStateManagerConcurrentUpdates() async throws {
        struct TestState {
            var counter: Int = 0
            var flags: Set<String> = []
        }
        
        let stateManager = StateManager(TestState())
        
        // Concurrent updates
        await withTaskGroup(of: Void.self) { group in
            // Increment counter
            for _ in 0..<1000 {
                group.addTask {
                    await stateManager.update { state in
                        var newState = state
                        newState.counter += 1
                        return newState
                    }
                }
            }
            
            // Add flags
            for i in 0..<100 {
                group.addTask {
                    await stateManager.update { state in
                        var newState = state
                        newState.flags.insert("flag_\(i)")
                        return newState
                    }
                }
            }
        }
        
        // Verify final state
        let finalState = await stateManager.get()
        XCTAssertEqual(finalState.counter, 1000)
        XCTAssertEqual(finalState.flags.count, 100)
    }
    
    func testPerformanceComparison() async throws {
        // Test actor-based performance
        let actorStart = Date()
        let collection = EventCollection()
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10000 {
                group.addTask {
                    let event = NDKEvent(
                        pubkey: "test",
                        createdAt: Timestamp(Date().timeIntervalSince1970),
                        kind: 1,
                        tags: [],
                        content: "Event \(i)"
                    )
                    event.id = "perf_\(i)"
                    _ = await collection.addEvent(event)
                }
            }
        }
        
        let actorDuration = Date().timeIntervalSince(actorStart)
        
        // Test NSLock-based performance (simplified)
        let lockStart = Date()
        let lock = NSLock()
        var lockedEvents: [NDKEvent] = []
        var lockedIds: Set<String> = []
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10000 {
                group.addTask {
                    let event = NDKEvent(
                        pubkey: "test",
                        createdAt: Timestamp(Date().timeIntervalSince1970),
                        kind: 1,
                        tags: [],
                        content: "Event \(i)"
                    )
                    event.id = "perf_lock_\(i)"
                    
                    lock.lock()
                    defer { lock.unlock() }
                    
                    if let id = event.id, !lockedIds.contains(id) {
                        lockedIds.insert(id)
                        lockedEvents.append(event)
                    }
                }
            }
        }
        
        let lockDuration = Date().timeIntervalSince(lockStart)
        
        print("Actor-based: \(actorDuration)s")
        print("Lock-based: \(lockDuration)s")
        
        // Actors should be competitive or faster
        XCTAssertLessThan(actorDuration, lockDuration * 1.5)
    }
}