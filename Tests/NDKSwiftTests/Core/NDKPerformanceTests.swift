@testable import NDKSwift
import XCTest

final class NDKPerformanceTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
    }
    
    // MARK: - Event Processing Performance
    
    func testEventCreationPerformance() {
        measure {
            for i in 0..<1000 {
                let event = NDKEvent(
                    pubkey: "test_pubkey_\(i)",
                    createdAt: Timestamp(Date().timeIntervalSince1970),
                    kind: 1,
                    tags: [],
                    content: "Test message \(i)"
                )
                _ = event
            }
        }
    }
    
    func testEventIDGenerationPerformance() {
        let events = createTestEvents(count: 100)
        
        measure {
            for event in events {
                try? event.generateID()
            }
        }
    }
    
    func testEventSigningPerformance() async throws {
        let signer = try NDKPrivateKeySigner()
        let events = createTestEvents(count: 50) // Smaller count for signing
        
        // Generate IDs first
        for event in events {
            try? event.generateID()
        }
        
        measure {
            for event in events {
                let group = DispatchGroup()
                group.enter()
                
                Task {
                    do {
                        event.sig = try await signer.sign(event)
                    } catch {
                        // Handle signing error
                    }
                    group.leave()
                }
                
                group.wait()
            }
        }
    }
    
    // MARK: - Filter Performance
    
    func testFilterMatchingPerformance() {
        let filter = NDKFilter(
            authors: Array(0..<100).map { "author_\($0)" },
            kinds: [1, 6, 7],
            since: 1000,
            until: 2000
        )
        
        let events = createTestEvents(count: 1000)
        
        measure {
            var matchCount = 0
            for event in events {
                if filter.matches(event: event) {
                    matchCount += 1
                }
            }
            _ = matchCount
        }
    }
    
    func testComplexFilterPerformance() {
        let filter = NDKFilter()
        filter.addTagFilter("p", values: Array(0..<50).map { "pubkey_\($0)" })
        filter.addTagFilter("e", values: Array(0..<50).map { "event_\($0)" })
        
        let events = createTestEventsWithTags(count: 1000)
        
        measure {
            var matchCount = 0
            for event in events {
                if filter.matches(event: event) {
                    matchCount += 1
                }
            }
            _ = matchCount
        }
    }
    
    // MARK: - Cache Performance
    
    func testInMemoryCachePerformance() async {
        let cache = NDKInMemoryCache()
        let events = createTestEvents(count: 1000)
        
        // Test write performance
        await measureAsync {
            for event in events {
                await cache.setEvent(event, filters: [], relay: nil)
            }
        }
        
        // Test read performance
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        
        await measureAsync {
            let _ = await cache.query(subscription: subscription)
        }
    }
    
    func testFileCachePerformance() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ndk_perf_test")
        let cache = NDKFileCache(cacheDir: tempDir.path)
        let events = createTestEvents(count: 100) // Smaller count for file I/O
        
        // Test write performance
        await measureAsync {
            for event in events {
                await cache.setEvent(event, filters: [], relay: nil)
            }
        }
        
        // Test read performance
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        
        await measureAsync {
            let _ = await cache.query(subscription: subscription)
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Subscription Performance
    
    func testSubscriptionCreationPerformance() {
        let filters = Array(0..<100).map { i in
            NDKFilter(authors: ["author_\(i)"], kinds: [1])
        }
        
        measure {
            for filter in filters {
                let subscription = NDKSubscription(filters: [filter], ndk: ndk)
                _ = subscription
            }
        }
    }
    
    func testMassSubscriptionEventHandling() {
        let subscriptions = Array(0..<100).map { i in
            NDKSubscription(filters: [NDKFilter(authors: ["author_\(i)"], kinds: [1])], ndk: ndk)
        }
        
        let events = createTestEvents(count: 100)
        
        measure {
            for subscription in subscriptions {
                for event in events {
                    subscription.handleEvent(event, fromRelay: nil)
                }
            }
        }
    }
    
    // MARK: - Relay Management Performance
    
    func testRelayPoolPerformance() async {
        let relayUrls = Array(0..<50).map { "wss://relay\($0).test.com" }
        
        await measureAsync {
            for url in relayUrls {
                _ = await ndk.relayPool.addRelay(url: url)
            }
        }
        
        await measureAsync {
            for url in relayUrls {
                let _ = await ndk.relayPool.relay(for: url)
            }
        }
        
        await measureAsync {
            for url in relayUrls {
                await ndk.relayPool.removeRelay(url: url)
            }
        }
    }
    
    // MARK: - Cryptography Performance
    
    func testKeyDerivationPerformance() {
        measure {
            for _ in 0..<10 { // Small count for expensive crypto operations
                do {
                    _ = try NDKPrivateKeySigner()
                } catch {
                    // Handle error
                }
            }
        }
    }
    
    func testBech32EncodingPerformance() {
        let testStrings = Array(0..<1000).map { "test_string_\($0)_with_some_length" }
        
        measure {
            for string in testStrings {
                do {
                    _ = try Bech32.encode("test", string.data(using: .utf8) ?? Data())
                } catch {
                    // Handle encoding error
                }
            }
        }
    }
    
    func testBech32DecodingPerformance() {
        // Create test bech32 strings
        let testBech32Strings = Array(0..<1000).compactMap { i -> String? in
            let data = "test_data_\(i)".data(using: .utf8) ?? Data()
            return try? Bech32.encode("test", data)
        }
        
        measure {
            for bech32String in testBech32Strings {
                do {
                    _ = try Bech32.decode(bech32String)
                } catch {
                    // Handle decoding error
                }
            }
        }
    }
    
    // MARK: - Memory Usage Tests
    
    func testMemoryUsageWithManyEvents() {
        let initialMemory = getMemoryUsage()
        
        autoreleasepool {
            let events = createTestEvents(count: 10000)
            _ = events
        }
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory should be reasonable (less than 100MB for 10k events)
        XCTAssertLessThan(memoryIncrease, 100 * 1024 * 1024, "Memory usage too high")
    }
    
    func testMemoryUsageWithManySubscriptions() {
        let initialMemory = getMemoryUsage()
        
        autoreleasepool {
            let subscriptions = Array(0..<1000).map { i in
                NDKSubscription(filters: [NDKFilter(authors: ["author_\(i)"])], ndk: ndk)
            }
            _ = subscriptions
        }
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory should be reasonable (less than 50MB for 1k subscriptions)
        XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory usage too high")
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvents(count: Int) -> [NDKEvent] {
        return Array(0..<count).map { i in
            NDKEvent(
                pubkey: "test_pubkey_\(i % 100)", // Reuse some pubkeys
                createdAt: Timestamp(Date().timeIntervalSince1970) + Timestamp(i),
                kind: [1, 6, 7][i % 3], // Vary kinds
                tags: [],
                content: "Test message \(i)"
            )
        }
    }
    
    private func createTestEventsWithTags(count: Int) -> [NDKEvent] {
        return Array(0..<count).map { i in
            let tags: [[String]] = [
                ["p", "pubkey_\(i % 50)"],
                ["e", "event_\(i % 50)"],
                ["t", "tag_\(i % 20)"]
            ]
            
            return NDKEvent(
                pubkey: "test_pubkey_\(i % 100)",
                createdAt: Timestamp(Date().timeIntervalSince1970) + Timestamp(i),
                kind: 1,
                tags: tags,
                content: "Test message \(i)"
            )
        }
    }
    
    private func measureAsync(_ block: @escaping () async -> Void) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        await block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Print timing for manual verification
        print("Async operation took \(timeElapsed) seconds")
    }
    
    private func getMemoryUsage() -> Int64 {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(taskInfo.resident_size)
        } else {
            return 0
        }
    }
}