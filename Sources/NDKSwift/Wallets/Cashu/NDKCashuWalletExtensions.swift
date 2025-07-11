import Foundation
import CashuSwift

// MARK: - NDKCashuWallet Extensions

extension NDKCashuWallet {
    /// Discover and add mints from Nostr using NDK passed as parameter
    /// - Parameters:
    ///   - ndk: The NDK instance to use for discovery
    ///   - units: Filter by supported units
    ///   - limit: Maximum number of mints to discover
    /// - Returns: Array of discovered mints that were added
    public func discoverAndAddMints(
        using ndk: NDK,
        units: [String] = ["sat"],
        limit: Int = 10
    ) async throws -> [MintDiscovery.DiscoveredMint] {
        let discovery = MintDiscovery(ndk: ndk)
        let discoveredMints = try await discovery.discoverMints(
            limit: limit,
            units: units
        )
        
        var addedMints: [MintDiscovery.DiscoveredMint] = []
        
        for discovered in discoveredMints {
            // Skip suspicious mints
            if await discovery.isSuspiciousMint(discovered.announcement.mintURL) {
                continue
            }
            
            // Skip if we already have this mint
            if await self.hasMint(url: discovered.announcement.mintURL) {
                continue
            }
            
            // Try to load and add the mint
            do {
                let mint = try await CashuSwift.loadMint(url: discovered.announcement.mintURL)
                self.addMint(mint)
                addedMints.append(discovered)
                
                print("Added mint: \(discovered.announcement.name ?? discovered.announcement.mintURL.absoluteString)")
            } catch {
                print("Failed to load mint \(discovered.announcement.mintURL): \(error)")
            }
        }
        
        return addedMints
    }
    
    /// Check if wallet has a mint with given URL
    internal func hasMint(url: URL) async -> Bool {
        // This needs to be implemented in the main wallet class
        // For now, return false to allow adding
        return false
    }
}