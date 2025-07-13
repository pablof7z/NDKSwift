import Foundation
import CashuSwift

/// Protocol defining mint caching capabilities for Cashu wallets
public protocol MintCache {
    /// Save mint info to cache
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws
    
    /// Get mint info from cache
    func getMintInfo(url: String) async -> NDKMintInfo?
    
    /// Check if mint info needs refresh
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool
    
    /// Invalidate mint cache (forces refresh on next load)
    func invalidateMintCache(url: String) async throws
    
    /// Save keyset to cache
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws
    
    /// Save multiple keysets at once
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws
    
    /// Get keyset by ID
    func getKeyset(id: String) async -> CashuSwift.Keyset?
    
    /// Get all keysets for a mint
    func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset]
    
    /// Get active keysets for a mint and unit
    func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset]
    
    /// Check if keysets need refresh
    func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool
}

/// Extension to make NDKSQLiteCache conform to MintCache
extension NDKSQLiteCache: MintCache {
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        let jsonData = try info.toJSONData()
        try await saveMintInfoJSON(jsonData, url: url)
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        guard let jsonData = await getMintInfoJSON(url: url) else {
            return nil
        }
        return try? NDKMintInfo(from: jsonData)
    }
    
    public func invalidateMintCache(url: String) async throws {
        // NDKSQLiteCache doesn't have a direct invalidate method
        // We can achieve this by saving empty data or relying on staleness checks
        // For now, we'll do nothing as the staleness check will handle it
    }
}

/// A simple wrapper that provides mint caching with automatic refresh
public actor CachedMintLoader {
    private let cache: MintCache
    private let mintInfoMaxAge: TimeInterval
    private let keysetMaxAge: TimeInterval
    
    /// Initialize with a cache and staleness intervals
    /// - Parameters:
    ///   - cache: The cache implementation to use
    ///   - mintInfoMaxAge: How long before mint info is considered stale (default: 24 hours)
    ///   - keysetMaxAge: How long before keysets are considered stale (default: 1 hour)
    public init(
        cache: MintCache,
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
        let info = try JSONDecoder().decode(NDKMintInfo.self, from: data)
        
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

/// In-memory mint cache for testing or temporary use
public actor InMemoryMintCache: MintCache {
    private var mintInfos: [String: (info: NDKMintInfo, timestamp: Date)] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var mintKeysets: [String: [(keyset: CashuSwift.Keyset, timestamp: Date)]] = [:]
    
    public init() {}
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mintInfos[url] = (info, Date())
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        return mintInfos[url]?.info
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = mintInfos[url] else { return true }
        return Date().timeIntervalSince(entry.timestamp) > maxAge
    }
    
    public func invalidateMintCache(url: String) async throws {
        mintInfos.removeValue(forKey: url)
        mintKeysets.removeValue(forKey: url)
    }
    
    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        keysets[keyset.keysetID] = keyset
        
        var mintList = mintKeysets[mintUrl] ?? []
        mintList.append((keyset, Date()))
        mintKeysets[mintUrl] = mintList
    }
    
    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let timestamp = Date()
        var mintList = mintKeysets[mintUrl] ?? []
        
        for keyset in keysets {
            self.keysets[keyset.keysetID] = keyset
            mintList.append((keyset, timestamp))
        }
        
        mintKeysets[mintUrl] = mintList
    }
    
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return keysets[id]
    }
    
    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        return mintKeysets[mintUrl]?.map { $0.keyset } ?? []
    }
    
    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        return mintKeysets[mintUrl]?
            .map { $0.keyset }
            .filter { $0.unit == unit && $0.active } ?? []
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        guard let entries = mintKeysets[mintUrl], !entries.isEmpty else { return true }
        
        // Check the timestamp of the oldest keyset
        let oldestTimestamp = entries.map { $0.timestamp }.min() ?? Date()
        return Date().timeIntervalSince(oldestTimestamp) > maxAge
    }
}