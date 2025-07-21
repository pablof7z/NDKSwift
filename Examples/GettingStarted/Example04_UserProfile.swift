import Foundation
import NDKSwift

struct Example04_UserProfile {
    static func run() async throws {
        print("👤 NDKSwift Example: User Profiles")
        print("==================================\n")
        
        // Step 1: Setup NDK
        let ndk = NDK(relayUrls: ["wss://relay.primal.net", "wss://relay.damus.io"])
        await ndk.connect()
        print("✅ Connected to relays")
        
        // Step 2: Fetch a user's profile
        // Using jack's pubkey as an example
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        print("\n📥 Fetching user profile...")
        
        // Create a filter for profile metadata (kind 0)
        let profileFilter = NDKFilter(
            authors: [jackPubkey],
            kinds: [EventKind.metadata],
            limit: 1
        )
        
        // Fetch profile using observe
        let profileSource = ndk.observe(filter: profileFilter, cachePolicy: .cacheWithNetwork)
        
        // Wait for profile to arrive
        var fetchedProfile: NDKUserProfile?
        let fetchTask = Task {
            for await event in profileSource.events {
                if event.kind == EventKind.metadata,
                   let profileData = try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data()) {
                    fetchedProfile = profileData
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        fetchTask.cancel()
        
        if let profile = fetchedProfile {
            print("✅ Profile found!")
            print("📍 Name: \(profile.name ?? "N/A")")
            print("📍 Display Name: \(profile.displayName ?? "N/A")")
            print("📍 About: \(String((profile.about ?? "N/A").prefix(100)))...")
            print("📍 Picture: \(profile.picture != nil ? "✓" : "✗")")
            print("📍 NIP-05: \(profile.nip05 ?? "N/A")")
            print("📍 Lightning: \(profile.lud16 ?? profile.lud06 ?? "N/A")")
        } else {
            print("❌ Profile not found")
        }
        
        // Step 3: Create and publish your own profile
        print("\n📤 Creating and publishing a new profile...")
        
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let myProfile = NDKUserProfile(
            name: "ndkswift_example",
            displayName: "NDKSwift Example User",
            about: "Learning Nostr development with NDKSwift! 🚀",
            picture: "https://robohash.org/ndkswiftexample.png",
            banner: nil,
            nip05: "example@nostr.directory",
            lud16: "example@getalby.com",
            lud06: nil,
            website: "https://github.com/nostr-dev-kit/ndk-swift"
        )
        
        // Create metadata event manually
        let profileContent = try JSONEncoder().encode(myProfile)
        let profileString = String(data: profileContent, encoding: .utf8)!
        
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
        
        let multiProfileSource = ndk.observe(filter: multiProfileFilter, cachePolicy: .cacheWithNetwork)
        var profileEvents: [NDKEvent] = []
        
        let multiTask = Task {
            for await event in multiProfileSource.events {
                profileEvents.append(event)
                if profileEvents.count >= pubkeys.count {
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        multiTask.cancel()
        
        print("📊 Found \(profileEvents.count) profile events")
        
        for event in profileEvents {
            if event.kind == EventKind.metadata,
               let profileData = try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data()) {
                print("\n👤 Profile: \(profileData.name ?? "Unknown")")
                print("   Pubkey: \(String(event.pubkey.prefix(16)))...")
            }
        }
        
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
                if event.kind == EventKind.metadata,
                   let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data()) {
                    print("🔔 Profile update #\(updateCount): \(profile.name ?? "Unknown")")
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