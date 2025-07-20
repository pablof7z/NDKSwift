#!/usr/bin/env swift

// Example demonstrating the new maxAge parameter in NDKDataSource

import Foundation
import NDKSwift

// Helper to run async code
struct Runner {
    static func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                print("Error: \(error)")
            }
        }
        RunLoop.main.run()
    }
}

Runner.run {
    // Initialize NDK
    let ndk = NDK()
    
    // Example 1: Real-time subscription (maxAge = 0)
    print("Example 1: Real-time subscription")
    let realtimeSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [1], limit: 10),
        maxAge: 0  // Keep subscription open
    )
    
    // Example 2: Feed view with stale tolerance
    print("\nExample 2: Feed with 1-hour stale tolerance")
    let feedSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [1], authors: ["pubkey1", "pubkey2"]),
        maxAge: 3600  // 1 hour old data is fine
    )
    
    // Example 3: Profile data with moderate freshness
    print("\nExample 3: Profile with 5-minute freshness")
    let profileSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [0], authors: ["profilePubkey"]),
        maxAge: 300  // 5 minutes
    )
    
    // Example 4: Cache-only mode for offline
    print("\nExample 4: Cache-only mode")
    let offlineSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [10002]),  // Relay lists
        maxAge: .infinity,  // Any age is fine
        cachePolicy: .cacheOnly
    )
    
    // Example 5: Force network refresh
    print("\nExample 5: Force network refresh")
    let freshSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [1], limit: 1),
        cachePolicy: .networkOnly
    )
    
    // Example 6: Using AsyncStream for internal components
    print("\nExample 6: Internal component using AsyncStream")
    Task {
        for await event in profileSource.events {
            print("Received profile update: \(event)")
            // Internal components can react to updates
        }
    }
    
    // Example 7: One-shot access for internal use
    print("\nExample 7: One-shot value access")
    let currentProfiles = await profileSource.currentValue()
    print("Current profiles: \(currentProfiles.count)")
    
    print("\nAll examples initialized. The new architecture supports:")
    print("- maxAge for cache freshness control")
    print("- CachePolicy for offline/online modes")
    print("- AsyncStream for internal components")
    print("- Thread-safe state management")
    print("- No more fetchEvents methods needed!")
    
    exit(0)
}