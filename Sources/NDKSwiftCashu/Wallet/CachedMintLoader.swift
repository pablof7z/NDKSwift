import CashuSwift
import Foundation
import NDKSwiftCore

// MARK: - Cache Constants

public enum CacheConstants {
    /// Default max age for mint info (7 days)
    public static let defaultMintInfoMaxAge: TimeInterval = TimeConstants.mintInfoCacheTTL

    /// Default max age for keysets (3 days)
    public static let defaultKeysetMaxAge: TimeInterval = TimeConstants.keysetsCacheTTL
}

/// A simple wrapper that provides mint caching with automatic refresh
public actor CachedMintLoader {
    private let cacheHelper: CashuCacheHelper
    private let mintInfoMaxAge: TimeInterval
    private let keysetMaxAge: TimeInterval
    private let networkClient = NDKNetworkClient()

    /// Initialize with a cache and staleness intervals
    /// - Parameters:
    ///   - cache: The cache implementation to use
    ///   - mintInfoMaxAge: How long before mint info is considered stale (default: 7 days)
    ///   - keysetMaxAge: How long before keysets are considered stale (default: 3 days)
    public init(
        cache: NDKNostrDBCache,
        mintInfoMaxAge: TimeInterval = CacheConstants.defaultMintInfoMaxAge,
        keysetMaxAge: TimeInterval = CacheConstants.defaultKeysetMaxAge
    ) {
        cacheHelper = CashuCacheHelper(cache: cache)
        self.mintInfoMaxAge = mintInfoMaxAge
        self.keysetMaxAge = keysetMaxAge
    }

    /// Load mint with caching - returns cached version if fresh, otherwise fetches from network
    public func loadMint(url: URL, forceRefresh: Bool = false) async throws -> CashuSwift.Mint {
        let urlString = url.absoluteString

        // Force refresh if requested
        if forceRefresh {
            do {
                try await cacheHelper.invalidateMintCache(url: urlString)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to invalidate mint cache for \(urlString): \(error.localizedDescription)")
            }
        }

        // Check if we have cached keysets that are still fresh
        let cachedKeysets = await cacheHelper.getKeysets(mintUrl: urlString)
        let keysetsStale = await cacheHelper.areKeysetsStale(mintUrl: urlString, maxAge: keysetMaxAge)

        if !cachedKeysets.isEmpty && !keysetsStale && !forceRefresh {
            // We have fresh cached keysets, use them
            return CashuSwift.Mint(url: url, keysets: cachedKeysets)
        }

        // Load fresh mint data from network
        let mint = try await CashuSwift.loadMint(url: url)

        // Cache the keysets
        try await cacheHelper.saveKeysets(mint.keysets, mintUrl: urlString)

        return mint
    }

    /// Load mint info with caching
    public func loadMintInfo(url: URL, forceRefresh: Bool = false) async throws -> NDKMintInfo {
        let urlString = url.absoluteString

        // Force refresh if requested
        if forceRefresh {
            do {
                try await cacheHelper.invalidateMintCache(url: urlString)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to invalidate mint info cache for \(urlString): \(error.localizedDescription)")
            }
        }

        // Check cache first
        if let cachedInfo = await cacheHelper.getMintInfo(url: urlString) {
            let isStale = await cacheHelper.isMintInfoStale(url: urlString, maxAge: mintInfoMaxAge)
            if !isStale {
                return cachedInfo
            }
        }

        // Fetch from network
        let infoUrl = url.appending(path: "/v1/info")
        let info = try await networkClient.fetchJSON(NDKMintInfo.self, from: infoUrl)

        // Cache the result
        try await cacheHelper.saveMintInfo(info, url: urlString)

        return info
    }

    /// Get keyset by ID with caching
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return await cacheHelper.getKeyset(id: id)
    }

    /// Invalidate cache for a mint (forces refresh on next load)
    public func invalidateMintCache(url: URL) async {
        do {
            try await cacheHelper.invalidateMintCache(url: url.absoluteString)
        } catch {
            NDKLogger.log(.warning, category: .cache, "Failed to invalidate mint cache: \(error.localizedDescription)")
        }
    }
}
