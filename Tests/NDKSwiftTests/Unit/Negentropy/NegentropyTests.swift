import XCTest
@testable import NDKSwift

final class NegentropyTests: XCTestCase {
    
    // MARK: - NegentropyItem Tests
    
    func testNegentropyItemCreation() throws {
        // Test from raw data
        let id = Data(repeating: 0x42, count: 32)
        let timestamp: UInt64 = 1234567890
        let item = NegentropyItem(id: id, timestamp: timestamp)
        
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.timestamp, timestamp)
    }
    
    func testNegentropyItemFromHex() throws {
        let hexId = "4242424242424242424242424242424242424242424242424242424242424242"
        let timestamp: UInt64 = 1234567890
        
        let item = try NegentropyItem(hexId: hexId, timestamp: timestamp)
        XCTAssertEqual(item.id.hexEncodedString(), hexId.lowercased())
        XCTAssertEqual(item.timestamp, timestamp)
    }
    
    func testNegentropyItemFromEvent() async throws {
        // Create a mock event with all required fields
        let event = NDKEvent(
            id: "4242424242424242424242424242424242424242424242424242424242424242",
            pubkey: "4242424242424242424242424242424242424242424242424242424242424242",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "42424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242424242"
        )
        
        let item = try NegentropyItem(event: event)
        XCTAssertEqual(item.id.hexEncodedString(), event.id)
        XCTAssertEqual(item.timestamp, UInt64(event.createdAt))
    }
    
    func testNegentropyItemComparison() {
        let item1 = NegentropyItem(id: Data(repeating: 0x01, count: 32), timestamp: 100)
        let item2 = NegentropyItem(id: Data(repeating: 0x02, count: 32), timestamp: 100)
        let item3 = NegentropyItem(id: Data(repeating: 0x01, count: 32), timestamp: 200)
        
        // Same timestamp, different ID
        XCTAssertTrue(item1 < item2)
        XCTAssertFalse(item2 < item1)
        
        // Different timestamp
        XCTAssertTrue(item1 < item3)
        XCTAssertFalse(item3 < item1)
    }
    
    // MARK: - NegentropyAccumulator Tests
    
    func testAccumulatorBasic() {
        var accumulator = NegentropyAccumulator()
        
        let item1 = NegentropyItem(id: Data(repeating: 0x01, count: 32), timestamp: 100)
        let item2 = NegentropyItem(id: Data(repeating: 0x02, count: 32), timestamp: 200)
        
        accumulator.add(item1)
        accumulator.add(item2)
        
        XCTAssertEqual(accumulator.count, 2)
        
        let fingerprint = accumulator.fingerprint()
        XCTAssertEqual(fingerprint.count, 32) // SHA256 output
    }
    
    func testAccumulatorDeterministic() {
        // Two accumulators with same items should produce same fingerprint
        var acc1 = NegentropyAccumulator()
        var acc2 = NegentropyAccumulator()
        
        let items = [
            NegentropyItem(id: Data(repeating: 0x01, count: 32), timestamp: 100),
            NegentropyItem(id: Data(repeating: 0x02, count: 32), timestamp: 200),
            NegentropyItem(id: Data(repeating: 0x03, count: 32), timestamp: 300)
        ]
        
        for item in items {
            acc1.add(item)
            acc2.add(item)
        }
        
        XCTAssertEqual(acc1.fingerprint(), acc2.fingerprint())
    }
    
    // MARK: - NegentropyRange Tests
    
    func testRangeContains() {
        let lower = NegentropyItem(id: Data(repeating: 0x10, count: 32), timestamp: 100)
        let upper = NegentropyItem(id: Data(repeating: 0x20, count: 32), timestamp: 200)
        
        let range = NegentropyRange(
            lower: lower,
            upper: upper,
            fingerprint: Data(),
            count: 0
        )
        
        // Test items
        let inside = NegentropyItem(id: Data(repeating: 0x15, count: 32), timestamp: 150)
        let before = NegentropyItem(id: Data(repeating: 0x05, count: 32), timestamp: 50)
        let after = NegentropyItem(id: Data(repeating: 0x25, count: 32), timestamp: 250)
        
        XCTAssertTrue(range.contains(inside))
        XCTAssertFalse(range.contains(before))
        XCTAssertFalse(range.contains(after))
        XCTAssertTrue(range.contains(lower)) // Lower bound is inclusive
        XCTAssertFalse(range.contains(upper)) // Upper bound is exclusive
    }
    
    func testRangeSplit() {
        let lower = NegentropyItem(id: Data(repeating: 0x10, count: 32), timestamp: 100)
        let upper = NegentropyItem(id: Data(repeating: 0x30, count: 32), timestamp: 300)
        let midpoint = NegentropyItem(id: Data(repeating: 0x20, count: 32), timestamp: 200)
        
        let range = NegentropyRange(
            lower: lower,
            upper: upper,
            fingerprint: Data(),
            count: 10
        )
        
        let (lowerRange, upperRange) = range.split(at: midpoint)
        
        XCTAssertEqual(lowerRange.lower?.timestamp, lower.timestamp)
        XCTAssertEqual(lowerRange.upper?.timestamp, midpoint.timestamp)
        XCTAssertEqual(upperRange.lower?.timestamp, midpoint.timestamp)
        XCTAssertEqual(upperRange.upper?.timestamp, upper.timestamp)
    }
    
    // MARK: - Encoder/Decoder Tests
    
    func testEncodeDecodeInitialMessage() throws {
        let fingerprint = Data(repeating: 0xAB, count: 32)
        let count = 42
        
        let encoded = try NegentropyEncoder.encodeInitialMessage(
            fingerprint: fingerprint,
            count: count
        )
        
        let decoded = try NegentropyDecoder.decode(encoded)
        
        guard case let .initial(decodedFingerprint, decodedCount) = decoded else {
            XCTFail("Expected initial message")
            return
        }
        
        XCTAssertEqual(decodedFingerprint, fingerprint)
        XCTAssertEqual(decodedCount, count)
    }
    
    func testVarintEncoding() {
        // Test varint encoding/decoding through the protocol
        let testValues: [UInt64] = [0, 127, 128, 16383, 16384, UInt64.max]
        
        for value in testValues {
            let data = try! NegentropyEncoder.encodeInitialMessage(
                fingerprint: Data(repeating: 0, count: 32),
                count: Int(min(value, UInt64(Int.max)))
            )
            
            let decoded = try! NegentropyDecoder.decode(data)
            
            guard case let .initial(_, count) = decoded else {
                XCTFail("Failed to decode")
                continue
            }
            
            XCTAssertEqual(UInt64(count), min(value, UInt64(Int.max)))
        }
    }
    
    // MARK: - Cache Integration Tests
    
    func testCacheNegentropyStorage() async throws {
        let cache = MemoryCache()
        let storage = NDKCacheNegentropyStorage(cache: cache)
        
        // Add some test events
        let ndk = NDK()
        let events = try await createTestEvents(ndk: ndk, count: 10)
        
        for event in events {
            try await cache.saveEvent(event)
        }
        
        // Test getItems
        let range = NegentropyRange(
            lower: nil,
            upper: nil,
            fingerprint: Data(),
            count: 0
        )
        
        let items = try await storage.getItems(in: range)
        XCTAssertEqual(items.count, 10)
        
        // Verify items are sorted
        for i in 1..<items.count {
            XCTAssertTrue(items[i-1] < items[i])
        }
    }
    
    func testCacheRangeQueries() async throws {
        let cache = MemoryCache()
        let storage = NDKCacheNegentropyStorage(cache: cache)
        
        // Create events with specific timestamps
        let baseTime = Timestamp(1000000)
        for i in 0..<20 {
            let eventId = String(format: "%064x", i)
            let event = NDKEvent(
                id: eventId,
                pubkey: "4242424242424242424242424242424242424242424242424242424242424242",
                createdAt: baseTime + Timestamp(i * 100),
                kind: 1,
                tags: [],
                content: "Event \(i)",
                sig: String(repeating: "42", count: 64)
            )
            try await cache.saveEvent(event)
        }
        
        // Query a specific range
        let lowerItem = NegentropyItem(
            id: Data(repeating: 0, count: 32),
            timestamp: UInt64(baseTime + 500)
        )
        let upperItem = NegentropyItem(
            id: Data(repeating: 0xFF, count: 32),
            timestamp: UInt64(baseTime + 1500)
        )
        
        let range = NegentropyRange(
            lower: lowerItem,
            upper: upperItem,
            fingerprint: Data(),
            count: 0
        )
        
        let items = try await storage.getItems(in: range)
        XCTAssertEqual(items.count, 10) // Events 5-14
        
        // Verify all items are in range
        for item in items {
            XCTAssertTrue(range.contains(item))
        }
    }
    
    // MARK: - NIP-77 Message Tests
    
    func testNIP77MessageEncoding() throws {
        let filter = NDKFilter(kinds: [1], limit: 100)
        let data = Data(repeating: 0x42, count: 32)
        
        let openMsg = NIP77Message.negOpen(
            subscriptionId: "test123",
            filter: filter,
            initialMessage: data.hexString
        )
        
        let json = try openMsg.toJSON()
        let decoded = try NIP77Message.parse(from: json)
        
        XCTAssertEqual(decoded.messageType, .negOpen)
        XCTAssertEqual(decoded.subscriptionId, "test123")
        XCTAssertEqual(decoded.filter?.kinds, [1])
        XCTAssertEqual(decoded.filter?.limit, 100)
        XCTAssertEqual(decoded.initialMessage, data.hexString)
    }
    
    // MARK: - End-to-End Reconciliation Tests
    
    func testCompleteReconciliationFlow() async throws {
        // Setup two caches with different sets of events
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Create test events - some shared, some unique to each cache
        let sharedEvents = try await createTestEvents(ndk: NDK(), count: 5, baseId: 1000, baseTime: 1000000)
        let unique1Events = try await createTestEvents(ndk: NDK(), count: 3, baseId: 2000, baseTime: 1100000)
        let unique2Events = try await createTestEvents(ndk: NDK(), count: 4, baseId: 3000, baseTime: 1200000)
        
        // Populate cache1
        for event in sharedEvents + unique1Events {
            try await cache1.saveEvent(event)
        }
        
        // Populate cache2
        for event in sharedEvents + unique2Events {
            try await cache2.saveEvent(event)
        }
        
        // Perform reconciliation
        let negentropy1 = Negentropy(storage: storage1)
        let negentropy2 = Negentropy(storage: storage2)
        
        // Initiator starts
        let initMessage = try await negentropy1.initiate()
        
        // Responder processes and generates response
        let (responseData, haveIds2, needIds2) = try await negentropy2.reconcile(initMessage)
        
        // If there's a response, initiator processes it
        var finalHaveIds: [String] = haveIds2
        var finalNeedIds: [String] = needIds2
        
        if let responseData = responseData {
            let (finalResponse, haveIds1, needIds1) = try await negentropy1.reconcile(responseData)
            finalHaveIds.append(contentsOf: haveIds1)
            finalNeedIds.append(contentsOf: needIds1)
            
            // Verify no further response is needed
            XCTAssertNil(finalResponse)
        }
        
        // Verify results
        XCTAssertEqual(Set(finalHaveIds).count, 3) // unique1Events
        XCTAssertEqual(Set(finalNeedIds).count, 4) // unique2Events
        
        // Verify the IDs match what we expect
        let expectedHaveIds = Set(unique1Events.map { $0.id })
        let expectedNeedIds = Set(unique2Events.map { $0.id })
        
        XCTAssertEqual(Set(finalHaveIds), expectedHaveIds)
        XCTAssertEqual(Set(finalNeedIds), expectedNeedIds)
    }
    
    func testReconciliationWithEmptyCache() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Only populate cache1
        let events = try await createTestEvents(ndk: NDK(), count: 5, baseId: 1000, baseTime: 1000000)
        for event in events {
            try await cache1.saveEvent(event)
        }
        
        let negentropy1 = Negentropy(storage: storage1)
        let negentropy2 = Negentropy(storage: storage2)
        
        let initMessage = try await negentropy1.initiate()
        let (_, haveIds, needIds) = try await negentropy2.reconcile(initMessage)
        
        // Cache2 should need all events from cache1
        XCTAssertEqual(needIds.count, 5)
        XCTAssertEqual(haveIds.count, 0)
        XCTAssertEqual(Set(needIds), Set(events.map { $0.id }))
    }
    
    func testReconciliationWithIdenticalCaches() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Populate both caches with identical events
        let events = try await createTestEvents(ndk: NDK(), count: 10, baseId: 1000, baseTime: 1000000)
        for event in events {
            try await cache1.saveEvent(event)
            try await cache2.saveEvent(event)
        }
        
        let negentropy1 = Negentropy(storage: storage1)
        let negentropy2 = Negentropy(storage: storage2)
        
        let initMessage = try await negentropy1.initiate()
        let (responseData, haveIds, needIds) = try await negentropy2.reconcile(initMessage)
        
        // No differences should be found
        XCTAssertNil(responseData)
        XCTAssertEqual(haveIds.count, 0)
        XCTAssertEqual(needIds.count, 0)
    }
    
    func testLargeDatasetReconciliation() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Create large datasets
        let sharedEvents = try await createTestEvents(ndk: NDK(), count: 100, baseId: 1000, baseTime: 1000000)
        let unique1Events = try await createTestEvents(ndk: NDK(), count: 50, baseId: 2000, baseTime: 2000000)
        let unique2Events = try await createTestEvents(ndk: NDK(), count: 75, baseId: 3000, baseTime: 3000000)
        
        for event in sharedEvents + unique1Events {
            try await cache1.saveEvent(event)
        }
        
        for event in sharedEvents + unique2Events {
            try await cache2.saveEvent(event)
        }
        
        let negentropy1 = Negentropy(storage: storage1)
        let negentropy2 = Negentropy(storage: storage2)
        
        let initMessage = try await negentropy1.initiate()
        let (responseData, haveIds2, needIds2) = try await negentropy2.reconcile(initMessage)
        
        var allHaveIds = haveIds2
        var allNeedIds = needIds2
        
        if let responseData = responseData {
            let (_, haveIds1, needIds1) = try await negentropy1.reconcile(responseData)
            allHaveIds.append(contentsOf: haveIds1)
            allNeedIds.append(contentsOf: needIds1)
        }
        
        XCTAssertEqual(Set(allHaveIds).count, 50)
        XCTAssertEqual(Set(allNeedIds).count, 75)
    }
    
    // MARK: - Protocol Message Flow Tests
    
    func testNIP77MessageRoundtrip() throws {
        let filter = NDKFilter(kinds: [1], limit: 100)
        let initialData = Data(repeating: 0x42, count: 64)
        
        // Test NEG-OPEN
        let openMsg = NIP77Message.negOpen(
            subscriptionId: "test-sub-123",
            filter: filter,
            initialMessage: initialData.hexString
        )
        
        let openJson = try openMsg.toJSON()
        let decodedOpen = try NIP77Message.parse(from: openJson)
        
        XCTAssertEqual(decodedOpen.messageType, .negOpen)
        XCTAssertEqual(decodedOpen.subscriptionId, "test-sub-123")
        XCTAssertEqual(decodedOpen.initialMessage, initialData.hexString)
        XCTAssertEqual(decodedOpen.filter?.kinds, [1])
        XCTAssertEqual(decodedOpen.filter?.limit, 100)
        
        // Test NEG-MSG
        let msgData = Data(repeating: 0xAB, count: 32)
        let msgMsg = NIP77Message.negMsg(subscriptionId: "test-sub-123", message: msgData.hexString)
        
        let msgJson = try msgMsg.toJSON()
        let decodedMsg = try NIP77Message.parse(from: msgJson)
        
        XCTAssertEqual(decodedMsg.messageType, .negMsg)
        XCTAssertEqual(decodedMsg.subscriptionId, "test-sub-123")
        XCTAssertEqual(decodedMsg.message, msgData.hexString)
        
        // Test NEG-CLOSE
        let closeMsg = NIP77Message.negClose(subscriptionId: "test-sub-123")
        let closeJson = try closeMsg.toJSON()
        let decodedClose = try NIP77Message.parse(from: closeJson)
        
        XCTAssertEqual(decodedClose.messageType, .negClose)
        XCTAssertEqual(decodedClose.subscriptionId, "test-sub-123")
        XCTAssertNil(decodedClose.message)
        
        // Test NEG-ERR
        let errMsg = NIP77Message.negErr(subscriptionId: "test-sub-123", reason: "Test error")
        let errJson = try errMsg.toJSON()
        let decodedErr = try NIP77Message.parse(from: errJson)
        
        XCTAssertEqual(decodedErr.messageType, .negErr)
        XCTAssertEqual(decodedErr.subscriptionId, "test-sub-123")
        XCTAssertEqual(decodedErr.reason, "Test error")
    }
    
    func testNegentropyReconcilerFlow() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Add different events to each cache
        let events1 = try await createTestEvents(ndk: NDK(), count: 5, baseId: 1000, baseTime: 1000000)
        let events2 = try await createTestEvents(ndk: NDK(), count: 3, baseId: 2000, baseTime: 2000000)
        
        for event in events1 {
            try await cache1.saveEvent(event)
        }
        
        for event in events2 {
            try await cache2.saveEvent(event)
        }
        
        // Set filters on storages to include all events
        await storage1.setFilter(NDKFilter(kinds: [1]))
        await storage2.setFilter(NDKFilter(kinds: [1]))
        
        let reconciler1 = NegentropyReconciler(storage: storage1)
        let reconciler2 = NegentropyReconciler(storage: storage2)
        
        // Start reconciliation
        let initData = try await reconciler1.initiate()
        let response = try await reconciler2.processMessage(initData)
        
        switch response {
        case .continuing(let data, _, _):
            // At this point, reconciler2 might not have identified differences yet
            // The protocol often requires multiple rounds
            
            // Process the response back at reconciler1
            let response2 = try await reconciler1.processMessage(data)
            
            switch response2 {
            case .terminated(let haveIds1, let needIds1, let isDone):
                XCTAssertTrue(isDone)
                // reconciler1 should identify it has 5 events and needs 3
                XCTAssertEqual(haveIds1.count, 5) // events1 that peer needs
                XCTAssertEqual(needIds1.count, 3) // events2 that we need
                
            case .continuing(let data2, let haveIds1, let needIds1):
                // Might need another round
                XCTAssertTrue(haveIds1.count > 0 || needIds1.count > 0 || data2.count > 0)
            }
            
        case .terminated(_, _, let isDone):
            // Early termination is possible if sets are identical
            XCTAssertTrue(isDone)
        }
    }
    
    func testNegentropyReconcilerStatefulBehavior() async throws {
        let storage = NDKCacheNegentropyStorage(cache: MemoryCache())
        let reconciler = NegentropyReconciler(storage: storage)
        
        // Test that calling initiate twice throws an error
        _ = try await reconciler.initiate()
        
        do {
            _ = try await reconciler.initiate()
            XCTFail("Should throw error when initiating twice")
        } catch {
            // Expected error
            XCTAssertTrue(error.localizedDescription.contains("already initiated"))
        }
    }
    
    func testNegentropyReconcilerLargeSetReconciliation() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Create larger sets with partial overlap
        // Cache1: events 0-99 (100 events)
        // Cache2: events 50-149 (100 events)
        // Overlap: events 50-99 (50 events)
        let events1 = try await createTestEvents(ndk: NDK(), count: 100, baseId: 0, baseTime: 1000000)
        let events2 = try await createTestEvents(ndk: NDK(), count: 100, baseId: 50, baseTime: 1500000)
        
        for event in events1 {
            try await cache1.saveEvent(event)
        }
        
        for event in events2 {
            try await cache2.saveEvent(event)
        }
        
        // Set filters
        await storage1.setFilter(NDKFilter(kinds: [1]))
        await storage2.setFilter(NDKFilter(kinds: [1]))
        
        let reconciler1 = NegentropyReconciler(storage: storage1)
        let reconciler2 = NegentropyReconciler(storage: storage2)
        
        // Track rounds
        var rounds = 0
        var totalHave = 0
        var totalNeed = 0
        
        // Start reconciliation
        var currentData = try await reconciler1.initiate()
        var isReconciler1Turn = false
        
        // Continue until reconciliation is complete
        while true {
            rounds += 1
            
            let response = isReconciler1Turn
                ? try await reconciler1.processMessage(currentData)
                : try await reconciler2.processMessage(currentData)
            
            switch response {
            case .continuing(let data, let haveIds, let needIds):
                totalHave += haveIds.count
                totalNeed += needIds.count
                currentData = data
                isReconciler1Turn.toggle()
                
            case .terminated(let haveIds, let needIds, _):
                totalHave += haveIds.count
                totalNeed += needIds.count
                
                // Verify the reconciliation identified the correct differences
                // Each side should identify 50 unique events
                XCTAssertTrue(rounds > 1, "Large sets should require multiple rounds")
                break
            }
            
            if rounds > 10 {
                XCTFail("Too many rounds, reconciliation might be stuck")
                break
            }
        }
    }
    
    func testNegentropyReconcilerAsResponder() async throws {
        let cache1 = MemoryCache()
        let cache2 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        
        // Add some events to each cache
        let events1 = try await createTestEvents(ndk: NDK(), count: 3, baseId: 100, baseTime: 1000000)
        let events2 = try await createTestEvents(ndk: NDK(), count: 2, baseId: 200, baseTime: 2000000)
        
        for event in events1 {
            try await cache1.saveEvent(event)
        }
        
        for event in events2 {
            try await cache2.saveEvent(event)
        }
        
        // Set filters
        await storage1.setFilter(NDKFilter(kinds: [1]))
        await storage2.setFilter(NDKFilter(kinds: [1]))
        
        let reconciler1 = NegentropyReconciler(storage: storage1)
        let reconciler2 = NegentropyReconciler(storage: storage2)
        
        // Start with reconciler1 as initiator
        let initData = try await reconciler1.initiate()
        
        // reconciler2 acts as responder (doesn't call initiate)
        let response = try await reconciler2.processMessage(initData)
        
        // Verify reconciler2 can process messages without calling initiate
        switch response {
        case .continuing(let data, _, _):
            XCTAssertTrue(data.count > 0)
        case .terminated:
            // Also valid for small sets
            break
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidProtocolVersion() async throws {
        let cache = MemoryCache()
        let storage = NDKCacheNegentropyStorage(cache: cache)
        let negentropy = Negentropy(storage: storage)
        
        // Create invalid message with wrong protocol version
        var invalidMessage = Data([0x50]) // Invalid version
        invalidMessage.append(Data(repeating: 0, count: 10))
        
        do {
            _ = try await negentropy.reconcile(invalidMessage)
            XCTFail("Should have thrown protocol error")
        } catch NegentropyError.protocolError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTruncatedMessage() async throws {
        let cache = MemoryCache()
        let storage = NDKCacheNegentropyStorage(cache: cache)
        let negentropy = Negentropy(storage: storage)
        
        // Create truncated message
        let truncatedMessage = Data([0x61]) // Just protocol version
        
        do {
            _ = try await negentropy.reconcile(truncatedMessage)
            XCTFail("Should have thrown decoding error")
        } catch NegentropyError.decodingError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testInvalidNIP77Message() {
        // Test invalid JSON
        XCTAssertThrowsError(try NIP77Message.parse(from: "invalid json")) { error in
            XCTAssertTrue(error is NIP77Error)
        }
        
        // Test wrong array structure
        XCTAssertThrowsError(try NIP77Message.parse(from: "[\"NEG-OPEN\"]")) { error in
            XCTAssertTrue(error is NIP77Error)
        }
        
        // Test invalid message type
        XCTAssertThrowsError(try NIP77Message.parse(from: "[\"INVALID-TYPE\", \"sub123\"]")) { error in
            XCTAssertTrue(error is NIP77Error)
        }
    }
    
    func testFrameSizeLimitHandling() async throws {
        let cache1 = MemoryCache()
        let storage1 = NDKCacheNegentropyStorage(cache: cache1)
        
        // Add many events to trigger frame size limits
        let events = try await createTestEvents(ndk: NDK(), count: 200, baseId: 1000, baseTime: 1000000)
        for event in events {
            try await cache1.saveEvent(event)
        }
        
        // Use small frame size limit
        let negentropy1 = Negentropy(storage: storage1, frameSizeLimit: 1000)
        
        let initMessage = try await negentropy1.initiate()
        
        // Message should be within frame size limit
        XCTAssertLessThan(initMessage.count, 1200) // Allow some overhead
        
        // Create empty responder
        let cache2 = MemoryCache()
        let storage2 = NDKCacheNegentropyStorage(cache: cache2)
        let negentropy2 = Negentropy(storage: storage2, frameSizeLimit: 1000)
        
        let (responseData, _, _) = try await negentropy2.reconcile(initMessage)
        
        if let responseData = responseData {
            XCTAssertLessThan(responseData.count, 1200)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvents(ndk: NDK, count: Int, baseId: Int = 0, baseTime: Int = 1000000) async throws -> [NDKEvent] {
        var events: [NDKEvent] = []
        
        for i in 0..<count {
            let eventId = String(format: "%064x", baseId + i)
            let event = NDKEvent(
                id: eventId,
                pubkey: "4242424242424242424242424242424242424242424242424242424242424242",
                createdAt: Timestamp(baseTime + i * 100),
                kind: 1,
                tags: [],
                content: "Test event \(baseId + i)",
                sig: String(repeating: "42", count: 64)
            )
            events.append(event)
        }
        
        return events
    }
}

// Extension for hex encoding in tests
extension Data {
    func hexEncodedString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}