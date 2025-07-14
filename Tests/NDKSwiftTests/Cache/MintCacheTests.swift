import XCTest
@testable import NDKSwift
import CashuSwift

final class MintCacheTests: XCTestCase {
    var cache: NDKSQLiteCache!
    var inMemoryCache: InMemoryMintCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create SQLite cache with temporary database
        let tempPath = NSTemporaryDirectory() + "test_mint_cache_\(UUID().uuidString).db"
        cache = try await NDKSQLiteCache(path: tempPath)
        
        // Create in-memory cache
        inMemoryCache = InMemoryMintCache()
    }
    
    override func tearDown() async throws {
        try await cache.clear()
        try await super.tearDown()
    }
    
    // MARK: - Mint Info Tests
    
    func testSaveAndRetrieveMintInfo() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        
        // Test SQLite cache
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        let retrieved = await cache.getMintInfo(url: mintUrl)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, mintInfo.name)
        XCTAssertEqual(retrieved?.pubkey, mintInfo.pubkey)
        XCTAssertEqual(retrieved?.version, mintInfo.version)
    }
    
    func testMintInfoStaleness() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        
        // Save mint info
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        // Should not be stale immediately
        let isStale = await cache.isMintInfoStale(url: mintUrl, maxAge: 3600) // 1 hour
        XCTAssertFalse(isStale)
        
        // Should be stale with negative max age
        let isStaleNegative = await cache.isMintInfoStale(url: mintUrl, maxAge: -1)
        XCTAssertTrue(isStaleNegative)
    }
    
    // MARK: - Keyset Tests
    
    func testSaveAndRetrieveKeyset() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        let keyset = createTestKeyset()
        
        // Save mint info first (required by foreign key constraint)
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        // Save keyset
        try await cache.saveKeyset(keyset, mintUrl: mintUrl)
        
        // Retrieve by ID
        let retrieved = await cache.getKeyset(id: keyset.keysetID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.keysetID, keyset.keysetID)
        XCTAssertEqual(retrieved?.unit, keyset.unit)
        XCTAssertEqual(retrieved?.active, keyset.active)
    }
    
    func testBatchSaveKeysets() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        let keysets = [
            createTestKeyset(id: "keyset1"),
            createTestKeyset(id: "keyset2"),
            createTestKeyset(id: "keyset3")
        ]
        
        // Save mint info first (required by foreign key constraint)
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        // Batch save
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        // Retrieve all
        let retrieved = await cache.getKeysets(mintUrl: mintUrl)
        XCTAssertEqual(retrieved.count, 3)
        XCTAssertTrue(retrieved.contains { $0.keysetID == "keyset1" })
        XCTAssertTrue(retrieved.contains { $0.keysetID == "keyset2" })
        XCTAssertTrue(retrieved.contains { $0.keysetID == "keyset3" })
    }
    
    func testGetActiveKeysets() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        let keysets = [
            createTestKeyset(id: "active1", unit: "sat", active: true),
            createTestKeyset(id: "active2", unit: "sat", active: true),
            createTestKeyset(id: "inactive", unit: "sat", active: false),
            createTestKeyset(id: "usd", unit: "usd", active: true)
        ]
        
        // Save mint info first (required by foreign key constraint)
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        // Get active sat keysets
        let activeSat = await cache.getActiveKeysets(mintUrl: mintUrl, unit: "sat")
        XCTAssertEqual(activeSat.count, 2)
        XCTAssertTrue(activeSat.allSatisfy { $0.unit == "sat" && $0.active })
        
        // Get active usd keysets
        let activeUsd = await cache.getActiveKeysets(mintUrl: mintUrl, unit: "usd")
        XCTAssertEqual(activeUsd.count, 1)
        XCTAssertEqual(activeUsd.first?.keysetID, "usd")
    }
    
    func testKeysetsStaleness() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        let keysets = [createTestKeyset()]
        
        // Save mint info first (required by foreign key constraint)
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        // Should not be stale immediately
        let isStale = await cache.areKeysetsStale(mintUrl: mintUrl, maxAge: 3600)
        XCTAssertFalse(isStale)
        
        // Should be stale with negative max age
        let isStaleNegative = await cache.areKeysetsStale(mintUrl: mintUrl, maxAge: -1)
        XCTAssertTrue(isStaleNegative)
    }
    
    // MARK: - Cached Mint Loader Tests
    
    func testCachedMintLoader() async throws {
        let loader = CachedMintLoader(
            cache: inMemoryCache,
            mintInfoMaxAge: 3600,
            keysetMaxAge: 1800
        )
        
        // Mock mint info
        let mintUrl = URL(string: "https://test.mint.com")!
        let mintInfo = createTestMintInfo()
        try await inMemoryCache.saveMintInfo(mintInfo, url: mintUrl.absoluteString)
        
        // Load should return cached version
        let loadedInfo = try await loader.loadMintInfo(url: mintUrl)
        XCTAssertNotNil(loadedInfo)
        XCTAssertEqual(loadedInfo.name, mintInfo.name)
    }
    
    // MARK: - Mint Management Tests
    
    func testGetCachedMintUrls() async throws {
        let urls = [
            "https://mint1.com",
            "https://mint2.com",
            "https://mint3.com"
        ]
        
        for url in urls {
            let info = createTestMintInfo(name: "Mint at \(url)")
            try await cache.saveMintInfo(info, url: url)
        }
        
        let cachedUrls = await cache.getCachedMintUrls()
        XCTAssertEqual(cachedUrls.count, 3)
        XCTAssertEqual(Set(cachedUrls), Set(urls))
    }
    
    func testDeleteMint() async throws {
        let mintUrl = "https://test.mint.com"
        let mintInfo = createTestMintInfo()
        let keysets = [
            createTestKeyset(id: "keyset1"),
            createTestKeyset(id: "keyset2")
        ]
        
        // Save mint and keysets
        try await cache.saveMintInfo(mintInfo, url: mintUrl)
        try await cache.saveKeysets(keysets, mintUrl: mintUrl)
        
        // Verify they exist
        let cachedMintInfo = await cache.getMintInfo(url: mintUrl)
        XCTAssertNotNil(cachedMintInfo)
        let cachedKeysets = await cache.getKeysets(mintUrl: mintUrl)
        XCTAssertEqual(cachedKeysets.count, 2)
        
        // Delete mint
        try await cache.deleteMint(url: mintUrl)
        
        // Verify mint and keysets are gone
        let deletedMintInfo = await cache.getMintInfo(url: mintUrl)
        XCTAssertNil(deletedMintInfo)
        let deletedKeysets = await cache.getKeysets(mintUrl: mintUrl)
        XCTAssertEqual(deletedKeysets.count, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestMintInfoData() -> Data {
        let jsonString = """
        {
            "name": "Test Mint",
            "pubkey": "02testpubkey",
            "version": "0.15.0",
            "description": "Test mint",
            "description_long": "This is a test mint for unit tests",
            "motd": "Welcome to test mint",
            "contact": [{"method": "email", "info": "test@mint.com"}],
            "nuts": {
                "4": {"methods": [{"method": "bolt11", "unit": "sat", "min_amount": 1, "max_amount": 1000000}], "disabled": false},
                "5": {"methods": [{"method": "bolt11", "unit": "sat", "min_amount": 1, "max_amount": 1000000}], "disabled": false}
            }
        }
        """
        
        return jsonString.data(using: .utf8)!
    }
    
    private func createTestMintInfo(name: String = "Test Mint") -> NDKMintInfo {
        let contact = NDKMintInfo.Contact(method: "email", info: "test@mint.com")
        let paymentMethod = NDKMintInfo.PaymentMethod(
            method: "bolt11",
            unit: "sat",
            minAmount: 1,
            maxAmount: 1000000
        )
        let paymentMethodList = NDKMintInfo.PaymentMethodList(
            methods: [paymentMethod],
            disabled: false
        )
        let nuts = NDKMintInfo.Nuts(
            nut04: paymentMethodList,
            nut05: paymentMethodList,
            nut07: nil,
            nut08: nil,
            nut09: nil,
            nut10: nil,
            nut12: nil
        )
        
        return NDKMintInfo(
            name: name,
            pubkey: "02testpubkey",
            version: "0.15.0",
            description: "Test mint",
            descriptionLong: "This is a test mint for unit tests",
            contact: [contact],
            motd: "Welcome to test mint",
            iconUrl: nil,
            urls: nil,
            time: nil,
            tosUrl: nil,
            nuts: nuts
        )
    }
    
    private func createTestKeyset(
        id: String = "testkeyset",
        unit: String = "sat",
        active: Bool = true
    ) -> CashuSwift.Keyset {
        // Create a mock Keyset
        let jsonString = """
        {
            "id": "\(id)",
            "unit": "\(unit)",
            "active": \(active),
            "input_fee_ppk": 0,
            "keys": {
                "1": "02a1234567890abcdef",
                "2": "02b1234567890abcdef",
                "4": "02c1234567890abcdef"
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: data)
    }
}