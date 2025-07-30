import Foundation
import NDKSwift

struct Example04_UserProfile {
    static func run() async throws {
        print("👤 NDKSwift Example: User Profiles")
        print("==================================\n")
        
        // Step 1: Setup NDK
        let ndk = NDK(relayUrls: [RelayConstants.primal, RelayConstants.damus])
        await ndk.connect()
        print("✅ Connected to relays")
        
        // Step 2: Fetch a user's profile
        // Using jack's pubkey as an example
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        print("\n📥 Fetching user profile...")
        
        // Create a filter for profile metadata (kind 0)
        let profileFilter = NDKFilter(
            authors: [jackPubkey],
            kinds: [EventKind.metadata]
        )
        
        // Fetch profile using profileManager
        var fetchedMetadata: NDKUserMetadata?
        for await metadata in await ndk.profileManager.observe(for: jackPubkey) {
            fetchedMetadata = metadata
            break // Get first result
        }
        
        if let metadata = fetchedMetadata {
            print("✅ Profile found!")
            print("📍 Name: \(metadata.name ?? "N/A")")
            print("📍 Display Name: \(metadata.displayName ?? "N/A")")
            print("📍 About: \(String((metadata.about ?? "N/A").prefix(100)))...")
            print("📍 Picture: \(metadata.picture != nil ? "✓" : "✗")")
            print("📍 NIP-05: \(metadata.nip05 ?? "N/A")")
            print("📍 Lightning: \(metadata.lud16 ?? metadata.lud06 ?? "N/A")")
        } else {
            print("❌ Profile not found")
        }
        
        // Step 3: Create and publish your own profile
        print("\n📤 Creating and publishing a new profile...")
        
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let myMetadata = [
            "name": "ndkswift_example",
            "display_name": "NDKSwift Example User",
            "about": "Learning Nostr development with NDKSwift! 🚀",
            "picture": "https://robohash.org/ndkswiftexample.png",
            "nip05": "example@nostr.directory",
            "lud16": "example@getalby.com",
            "website": "https://github.com/nostr-dev-kit/ndk-swift"
        ]
        
        // Create metadata event
        let profileString = try JSONCoding.encodeToString(myMetadata)
        
        let (profileEvent, result) = try await ndk.publish { builder in
            builder
                .content(profileString)
                .kind(EventKind.metadata)
        }
        print("✅ Profile published!")
        print("📍 Event ID: \(profileEvent.id)")
        print("📊 Published to \(result.count) relay(s)")
        
        // Step 4: Fetch multiple profiles at once
        print("\n📥 Fetching multiple profiles...")
        
        let pubkeys = [
            jackPubkey,
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
            try await signer.pubkey // our new pubkey
        ]
        
        // Create a filter for multiple profiles
        let multiProfileFilter = NDKFilter(
            authors: pubkeys,
            kinds: [EventKind.metadata]
        )
        
        // Fetch profiles for multiple users
        var foundProfiles = 0
        for pubkey in pubkeys {
            for await metadata in await ndk.profileManager.observe(for: pubkey, maxAge: 0) {
                if let metadata = metadata {
                    foundProfiles += 1
                    print("\n👤 Profile: \(metadata.name ?? "Unknown")")
                    print("   Pubkey: \(String(pubkey.prefix(16)))...")
                }
                break // Get first result
            }
        }
        
        print("\n📊 Found \(foundProfiles) profiles")
        
        // Step 5: Subscribe to profile updates
        print("\n📡 Subscribing to profile updates (5 seconds)...")
        
        let updateFilter = NDKFilter(
            kinds: [EventKind.metadata],
            since: Timestamp(Date().timeIntervalSince1970)
        )
        
        let updateSource = ndk.observe(filter: updateFilter, cachePolicy: .networkOnly)
        
        let subscriptionTask = Task {
            var updateCount = 0
            for await event in updateSource.events {
                updateCount += 1
                if event.kind == EventKind.metadata {
                    let metadata = NDKUserMetadata(event: event)
                    print("🔔 Profile update #\(updateCount): \(metadata.name ?? "Unknown")")
                }
                if updateCount >= 3 {
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 5_000_000_000)
        subscriptionTask.cancel()
        
        // Step 6: Disconnect
        await ndk.disconnect()
        
        print("\n📚 Key Concepts:")
        print("- Profiles are stored in kind 0 events")
        print("- Use observe() with metadata filter to fetch profiles")
        print("- NIP-05 provides human-readable identifiers")
        print("- Lightning addresses enable zaps (tips)")
        print("- Profile events can be subscribed to for real-time updates")
    }
}