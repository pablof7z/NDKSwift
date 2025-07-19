import Foundation
import CashuSwift

/// A simple wrapper that provides mint caching with automatic refresh
public actor CachedMintLoader {
    private let cache: NDKCache
    private let mintInfoMaxAge: TimeInterval
    private let keysetMaxAge: TimeInterval
    
    /// Initialize with a cache and staleness intervals
    /// - Parameters:
    ///   - cache: The cache implementation to use
    ///   - mintInfoMaxAge: How long before mint info is considered stale (default: 24 hours)
    ///   - keysetMaxAge: How long before keysets are considered stale (default: 1 hour)
    public init(
        cache: NDKCache,
        mintInfoMaxAge: TimeInterval = 86400,  // 24 hours
        keysetMaxAge: TimeInterval = 3600      // 1 hour
    ) {
        self.cache = cache
        self.mintInfoMaxAge = mintInfoMaxAge
        self.keysetMaxAge = keysetMaxAge
    }
    
    /// Load mint with caching - returns cached version if fresh, otherwise fetches from network
    public func loadMint(url: URL, forceRefresh: Bool = false) async throws -> CashuSwift.Mint {
        let urlString = url.absoluteString
        
        // Force refresh if requested
        if forceRefresh {
            try? await cache.invalidateMintCache(url: urlString)
        }
        
        // Check if we have cached keysets that are still fresh
        let cachedKeysets = await cache.getKeysets(mintUrl: urlString)
        let keysetsStale = await cache.areKeysetsStale(mintUrl: urlString, maxAge: keysetMaxAge)
        
        if !cachedKeysets.isEmpty && !keysetsStale && !forceRefresh {
            // We have fresh cached keysets, use them
            return CashuSwift.Mint(url: url, keysets: cachedKeysets)
        }
        
        // Load fresh mint data from network
        let mint = try await CashuSwift.loadMint(url: url)
        
        // Cache the keysets
        try await cache.saveKeysets(mint.keysets, mintUrl: urlString)
        
        return mint
    }
    
    /// Load mint info with caching
    public func loadMintInfo(url: URL, forceRefresh: Bool = false) async throws -> NDKMintInfo {
        let urlString = url.absoluteString
        
        // Force refresh if requested
        if forceRefresh {
            try? await cache.invalidateMintCache(url: urlString)
        }
        
        // Check cache first
        if let cachedInfo = await cache.getMintInfo(url: urlString) {
            let isStale = await cache.isMintInfoStale(url: urlString, maxAge: mintInfoMaxAge)
            if !isStale {
                return cachedInfo
            }
        }
        
        // Fetch from network
        let infoUrl = url.appending(path: "/v1/info")
        let data = try await URLSession.shared.data(from: infoUrl).0
        
        // Decode to our local type
        let info = try JSONCoding.decode(NDKMintInfo.self, from: data)
        
        // Cache the result
        try await cache.saveMintInfo(info, url: urlString)
        
        return info
    }
    
    /// Get keyset by ID with caching
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return await cache.getKeyset(id: id)
    }
    
    /// Invalidate cache for a mint (forces refresh on next load)
    public func invalidateMintCache(url: URL) async {
        // This could be implemented by updating last_updated to 0
        // or by deleting the entries - for now we'll rely on staleness checks
    }
}