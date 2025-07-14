import Foundation
import CashuSwift

/// Manages all mint-related operations for the Cashu wallet
public actor MintManager {
    // MARK: - Properties
    
    private var mints: [String: CashuSwift.Mint] = [:] // URL string to Mint
    private var keysets: [String: CashuSwift.Keyset] = [:] // Keyset ID to Keyset
    private let mintLoader: CachedMintLoader?
    
    // MARK: - Initialization
    
    public init(cache: NDKCache? = nil) {
        if let cache = cache {
            self.mintLoader = CachedMintLoader(cache: cache)
        } else {
            self.mintLoader = nil
        }
    }
    
    // MARK: - Mint Management
    
    /// Load a mint (uses cache if available)
    public func loadMint(url: URL, forceRefresh: Bool = false) async throws -> CashuSwift.Mint {
        if let loader = mintLoader {
            return try await loader.loadMint(url: url, forceRefresh: forceRefresh)
        } else {
            return try await CashuSwift.loadMint(url: url)
        }
    }
    
    /// Add a mint to the manager
    public func addMint(url: URL) async throws {
        let mint = try await loadMint(url: url)
        mints[url.absoluteString] = mint
        
        // Store keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
    }
    
    /// Remove a mint from the manager
    public func removeMint(url: URL) async -> [String] {
        // Get keyset IDs before removing
        let mintKeysetIds = mints[url.absoluteString]?.keysets.map { $0.keysetID } ?? []
        
        // Remove keysets
        for keysetId in mintKeysetIds {
            keysets.removeValue(forKey: keysetId)
        }
        
        // Remove mint
        mints.removeValue(forKey: url.absoluteString)
        
        return mintKeysetIds
    }
    
    /// Get a mint by URL
    public func getMint(url: String) -> CashuSwift.Mint? {
        return mints[url]
    }
    
    /// Get all mints
    public func getAllMints() -> [String: CashuSwift.Mint] {
        return mints
    }
    
    /// Get all mint URLs
    public func getMintURLs() -> [String] {
        return Array(mints.keys)
    }
    
    /// Check if a mint exists
    public func hasMint(url: String) -> Bool {
        return mints[url] != nil
    }
    
    /// Get mint info (uses cache if available)
    public func getMintInfo(url: URL) async throws -> NDKMintInfo {
        if let loader = mintLoader {
            return try await loader.loadMintInfo(url: url)
        } else {
            // Fallback to direct network fetch
            let infoUrl = url.appending(path: "/v1/info")
            let data = try await URLSession.shared.data(from: infoUrl).0
            return try JSONDecoder().decode(NDKMintInfo.self, from: data)
        }
    }
    
    /// Refresh mint keysets from network
    public func refreshMintKeysets(url: URL) async throws {
        let mint = try await loadMint(url: url, forceRefresh: true)
        mints[url.absoluteString] = mint
        
        // Update keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
    }
    
    // MARK: - Keyset Management
    
    /// Get a keyset by ID
    public func getKeyset(id: String) -> CashuSwift.Keyset? {
        return keysets[id]
    }
    
    /// Check if a keyset exists
    public func hasKeyset(id: String) -> Bool {
        return keysets[id] != nil
    }
    
    /// Add a keyset
    public func addKeyset(_ keyset: CashuSwift.Keyset) {
        keysets[keyset.keysetID] = keyset
    }
    
    /// Find mint URL for a given keyset ID
    public func findMintForKeyset(_ keysetId: String) -> String? {
        for (mintUrl, mint) in mints {
            if mint.keysets.contains(where: { $0.keysetID == keysetId }) {
                return mintUrl
            }
        }
        return nil
    }
    
    /// Get keysets for a specific mint
    public func getKeysetsForMint(url: String) -> [CashuSwift.Keyset] {
        return mints[url]?.keysets ?? []
    }
    
    // MARK: - Mint Operations
    
    /// Request a mint quote for Lightning deposits
    public func requestMintQuote(amount: Int64, mintURL: String) async throws -> CashuSwift.Bolt11.MintQuote {
        // Ensure mint is loaded
        if !hasMint(url: mintURL), let url = URL(string: mintURL) {
            try await addMint(url: url)
        }
        
        guard let mint = getMint(url: mintURL) else {
            throw NDKError.noMintAvailable("Failed to load mint")
        }
        
        // Request mint quote from the mint
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )
        
        let quoteResponse = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MintQuote
        
        return quoteResponse
    }
    
    /// Load mint from wallet configuration tags
    public func loadMintFromTag(_ mintURLString: String) async {
        guard let mintURL = URL(string: mintURLString) else { return }
        
        do {
            try await addMint(url: mintURL)
        } catch {
            print("Failed to load mint \(mintURLString): \(error)")
        }
    }
    
    // MARK: - State Management
    
    /// Clear all mints and keysets
    public func clear() {
        mints.removeAll()
        keysets.removeAll()
    }
    
    /// Get mint information for display
    public func getMintsInfo() -> [MintInfo] {
        return mints.values.map { mint in
            // Use the existing MintInfo from CashuTypes
            MintInfo(
                url: mint.url,
                features: nil
            )
        }
    }
}

// MARK: - Test Helpers
#if DEBUG
extension MintManager {
    /// Test helper to directly set a mint
    func setTestMint(_ mint: CashuSwift.Mint, for url: URL) {
        mints[url.absoluteString] = mint
        // Also store keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
    }
    
    /// Test helper to directly set a keyset
    func setTestKeyset(_ keyset: CashuSwift.Keyset) {
        keysets[keyset.keysetID] = keyset
    }
    
    /// Get a mint by URL (overload for URL type)
    func getMint(for url: URL) async throws -> CashuSwift.Mint? {
        return mints[url.absoluteString]
    }
}
#endif