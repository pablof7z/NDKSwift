#!/usr/bin/env swift

import Foundation
import NDKSwift
import CashuSwift

// Example: Using NDKCashuWallet with mint caching for improved performance

@main
struct CashuWalletWithCacheExample {
    static func main() async throws {
        print("🏦 Cashu Wallet with Mint Caching Example")
        print("=========================================\n")
        
        // Initialize NDK
        let ndk = NDK()
        
        // Create SQLite cache for persistent storage
        let cache = try await NDKSQLiteCache(path: "cashu_mint_cache.db")
        print("✅ Created SQLite cache")
        
        // Create wallet with cache support
        let wallet = NDKCashuWallet(ndk: ndk, mintCache: cache)
        print("✅ Created Cashu wallet with caching enabled")
        
        // Example mint URLs
        let mintUrls = [
            URL(string: "https://mint.minibits.cash")!,
            URL(string: "https://testnut.cashu.space")!
        ]
        
        // First load - will fetch from network and cache
        print("\n📡 First load (from network):")
        for mintUrl in mintUrls {
            let start = Date()
            do {
                try await wallet.addMint(url: mintUrl)
                let duration = Date().timeIntervalSince(start)
                print("  ✓ Added \(mintUrl.host ?? "mint") - took \(String(format: "%.2f", duration))s")
                
                // Get mint info (also cached)
                let info = try await wallet.getMintInfo(url: mintUrl)
                print("    Name: \(info.name ?? "Unknown")")
                print("    Version: \(info.version ?? "Unknown")")
            } catch {
                print("  ✗ Failed to add \(mintUrl.host ?? "mint"): \(error)")
            }
        }
        
        // Check cache statistics
        print("\n📊 Cache Statistics:")
        let cachedMints = await cache.getCachedMintUrls()
        print("  Cached mints: \(cachedMints.count)")
        for url in cachedMints {
            let keysets = await cache.getKeysets(mintUrl: url)
            print("  - \(URL(string: url)?.host ?? url): \(keysets.count) keysets")
        }
        
        // Second load - will use cache (much faster)
        print("\n💨 Second load (from cache):")
        let wallet2 = NDKCashuWallet(ndk: ndk, mintCache: cache)
        
        for mintUrl in mintUrls {
            let start = Date()
            do {
                // This will use cached data if fresh
                let info = try await wallet2.getMintInfo(url: mintUrl)
                let duration = Date().timeIntervalSince(start)
                print("  ✓ Loaded \(info.name ?? mintUrl.host ?? "mint") - took \(String(format: "%.4f", duration))s (cached)")
            } catch {
                print("  ✗ Failed to load info: \(error)")
            }
        }
        
        // Check staleness
        print("\n🕐 Cache Freshness:")
        for url in cachedMints {
            let infoStale = await cache.isMintInfoStale(url: url, maxAge: 86400) // 24 hours
            let keysetsStale = await cache.areKeysetsStale(mintUrl: url, maxAge: 3600) // 1 hour
            print("  \(URL(string: url)?.host ?? url):")
            print("    - Info: \(infoStale ? "stale" : "fresh")")
            print("    - Keysets: \(keysetsStale ? "stale" : "fresh")")
        }
        
        // Force refresh example
        if let firstMint = mintUrls.first {
            print("\n🔄 Force refreshing \(firstMint.host ?? "mint")...")
            do {
                try await wallet.refreshMintKeysets(url: firstMint)
                print("  ✓ Keysets refreshed and cache updated")
            } catch {
                print("  ✗ Refresh failed: \(error)")
            }
        }
        
        print("\n✨ Example complete!")
        print("\nBenefits of mint caching:")
        print("- ⚡ Faster wallet initialization")
        print("- 📱 Reduced network requests")
        print("- 🔋 Lower battery usage on mobile")
        print("- 🌐 Better offline support")
    }
}

// Note: To run this example:
// swift run --package-path Examples CashuWalletWithCache