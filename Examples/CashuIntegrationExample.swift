import Foundation
import NDKSwift
import CashuSwift

/// Example demonstrating the integration of NDKCache (SQLite) with Cashu wallet
/// 
/// This example shows how the NDKSQLiteCache serves as the unified cache implementation
/// for both Nostr events and Cashu mint data.
@main
struct CashuIntegrationExample {
    static func main() async {
        do {
            print("🚀 NDKSwift Cashu Cache Integration Example")
            print("=========================================\n")
            
            // Step 1: Create a unified SQLite cache instance
            // This cache implements NDKCache which now includes mint caching
            let unifiedCache = try await NDKSQLiteCache(
                path: "cashu_integrated.db",
                debugMode: true
            )
            print("✅ Created unified SQLite cache")
            
            // Step 2: Initialize NDK with the unified cache
            let ndk = NDK(
                relayConnector: SimpleRelayConnector(
                    relayURLs: [
                        "wss://relay.damus.io",
                        "wss://relay.primal.net"
                    ]
                ),
                cache: unifiedCache  // Using the same cache instance
            )
            print("✅ Initialized NDK with unified cache")
            
            // Step 3: Create a signer (required for wallet operations)
            let privateKey = try generatePrivateKey()
            let signer = NDKPrivateKeySigner(privateKey: privateKey)
            ndk.signer = signer
            print("✅ Created and configured signer")
            
            // Step 4: Initialize Cashu wallet with the same cache instance
            // The wallet will use the mint cache functionality from NDKCache
            let cashuWallet = NDKCashuWallet(
                ndk: ndk,
                cache: unifiedCache  // Same cache instance!
            )
            print("✅ Created Cashu wallet with unified cache")
            
            // Step 5: Connect to relays
            try await ndk.connect()
            print("✅ Connected to relays")
            
            // Step 6: Demonstrate cache usage
            print("\n📊 Demonstrating Unified Cache Usage:")
            print("=====================================")
            
            // Example: Loading mint info (will be cached automatically)
            let mintURL = URL(string: "https://mint.example.com")!
            
            print("\n1️⃣ First mint load - fetches from network and caches:")
            // This would normally fetch from network and cache the result
            // (In a real scenario, you'd need a running mint server)
            
            print("\n2️⃣ Second mint load - retrieves from cache:")
            // Subsequent calls would use the cached data
            
            // Example: Event caching works alongside mint caching
            print("\n3️⃣ Creating and caching a Nostr event:")
            let event = try await ndk.createEvent(
                kind: 1,
                content: "Testing unified cache with Cashu integration!"
            )
            
            // The event is automatically cached when published
            try await event.publish()
            print("   ✅ Event published and cached")
            
            // Retrieve the event from cache
            if let cachedEvent = await unifiedCache.getEvent(id: event.id) {
                print("   ✅ Event retrieved from cache: \(cachedEvent.content)")
            }
            
            // Example: Mint cache operations
            print("\n4️⃣ Direct mint cache operations:")
            
            // Save mint info to cache
            let mockMintInfo = NDKMintInfo(
                name: "Example Mint",
                pubkey: "02abc...",
                version: "1.0.0",
                description: "Test mint for demo",
                descriptionLong: nil,
                contact: nil,
                mintIconUrl: nil,
                motd: nil,
                nuts: nil
            )
            
            try await unifiedCache.saveMintInfo(mockMintInfo, url: mintURL.absoluteString)
            print("   ✅ Saved mint info to cache")
            
            // Retrieve mint info from cache
            if let cachedMintInfo = await unifiedCache.getMintInfo(url: mintURL.absoluteString) {
                print("   ✅ Retrieved mint info: \(cachedMintInfo.name)")
            }
            
            // Check if mint info is stale
            let isStale = await unifiedCache.isMintInfoStale(
                url: mintURL.absoluteString,
                maxAge: 86400 // 24 hours
            )
            print("   ℹ️ Mint info is stale: \(isStale)")
            
            // Example: Keyset caching
            print("\n5️⃣ Keyset cache operations:")
            
            // Create a mock keyset
            let mockKeyset = CashuSwift.Keyset(
                keysetID: "test-keyset-id",
                unit: "sat",
                active: true,
                inputFeePPK: 0,
                keys: [:]  // Empty for demo
            )
            
            try await unifiedCache.saveKeyset(mockKeyset, mintUrl: mintURL.absoluteString)
            print("   ✅ Saved keyset to cache")
            
            // Retrieve keyset
            if let cachedKeyset = await unifiedCache.getKeyset(id: "test-keyset-id") {
                print("   ✅ Retrieved keyset: \(cachedKeyset.keysetID)")
            }
            
            // Get all keysets for a mint
            let mintKeysets = await unifiedCache.getKeysets(mintUrl: mintURL.absoluteString)
            print("   ℹ️ Found \(mintKeysets.count) keysets for mint")
            
            print("\n✨ Benefits of Unified Cache:")
            print("================================")
            print("• Single database file for all cached data")
            print("• Consistent caching strategy across Nostr and Cashu")
            print("• Shared database connection pool")
            print("• Atomic transactions for related data")
            print("• Unified cache management (clear, size limits, etc.)")
            print("• Better performance through shared indexes")
            
            // Cleanup
            try await ndk.disconnect()
            print("\n👋 Example completed successfully!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// MARK: - Best Practices for Production

/*
 Production Integration Guidelines:
 
 1. **Single Cache Instance**:
    ```swift
    // Create once at app startup
    let cache = try await NDKSQLiteCache()
    
    // Share with all components
    let ndk = NDK(cache: cache)
    let wallet = NDKCashuWallet(ndk: ndk, mintCache: cache)
    ```
 
 2. **Cache Configuration**:
    ```swift
    // Custom path for app's document directory
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let cachePath = documentsPath.appendingPathComponent("app_cache.db").path
    let cache = try await NDKSQLiteCache(path: cachePath)
    ```
 
 3. **Error Handling**:
    - Cache operations are designed to be fault-tolerant
    - Network fetches fallback when cache misses occur
    - Stale data is automatically refreshed based on age
 
 4. **Performance Considerations**:
    - SQLite cache uses WAL mode for concurrent reads
    - Indexes optimize common query patterns
    - JSON storage allows flexible schema evolution
 
 5. **Migration Safety**:
    - Database migrations run automatically
    - Schema changes are backward compatible
    - Data integrity is maintained during upgrades
*/

// MARK: - Architecture Benefits

/*
 Unified Cache Architecture:
 
 ┌─────────────────┐     ┌─────────────────┐
 │   NDK Events    │     │  Cashu Wallet   │
 └────────┬────────┘     └────────┬────────┘
          │                       │
          │  NDKCache            │  MintCache
          │  Protocol            │  Protocol
          └───────────┬──────────┘
                      │
              ┌───────┴────────┐
              │ NDKSQLiteCache │
              │                │
              │ Implements:    │
              │ - NDKCache     │
              │ - MintCache    │
              └───────┬────────┘
                      │
              ┌───────┴────────┐
              │  SQLite DB     │
              │                │
              │ Tables:        │
              │ - events       │
              │ - profiles     │
              │ - mint_info    │
              │ - keysets      │
              └────────────────┘
 
 This architecture provides:
 - Single source of truth for all cached data
 - Consistent caching behavior across features
 - Simplified dependency management
 - Better resource utilization
 - Easier debugging and monitoring
*/