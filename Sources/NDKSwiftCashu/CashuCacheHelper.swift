import Foundation
import CashuSwift
import NDKSwiftCore

/// Helper for storing Cashu-related data in NDKCache's generic KV store
public struct CashuCacheHelper: Sendable {
    private let cache: NDKCache
    private let namespace = "cashu"

    public init(cache: NDKCache) {
        self.cache = cache
    }

    // MARK: - Mint Info

    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        let wrapper = MintInfoWrapper(info: info, timestamp: Date())
        let data = try JSONEncoder().encode(wrapper)
        try await cache.setValue(data, forKey: "mint:\(url)", namespace: namespace)
    }

    public func getMintInfo(url: String) async -> NDKMintInfo? {
        guard let data = await cache.getValue(forKey: "mint:\(url)", namespace: namespace),
              let wrapper = try? JSONDecoder().decode(MintInfoWrapper.self, from: data) else {
            return nil
        }
        return wrapper.info
    }

    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let data = await cache.getValue(forKey: "mint:\(url)", namespace: namespace),
              let wrapper = try? JSONDecoder().decode(MintInfoWrapper.self, from: data) else {
            return true
        }
        return Date().timeIntervalSince(wrapper.timestamp) > maxAge
    }

    public func invalidateMintCache(url: String) async throws {
        try await cache.deleteValue(forKey: "mint:\(url)", namespace: namespace)
        // Also delete all keysets for this mint
        let keysets = await cache.getValues(namespace: namespace, keyPrefix: "keyset:\(url):")
        for key in keysets.keys {
            try await cache.deleteValue(forKey: key, namespace: namespace)
        }
    }

    // MARK: - Keysets

    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        let wrapper = KeysetWrapper(keyset: keyset, mintUrl: mintUrl, timestamp: Date())
        let data = try JSONEncoder().encode(wrapper)
        try await cache.setValue(data, forKey: "keyset:\(mintUrl):\(keyset.keysetID)", namespace: namespace)
    }

    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let timestamp = Date()
        for keyset in keysets {
            let wrapper = KeysetWrapper(keyset: keyset, mintUrl: mintUrl, timestamp: timestamp)
            let data = try JSONEncoder().encode(wrapper)
            try await cache.setValue(data, forKey: "keyset:\(mintUrl):\(keyset.keysetID)", namespace: namespace)
        }
    }

    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        // Need to search all keysets since we don't know the mintUrl
        let allKeysets = await cache.getValues(namespace: namespace, keyPrefix: "keyset:")
        for (_, data) in allKeysets {
            if let wrapper = try? JSONDecoder().decode(KeysetWrapper.self, from: data),
               wrapper.keyset.keysetID == id {
                return wrapper.keyset
            }
        }
        return nil
    }

    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        let keysets = await cache.getValues(namespace: namespace, keyPrefix: "keyset:\(mintUrl):")
        return keysets.values.compactMap { data in
            try? JSONDecoder().decode(KeysetWrapper.self, from: data).keyset
        }
    }

    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        let allKeysets = await getKeysets(mintUrl: mintUrl)
        return allKeysets.filter { $0.unit == unit && $0.active }
    }

    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        let keysets = await cache.getValues(namespace: namespace, keyPrefix: "keyset:\(mintUrl):")
        guard !keysets.isEmpty else { return true }

        var oldestTimestamp: Date?
        for (_, data) in keysets {
            if let wrapper = try? JSONDecoder().decode(KeysetWrapper.self, from: data) {
                if oldestTimestamp == nil || wrapper.timestamp < oldestTimestamp! {
                    oldestTimestamp = wrapper.timestamp
                }
            }
        }

        guard let oldest = oldestTimestamp else { return true }
        return Date().timeIntervalSince(oldest) > maxAge
    }
}

// MARK: - Internal Wrapper Types

private struct MintInfoWrapper: Codable {
    let info: NDKMintInfo
    let timestamp: Date
}

private struct KeysetWrapper: Codable {
    let keyset: CashuSwift.Keyset
    let mintUrl: String
    let timestamp: Date
}
