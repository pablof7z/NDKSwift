import CashuSwift
import Foundation
import NDKSwiftCore

/// Manages all mint-related operations for the Cashu wallet
public actor MintManager {
    // MARK: - Properties

    private var mints: [String: CashuSwift.Mint] = [:] // URL string to Mint
    private var keysets: [String: CashuSwift.Keyset] = [:] // Keyset ID to Keyset
    private let mintLoader: CachedMintLoader?
    private let networkClient = NDKNetworkClient()

    // MARK: - Initialization

    public init(cache: NDKCache? = nil) {
        if let cache = cache {
            mintLoader = CachedMintLoader(cache: cache)
        } else {
            mintLoader = nil
        }
    }

    // MARK: - Mint Management

    /// Load a mint (uses cache if available)
    public func loadMint(url: URL, forceRefresh: Bool = false) async throws -> CashuSwift.Mint {
        let mint: CashuSwift.Mint
        if let loader = mintLoader {
            mint = try await loader.loadMint(url: url, forceRefresh: forceRefresh)
        } else {
            mint = try await CashuSwift.loadMint(url: url)
        }

        // Store in memory for quick access
        mints[url.absoluteString] = mint

        // Store keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }

        return mint
    }

    /// Add mint URL without connecting (for configuration)
    public func addMintURL(url: URL) async {
        // Create a placeholder mint with just the URL
        // We'll load the actual mint data later when needed
        let placeholderMint = CashuSwift.Mint(url: url, keysets: [])
        mints[url.absoluteString] = placeholderMint
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
            return try await networkClient.fetchJSON(NDKMintInfo.self, from: infoUrl)
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
        // Always ensure mint is properly loaded with keysets
        guard let url = URLUtils.safeURL(mintURL) else {
            throw NDKError.invalidURL("\(ErrorMessageConstants.invalid("mint URL")): \(mintURL)")
        }

        // Get mint - loadMint will use cache and store in memory
        let mint = try await loadMint(url: url)

        // Verify we have valid keysets
        guard !mint.keysets.isEmpty else {
            throw NDKError.noMintAvailable("Mint has no keysets")
        }

        // Request mint quote from the mint
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )

        let response = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        )

        guard let quoteResponse = response as? CashuSwift.Bolt11.MintQuote else {
            throw NDKError.walletError(message: "Unexpected quote response type")
        }

        return quoteResponse
    }

    // MARK: - State Management

    /// Clear all mints and keysets
    public func clear() {
        mints.removeAll()
        keysets.removeAll()
    }

    /// Get mint information for display
    public func getMintsInfo() -> [NDKMintInfo] {
        // Since we can't access the internal structure of CashuSwift.Mint,
        // we'll return a simplified version with just the URL
        return mints.keys.map { urlString in
            NDKMintInfo(
                name: nil,
                pubkey: nil,
                version: nil,
                description: nil,
                descriptionLong: nil,
                contact: nil,
                motd: nil,
                iconURL: nil,
                urls: [urlString],
                time: nil,
                tosURL: nil,
                nuts: nil
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
