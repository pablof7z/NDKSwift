import Foundation
import CashuSwift

/// Protocol defining mint caching capabilities for Cashu wallets
public protocol MintCache {
    /// Save raw mint info JSON to cache
    func saveMintInfoJSON(_ jsonData: Data, url: String) async throws
    
    /// Get raw mint info JSON from cache
    func getMintInfoJSON(url: String) async -> Data?
    
    /// Check if mint info needs refresh
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool
    
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
    // Already implemented in NDKSQLiteCache
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
    public func loadMint(url: URL) async throws -> CashuSwift.Mint {
        let urlString = url.absoluteString
        
        // Check if we have cached keysets that are still fresh
        let cachedKeysets = await cache.getKeysets(mintUrl: urlString)
        let keysetsStale = await cache.areKeysetsStale(mintUrl: urlString, maxAge: keysetMaxAge)
        
        if !cachedKeysets.isEmpty && !keysetsStale {
            // We have fresh cached keysets, use them
            return CashuSwift.Mint(url: url, keysets: cachedKeysets)
        }
        
        // Load fresh mint data from network
        let mint = try await CashuSwift.loadMint(url: url)
        
        // Cache the keysets
        try await cache.saveKeysets(mint.keysets, mintUrl: urlString)
        
        return mint
    }
    
    /// Load mint info with caching - returns the JSON data
    public func loadMintInfoData(url: URL) async throws -> Data {
        let urlString = url.absoluteString
        
        // Check cache first
        if let cachedData = await cache.getMintInfoJSON(url: urlString) {
            let isStale = await cache.isMintInfoStale(url: urlString, maxAge: mintInfoMaxAge)
            if !isStale {
                return cachedData
            }
        }
        
        // Fetch from network
        let infoUrl = url.appending(path: "/v1/info")
        let data = try await URLSession.shared.data(from: infoUrl).0
        
        // Cache the result
        try await cache.saveMintInfoJSON(data, url: urlString)
        
        return data
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
    private var mintInfos: [String: (data: Data, timestamp: Date)] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var mintKeysets: [String: [(keyset: CashuSwift.Keyset, timestamp: Date)]] = [:]
    
    public init() {}
    
    public func saveMintInfoJSON(_ jsonData: Data, url: String) async throws {
        mintInfos[url] = (jsonData, Date())
    }
    
    public func getMintInfoJSON(url: String) async -> Data? {
        return mintInfos[url]?.data
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = mintInfos[url] else { return true }
        return Date().timeIntervalSince(entry.timestamp) > maxAge
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