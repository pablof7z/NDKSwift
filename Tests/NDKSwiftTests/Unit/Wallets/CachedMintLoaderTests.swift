import CashuSwift
import NDKSwiftCashu
@testable import NDKSwiftCore
import XCTest

final class CachedMintLoaderTests: XCTestCase {
    var cache: NDKNostrDBCache!
    var cachedLoader: CachedMintLoader!
    let testMintURL = URL(string: "https://test.mint.com")!

    override func setUp() async throws {
        try await super.setUp()
        cache = try await NDKTestFactory.createTestCache()
        cachedLoader = CachedMintLoader(
            cache: cache,
            mintInfoMaxAge: 3600,
            keysetMaxAge: 1800
        )
    }

    override func tearDown() async throws {
        cache = nil
        cachedLoader = nil
        try await super.tearDown()
    }

    func testLoadMintWithFreshCache() async throws {
        // Given
        let keysetJSON = """
        {
            "id": "test-keyset-1",
            "unit": "sat",
            "keys": {},
            "input_fee_ppk": 0
        }
        """
        let testKeyset = try JSONCoding.decode(CashuSwift.Keyset.self, from: keysetJSON)
        let testKeysets = [testKeyset]
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveKeysets(testKeysets, mintUrl: testMintURL.absoluteString)

        // When
        let mint = try await cachedLoader.loadMint(url: testMintURL)

        // Then
        XCTAssertEqual(mint.url, testMintURL)
        XCTAssertEqual(mint.keysets.count, 1)
    }

    func testLoadMintWithStaleCache() async throws {
        // Given
        let keysetJSON = """
        {
            "id": "old-keyset",
            "unit": "sat",
            "keys": {},
            "input_fee_ppk": 0
        }
        """
        let testKeyset = try JSONCoding.decode(CashuSwift.Keyset.self, from: keysetJSON)
        let oldKeysets = [testKeyset]
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveKeysets(oldKeysets, mintUrl: testMintURL.absoluteString)

        // Manually set last updated to 2 days ago via KV store manipulation
        let keysets = await cache.getValues(namespace: "cashu", keyPrefix: "keyset:\(testMintURL.absoluteString):")
        for (key, data) in keysets {
            if let wrapper = try? JSONDecoder().decode(KeysetWrapperForTest.self, from: data) {
                let updatedWrapper = KeysetWrapperForTest(
                    keyset: wrapper.keyset,
                    mintUrl: wrapper.mintUrl,
                    timestamp: Date().addingTimeInterval(-172_800)
                )
                if let newData = try? JSONEncoder().encode(updatedWrapper) {
                    try? await cache.setValue(newData, forKey: key, namespace: "cashu")
                }
            }
        }

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
        let keysetJSON = """
        {
            "id": "cached-keyset",
            "unit": "sat",
            "keys": {},
            "input_fee_ppk": 0
        }
        """
        let testKeyset = try JSONCoding.decode(CashuSwift.Keyset.self, from: keysetJSON)
        let cachedKeysets = [testKeyset]
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveKeysets(cachedKeysets, mintUrl: testMintURL.absoluteString)

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
            descriptionLong: nil,
            contact: nil,
            motd: nil,
            iconURL: nil,
            urls: nil,
            time: nil,
            tosURL: nil,
            nuts: NDKMintInfo.Nuts(
                nut04: NDKMintInfo.PaymentMethodList(
                    methods: [
                        NDKMintInfo.PaymentMethod(
                            method: "bolt11",
                            unit: "sat",
                            minAmount: nil,
                            maxAmount: nil
                        ),
                    ],
                    disabled: false
                ),
                nut05: nil,
                nut07: nil,
                nut08: nil,
                nut09: nil,
                nut10: nil,
                nut12: nil
            )
        )
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveMintInfo(testMintInfo, url: testMintURL.absoluteString)

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
            descriptionLong: nil,
            contact: nil,
            motd: nil,
            iconURL: nil,
            urls: nil,
            time: nil,
            tosURL: nil,
            nuts: nil
        )
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveMintInfo(oldMintInfo, url: testMintURL.absoluteString)

        // Set last updated to 8 days ago via KV store manipulation
        let key = "mint:\(testMintURL.absoluteString)"
        if let data = await cache.getValue(forKey: key, namespace: "cashu"),
           let wrapper = try? JSONDecoder().decode(MintInfoWrapperForTest.self, from: data)
        {
            let updatedWrapper = MintInfoWrapperForTest(info: wrapper.info, timestamp: Date().addingTimeInterval(-691_200))
            if let newData = try? JSONEncoder().encode(updatedWrapper) {
                try? await cache.setValue(newData, forKey: key, namespace: "cashu")
            }
        }

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
        let keysetJSON = """
        {
            "id": "test-keyset-123",
            "unit": "sat",
            "keys": {},
            "input_fee_ppk": 0
        }
        """
        let testKeyset = try JSONCoding.decode(CashuSwift.Keyset.self, from: keysetJSON)
        let helper = CashuCacheHelper(cache: cache)
        try await helper.saveKeyset(testKeyset, mintUrl: "mock://test-keyset-123")

        // When
        let keyset = await cachedLoader.getKeyset(id: "test-keyset-123")

        // Then
        XCTAssertNotNil(keyset)
    }

    func testGetKeysetByIdNotFound() async throws {
        // When
        let keyset = await cachedLoader.getKeyset(id: "non-existent")

        // Then
        XCTAssertNil(keyset)
    }
}

// MARK: - Wrapper Types for Testing

/// Mirror of CashuCacheHelper's MintInfoWrapper for testing
private struct MintInfoWrapperForTest: Codable {
    let info: NDKMintInfo
    let timestamp: Date
}

/// Mirror of CashuCacheHelper's KeysetWrapper for testing
private struct KeysetWrapperForTest: Codable {
    let keyset: CashuSwift.Keyset
    let mintUrl: String
    let timestamp: Date
}
