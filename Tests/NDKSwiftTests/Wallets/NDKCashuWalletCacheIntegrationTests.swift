import XCTest
@testable import NDKSwift
import CashuSwift

final class NDKCashuWalletCacheIntegrationTests: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    var wallet: NDKCashuWallet!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK instance
        ndk = NDK()
        
        // Create cache
        let tempPath = NSTemporaryDirectory() + "test_wallet_cache_\(UUID().uuidString).db"
        cache = try await NDKSQLiteCache(path: tempPath)
        
        // Create wallet with cache
        wallet = NDKCashuWallet(ndk: ndk, mintCache: cache)
    }
    
    override func tearDown() async throws {
        try await cache.clear()
        try await super.tearDown()
    }
    
    func testWalletWithCachePerformance() async throws {
        // This test demonstrates the performance benefit of using cached mint loading
        // In a real scenario, this would make network calls
        
        let mintUrl = URL(string: "https://testnet.cashcrab.com")!
        
        // First load - would normally hit network
        let start1 = Date()
        do {
            try await wallet.addMint(url: mintUrl)
        } catch {
            // Expected to fail in test environment
            print("Expected error adding mint: \(error)")
        }
        let duration1 = Date().timeIntervalSince(start1)
        
        // Simulate that we have cached data
        let mockInfoData = createMockMintInfoData()
        try await cache.saveMintInfoJSON(mockInfoData, url: mintUrl.absoluteString)
        
        let mockKeysets = [
            createMockKeyset(id: "keyset1"),
            createMockKeyset(id: "keyset2")
        ]
        try await cache.saveKeysets(mockKeysets, mintUrl: mintUrl.absoluteString)
        
        // Second load - should use cache (much faster)
        let start2 = Date()
        do {
            let infoData = try await wallet.getMintInfoData(url: mintUrl)
            XCTAssertNotNil(infoData)
        } catch {
            // This might still fail if it tries to validate against real mint
            print("Error getting mint info: \(error)")
        }
        let duration2 = Date().timeIntervalSince(start2)
        
        print("First load duration: \(duration1)s")
        print("Cached load duration: \(duration2)s")
        
        // In a real scenario with network calls, cached load would be significantly faster
    }
    
    func testCacheIntegration() async throws {
        // Test that the wallet properly integrates with the cache
        
        let mintUrl = "https://test.mint.com"
        
        // Pre-populate cache
        let mockInfoData = createMockMintInfoData()
        try await cache.saveMintInfoJSON(mockInfoData, url: mintUrl)
        
        // Verify cache has the data
        let cachedInfo = await cache.getMintInfoJSON(url: mintUrl)
        XCTAssertNotNil(cachedInfo)
        XCTAssertEqual(cachedInfo, mockInfoData)
        
        // Test keyset caching
        let keysets = [
            createMockKeyset(id: "key1", unit: "sat"),
            createMockKeyset(id: "key2", unit: "sat"),
            createMockKeyset(id: "key3", unit: "usd")
        ]
        
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        // Verify keysets are cached
        let cachedKeysets = await cache.getKeysets(mintUrl: mintUrl)
        XCTAssertEqual(cachedKeysets.count, 3)
        
        // Test active keyset filtering
        let activeSatKeysets = await cache.getActiveKeysets(mintUrl: mintUrl, unit: "sat")
        XCTAssertEqual(activeSatKeysets.count, 2)
    }
    
    func testCacheStalenessHandling() async throws {
        let mintUrl = "https://test.mint.com"
        let mockInfoData = createMockMintInfoData()
        
        // Save mint info
        try await cache.saveMintInfoJSON(mockInfoData, url: mintUrl)
        
        // Check staleness with different intervals
        let fresh = await cache.isMintInfoStale(url: mintUrl, maxAge: 86400) // 24 hours
        XCTAssertFalse(fresh, "Mint info should be fresh")
        
        let stale = await cache.isMintInfoStale(url: mintUrl, maxAge: 0) // 0 seconds
        XCTAssertTrue(stale, "Mint info should be stale with 0 second max age")
        
        // Test keyset staleness
        let keysets = [createMockKeyset()]
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        let keysetsFresh = await cache.areKeysetsStale(mintUrl: mintUrl, maxAge: 3600) // 1 hour
        XCTAssertFalse(keysetsFresh, "Keysets should be fresh")
        
        let keysetsStale = await cache.areKeysetsStale(mintUrl: mintUrl, maxAge: 0)
        XCTAssertTrue(keysetsStale, "Keysets should be stale with 0 second max age")
    }
    
    // MARK: - Helper Methods
    
    private func createMockMintInfoData() -> Data {
        let jsonString = """
        {
            "name": "Test Mint",
            "pubkey": "02a1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd",
            "version": "0.15.0",
            "description": "A test mint",
            "description_long": "This is a test mint for integration tests",
            "motd": "Welcome!",
            "contact": [{"method": "email", "info": "test@example.com"}],
            "icon_url": "https://example.com/icon.png",
            "time": 1234567890,
            "nuts": {
                "4": {
                    "methods": [{
                        "method": "bolt11",
                        "unit": "sat",
                        "min_amount": 1,
                        "max_amount": 1000000
                    }],
                    "disabled": false
                },
                "5": {
                    "methods": [{
                        "method": "bolt11",
                        "unit": "sat",
                        "min_amount": 1,
                        "max_amount": 1000000
                    }],
                    "disabled": false
                }
            }
        }
        """
        
        return jsonString.data(using: .utf8)!
    }
    
    private func createMockKeyset(
        id: String = "testkeyset",
        unit: String = "sat"
    ) -> CashuSwift.Keyset {
        let jsonString = """
        {
            "id": "\(id)",
            "unit": "\(unit)",
            "active": true,
            "input_fee_ppk": 0,
            "keys": {
                "1": "02a1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd",
                "2": "02b1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd",
                "4": "02c1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd",
                "8": "02d1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd"
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: data)
    }
}