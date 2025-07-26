import XCTest
@testable import NDKSwift

final class NDKSignatureVerificationCacheTests: XCTestCase {
    
    func testInitialization() async {
        let cache = NDKSignatureVerificationCache(maxCacheSize: 100)
        let stats = await cache.getStats()
        XCTAssertEqual(stats.cacheSize, 0)
    }
    
    func testAddAndVerifySignature() async {
        let cache = NDKSignatureVerificationCache()
        let eventId = "test-event-id"
        let signature = "test-signature"
        
        // Initially not verified
        let isVerifiedBefore = await cache.isVerified(eventId: eventId, signature: signature)
        XCTAssertFalse(isVerifiedBefore)
        
        // Add signature
        await cache.addVerifiedSignature(eventId: eventId, signature: signature)
        
        // Now should be verified
        let isVerifiedAfter = await cache.isVerified(eventId: eventId, signature: signature)
        XCTAssertTrue(isVerifiedAfter)
        
        // Different signature should not be verified
        let isWrongSignatureVerified = await cache.isVerified(eventId: eventId, signature: "wrong-signature")
        XCTAssertFalse(isWrongSignatureVerified)
    }
    
    func testCacheSizeLimit() async {
        let maxSize = 3
        let cache = NDKSignatureVerificationCache(maxCacheSize: maxSize)
        
        // Add signatures up to max size
        for i in 0..<maxSize {
            await cache.addVerifiedSignature(eventId: "event-\(i)", signature: "sig-\(i)")
        }
        
        // Verify all are cached
        for i in 0..<maxSize {
            let isVerified = await cache.isVerified(eventId: "event-\(i)", signature: "sig-\(i)")
            XCTAssertTrue(isVerified)
        }
        
        // Add one more (should evict the oldest)
        await cache.addVerifiedSignature(eventId: "event-new", signature: "sig-new")
        
        // First should be evicted
        let isFirstVerified = await cache.isVerified(eventId: "event-0", signature: "sig-0")
        XCTAssertFalse(isFirstVerified)
        
        // Others should still be cached
        for i in 1..<maxSize {
            let isVerified = await cache.isVerified(eventId: "event-\(i)", signature: "sig-\(i)")
            XCTAssertTrue(isVerified)
        }
        
        // New one should be cached
        let isNewVerified = await cache.isVerified(eventId: "event-new", signature: "sig-new")
        XCTAssertTrue(isNewVerified)
    }
    
    func testLRUBehavior() async {
        let cache = NDKSignatureVerificationCache(maxCacheSize: 3)
        
        // Add three signatures
        await cache.addVerifiedSignature(eventId: "event-1", signature: "sig-1")
        await cache.addVerifiedSignature(eventId: "event-2", signature: "sig-2")
        await cache.addVerifiedSignature(eventId: "event-3", signature: "sig-3")
        
        // Access event-1 again (move to end)
        await cache.addVerifiedSignature(eventId: "event-1", signature: "sig-1")
        
        // Add new event (should evict event-2, not event-1)
        await cache.addVerifiedSignature(eventId: "event-4", signature: "sig-4")
        
        // Event-1 should still be cached
        let isEvent1Verified = await cache.isVerified(eventId: "event-1", signature: "sig-1")
        XCTAssertTrue(isEvent1Verified)
        
        // Event-2 should be evicted
        let isEvent2Verified = await cache.isVerified(eventId: "event-2", signature: "sig-2")
        XCTAssertFalse(isEvent2Verified)
        
        // Event-3 and event-4 should be cached
        let isEvent3Verified = await cache.isVerified(eventId: "event-3", signature: "sig-3")
        XCTAssertTrue(isEvent3Verified)
        let isEvent4Verified = await cache.isVerified(eventId: "event-4", signature: "sig-4")
        XCTAssertTrue(isEvent4Verified)
    }
    
    func testClearCache() async {
        let cache = NDKSignatureVerificationCache()
        
        // Add some signatures
        await cache.addVerifiedSignature(eventId: "event-1", signature: "sig-1")
        await cache.addVerifiedSignature(eventId: "event-2", signature: "sig-2")
        
        // Verify they are cached
        let isVerified1Before = await cache.isVerified(eventId: "event-1", signature: "sig-1")
        XCTAssertTrue(isVerified1Before)
        
        // Clear cache
        await cache.clear()
        
        // Verify they are no longer cached
        let isVerified1After = await cache.isVerified(eventId: "event-1", signature: "sig-1")
        XCTAssertFalse(isVerified1After)
        let isVerified2After = await cache.isVerified(eventId: "event-2", signature: "sig-2")
        XCTAssertFalse(isVerified2After)
        
        let stats = await cache.getStats()
        XCTAssertEqual(stats.cacheSize, 0)
    }
    
    func testConcurrentAccess() async {
        let cache = NDKSignatureVerificationCache()
        let iterations = 100
        
        // Concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    await cache.addVerifiedSignature(eventId: "event-\(i)", signature: "sig-\(i)")
                }
            }
        }
        
        // Concurrent reads
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    return await cache.isVerified(eventId: "event-\(i)", signature: "sig-\(i)")
                }
            }
            
            // All should be verified
            for await result in group {
                XCTAssertTrue(result)
            }
        }
    }
}