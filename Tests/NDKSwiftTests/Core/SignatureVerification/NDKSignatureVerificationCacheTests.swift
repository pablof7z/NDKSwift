import XCTest
@testable import NDKSwift

final class NDKSignatureVerificationCacheTests: XCTestCase {
    
    func testCacheBasicOperations() async {
        let cache = NDKSignatureVerificationCache(maxCacheSize: 100)
        
        let eventId = "test_event_id"
        let signature = "test_signature"
        
        // Test empty cache
        let isVerified = await cache.isVerified(eventId: eventId, signature: signature)
        XCTAssertFalse(isVerified, "Empty cache should return false")
        
        // Add verified signature
        await cache.addVerifiedSignature(eventId: eventId, signature: signature)
        
        // Test cache hit
        let isVerifiedAfterAdd = await cache.isVerified(eventId: eventId, signature: signature)
        XCTAssertTrue(isVerifiedAfterAdd, "Cache should return true for verified signature")
        
        // Test different signature
        let isDifferentVerified = await cache.isVerified(eventId: eventId, signature: "different_signature")
        XCTAssertFalse(isDifferentVerified, "Cache should return false for different signature")
    }
    
    func testCacheLRUEviction() async {
        let cacheSize = 5
        let cache = NDKSignatureVerificationCache(maxCacheSize: cacheSize)
        
        // Fill cache beyond capacity
        for i in 0..<10 {
            let eventId = "event_\(i)"
            let signature = "signature_\(i)"
            await cache.addVerifiedSignature(eventId: eventId, signature: signature)
        }
        
        // First 5 events should be evicted
        for i in 0..<5 {
            let eventId = "event_\(i)"
            let signature = "signature_\(i)"
            let isVerified = await cache.isVerified(eventId: eventId, signature: signature)
            XCTAssertFalse(isVerified, "Event \(i) should have been evicted")
        }
        
        // Last 5 events should still be in cache
        for i in 5..<10 {
            let eventId = "event_\(i)"
            let signature = "signature_\(i)"
            let isVerified = await cache.isVerified(eventId: eventId, signature: signature)
            XCTAssertTrue(isVerified, "Event \(i) should still be in cache")
        }
    }
    
    func testCacheClear() async {
        let cache = NDKSignatureVerificationCache()
        
        // Add some signatures
        for i in 0..<5 {
            await cache.addVerifiedSignature(eventId: "event_\(i)", signature: "sig_\(i)")
        }
        
        // Verify they're cached
        let isVerifiedBeforeClear = await cache.isVerified(eventId: "event_0", signature: "sig_0")
        XCTAssertTrue(isVerifiedBeforeClear)
        
        // Clear cache
        await cache.clear()
        
        // Verify cache is empty
        let isVerifiedAfterClear = await cache.isVerified(eventId: "event_0", signature: "sig_0")
        XCTAssertFalse(isVerifiedAfterClear)
    }
    
    func testCacheDuplicateHandling() async {
        let cache = NDKSignatureVerificationCache(maxCacheSize: 3)
        
        // Add three items
        await cache.addVerifiedSignature(eventId: "event_1", signature: "sig_1")
        await cache.addVerifiedSignature(eventId: "event_2", signature: "sig_2")
        await cache.addVerifiedSignature(eventId: "event_3", signature: "sig_3")
        
        // Re-add the first item (should move it to end)
        await cache.addVerifiedSignature(eventId: "event_1", signature: "sig_1")
        
        // Add a new item (should evict event_2, not event_1)
        await cache.addVerifiedSignature(eventId: "event_4", signature: "sig_4")
        
        // Check what's in cache
        let isEvent1Cached = await cache.isVerified(eventId: "event_1", signature: "sig_1")
        let isEvent2Cached = await cache.isVerified(eventId: "event_2", signature: "sig_2")
        let isEvent3Cached = await cache.isVerified(eventId: "event_3", signature: "sig_3")
        let isEvent4Cached = await cache.isVerified(eventId: "event_4", signature: "sig_4")
        
        XCTAssertTrue(isEvent1Cached, "Event 1 should still be cached (was re-added)")
        XCTAssertFalse(isEvent2Cached, "Event 2 should have been evicted")
        XCTAssertTrue(isEvent3Cached, "Event 3 should still be cached")
        XCTAssertTrue(isEvent4Cached, "Event 4 should be cached")
    }
}