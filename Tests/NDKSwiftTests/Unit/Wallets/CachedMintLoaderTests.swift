import XCTest
@testable import NDKSwift
import CashuSwift

final class CachedMintLoaderTests: XCTestCase {
    var mockCache: MockNDKCache!
    var cachedLoader: CachedMintLoader!
    let testMintURL = URL(string: "https://test.mint.com")!
    
    override func setUp() async throws {
        try await super.setUp()
        mockCache = MockNDKCache()
        cachedLoader = CachedMintLoader(
            cache: mockCache,
            mintInfoMaxAge: 3600,
            keysetMaxAge: 1800
        )
    }
    
    override func tearDown() async throws {
        mockCache = nil
        cachedLoader = nil
        try await super.tearDown()
    }
    
    func testLoadMintWithFreshCache() async throws {
        // Given
        let testKeysets = [
            CashuSwift.Keyset(
                id: "test-keyset-1",
                unit: "sat",
                keys: [:],
                inputFeePpk: 0
            )
        ]
        mockCache.mockKeysets[testMintURL.absoluteString] = testKeysets
        mockCache.mockKeysetsLastUpdated[testMintURL.absoluteString] = Date()
        
        // When
        let mint = try await cachedLoader.loadMint(url: testMintURL)
        
        // Then
        XCTAssertEqual(mint.url, testMintURL)
        XCTAssertEqual(mint.keysets.count, 1)
        XCTAssertEqual(mint.keysets.first?.id, "test-keyset-1")
    }
    
    func testLoadMintWithStaleCache() async throws {
        // Given
        let oldKeysets = [
            CashuSwift.Keyset(
                id: "old-keyset",
                unit: "sat",
                keys: [:],
                inputFeePpk: 0
            )
        ]
        mockCache.mockKeysets[testMintURL.absoluteString] = oldKeysets
        // Set last updated to 2 days ago (beyond keyset max age)
        mockCache.mockKeysetsLastUpdated[testMintURL.absoluteString] = Date().addingTimeInterval(-172800)
        
        // When/Then - should throw because network call would fail in test
        do {
            _ = try await cachedLoader.loadMint(url: testMintURL)
            XCTFail("Expected error when loading mint with stale cache")
        } catch {
            // Expected - network call fails in test environment
        }
    }
    
    func testLoadMintWithForceRefresh() async throws {
        // Given
        let cachedKeysets = [
            CashuSwift.Keyset(
                id: "cached-keyset",
                unit: "sat",
                keys: [:],
                inputFeePpk: 0
            )
        ]
        mockCache.mockKeysets[testMintURL.absoluteString] = cachedKeysets
        mockCache.mockKeysetsLastUpdated[testMintURL.absoluteString] = Date()
        
        // When/Then - should throw because network call would fail in test
        do {
            _ = try await cachedLoader.loadMint(url: testMintURL, forceRefresh: true)
            XCTFail("Expected error when force refreshing")
        } catch {
            // Expected - network call fails in test environment
        }
    }
    
    func testLoadMintInfoWithFreshCache() async throws {
        // Given
        let testMintInfo = NDKMintInfo(
            name: "Test Mint",
            pubkey: "test-pubkey",
            version: "1.0",
            description: "Test mint description",
            nuts: ["4": ["methods": [["method": "bolt11", "unit": "sat"]]]]
        )
        mockCache.mockMintInfo[testMintURL.absoluteString] = testMintInfo
        mockCache.mockMintInfoLastUpdated[testMintURL.absoluteString] = Date()
        
        // When
        let mintInfo = try await cachedLoader.loadMintInfo(url: testMintURL)
        
        // Then
        XCTAssertEqual(mintInfo.name, "Test Mint")
        XCTAssertEqual(mintInfo.pubkey, "test-pubkey")
        XCTAssertEqual(mintInfo.version, "1.0")
    }
    
    func testLoadMintInfoWithStaleCache() async throws {
        // Given
        let oldMintInfo = NDKMintInfo(
            name: "Old Mint",
            pubkey: "old-pubkey",
            version: "0.1",
            description: "Old mint description",
            nuts: [:]
        )
        mockCache.mockMintInfo[testMintURL.absoluteString] = oldMintInfo
        // Set last updated to 8 days ago (beyond mint info max age)
        mockCache.mockMintInfoLastUpdated[testMintURL.absoluteString] = Date().addingTimeInterval(-691200)
        
        // When/Then - should throw because network call would fail in test
        do {
            _ = try await cachedLoader.loadMintInfo(url: testMintURL)
            XCTFail("Expected error when loading mint info with stale cache")
        } catch {
            // Expected - network call fails in test environment
        }
    }
    
    func testGetKeysetById() async throws {
        // Given
        let testKeyset = CashuSwift.Keyset(
            id: "test-keyset-123",
            unit: "sat",
            keys: [:],
            inputFeePpk: 0
        )
        mockCache.mockKeysetsById["test-keyset-123"] = testKeyset
        
        // When
        let keyset = await cachedLoader.getKeyset(id: "test-keyset-123")
        
        // Then
        XCTAssertNotNil(keyset)
        XCTAssertEqual(keyset?.id, "test-keyset-123")
    }
    
    func testGetKeysetByIdNotFound() async throws {
        // When
        let keyset = await cachedLoader.getKeyset(id: "non-existent")
        
        // Then
        XCTAssertNil(keyset)
    }
}

// MARK: - Mock NDKCache for Testing

actor MockNDKCache: NDKCache {
    var mockKeysets: [String: [CashuSwift.Keyset]] = [:]
    var mockKeysetsLastUpdated: [String: Date] = [:]
    var mockKeysetsById: [String: CashuSwift.Keyset] = [:]
    var mockMintInfo: [String: NDKMintInfo] = [:]
    var mockMintInfoLastUpdated: [String: Date] = [:]
    
    // MARK: - NDKCache Protocol Implementation
    
    // Event operations
    func saveEvent(_ event: NDKEvent) async throws {}
    func getEvent(id: String) async -> NDKEvent? { nil }
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] { [] }
    func deleteEvent(id: String) async throws {}
    
    // Profile operations
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {}
    func getProfile(pubkey: String) async -> NDKUserProfile? { nil }
    
    // Cache management
    func clear() async throws {}
    
    // Mint cache operations - custom implementation for testing
    func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        return mockKeysets[mintUrl] ?? []
    }
    
    func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        guard let lastUpdated = mockKeysetsLastUpdated[mintUrl] else {
            return true
        }
        return Date().timeIntervalSince(lastUpdated) > maxAge
    }
    
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        mockKeysets[mintUrl] = keysets
        mockKeysetsLastUpdated[mintUrl] = Date()
        for keyset in keysets {
            mockKeysetsById[keyset.id] = keyset
        }
    }
    
    func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return mockKeysetsById[id]
    }
    
    func getMintInfo(url: String) async -> NDKMintInfo? {
        return mockMintInfo[url]
    }
    
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let lastUpdated = mockMintInfoLastUpdated[url] else {
            return true
        }
        return Date().timeIntervalSince(lastUpdated) > maxAge
    }
    
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mockMintInfo[url] = info
        mockMintInfoLastUpdated[url] = Date()
    }
    
    func invalidateMintCache(url: String) async throws {
        mockKeysets.removeValue(forKey: url)
        mockKeysetsLastUpdated.removeValue(forKey: url)
        mockMintInfo.removeValue(forKey: url)
        mockMintInfoLastUpdated.removeValue(forKey: url)
    }
    
    // Other required methods with default implementation
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {}
    func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] { [] }
}