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

class MockNDKCache: NDKCache {
    var mockKeysets: [String: [CashuSwift.Keyset]] = [:]
    var mockKeysetsLastUpdated: [String: Date] = [:]
    var mockKeysetsById: [String: CashuSwift.Keyset] = [:]
    var mockMintInfo: [String: NDKMintInfo] = [:]
    var mockMintInfoLastUpdated: [String: Date] = [:]
    
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
    
    // Required NDKCache protocol methods
    func save(event: NDKEvent) async throws {}
    func save(events: [NDKEvent]) async throws {}
    func saveProfile(_ profile: NDKUserProfile, for pubkey: PublicKey) async throws {}
    func loadEvents(filter: NDKFilter) async throws -> [NDKEvent] { [] }
    func loadProfile(pubkey: PublicKey) async -> NDKUserProfile? { nil }
    func deleteEvent(_ event: NDKEvent) async throws {}
    func deleteEvents(filter: NDKFilter) async throws {}
    func hasEvent(id: String) async -> Bool { false }
    func addObserver(_ observer: any NDKCacheObserver) {}
    func removeObserver(_ observer: any NDKCacheObserver) {}
    func loadAllKind0Events() async throws -> [NDKEvent] { [] }
    func replaceProofs(_ proofs: [CashuSwift.Proof], for mint: String) async throws {}
    func appendProof(_ proof: CashuSwift.Proof, for mint: String) async throws {}
    func loadProofs(for mint: String) async throws -> [CashuSwift.Proof] { [] }
    func invalidateProof(_ proof: CashuSwift.Proof, for mint: String) async throws {}
    func restoreValidProof(_ proof: CashuSwift.Proof, for mint: String) async throws {}
    func saveSpentProof(_ proofInfo: SpentProofInfo) async throws {}
    func loadSpentProofs(for mint: String) async throws -> [SpentProofInfo] { [] }
    func saveMintQuote(_ quote: CashuMintQuote) async throws {}
    func loadMintQuotes(for mint: String, state: MintQuoteState?) async throws -> [CashuMintQuote] { [] }
    func updateMintQuoteState(quoteId: String, state: MintQuoteState) async throws {}
    func saveMeltQuote(_ quote: CashuMeltQuote) async throws {}
    func loadMeltQuotes(for mint: String, state: MeltQuoteState?) async throws -> [CashuMeltQuote] { [] }
    func updateMeltQuoteState(quoteId: String, state: MeltQuoteState) async throws {}
    func loadAllMintURLs() async -> Set<String> { [] }
    func loadAllActiveKeysets() async -> [CashuSwift.Keyset] { [] }
    func saveKeysetActivation(keysetId: String, mintUrl: String, activatedAt: Date) async throws {}
}