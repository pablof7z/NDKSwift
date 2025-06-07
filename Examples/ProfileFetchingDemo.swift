#!/usr/bin/env swift

import Foundation
import NDKSwift

// Profile Fetching Demo
// This example demonstrates the various ways to fetch user profiles in NDKSwift

@main
struct ProfileFetchingDemo {
    static func main() async {
        print("🚀 NDKSwift Profile Fetching Demo")
        print("=================================\n")
        
        // Initialize NDK
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol"
            ],
            profileConfig: NDKProfileConfig(
                cacheSize: 100,
                staleAfter: 300, // 5 minutes
                batchRequests: true,
                batchDelay: 0.1
            )
        )
        
        // Connect to relays
        print("📡 Connecting to relays...")
        await ndk.connect()
        
        // Demo 1: Fetch a single profile
        await fetchSingleProfile(ndk: ndk)
        
        // Demo 2: Fetch multiple profiles with batching
        await fetchMultipleProfiles(ndk: ndk)
        
        // Demo 3: Demonstrate caching behavior
        await demonstrateCaching(ndk: ndk)
        
        // Demo 4: Fetch profiles for a thread
        await fetchThreadProfiles(ndk: ndk)
        
        // Disconnect
        await ndk.disconnect()
        print("\n✅ Demo completed!")
    }
    
    static func fetchSingleProfile(ndk: NDK) async {
        print("\n📋 Demo 1: Fetching a single profile")
        print("------------------------------------")
        
        // Jack Dorsey's pubkey
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        do {
            let user = ndk.getUser(jackPubkey)
            
            let startTime = Date()
            if let profile = try await user.fetchProfile() {
                let elapsed = Date().timeIntervalSince(startTime)
                
                print("✅ Profile fetched in \(String(format: "%.2f", elapsed))s")
                print("   Name: \(profile.name ?? "N/A")")
                print("   Display: \(profile.displayName ?? "N/A")")
                print("   About: \(profile.about?.prefix(100) ?? "N/A")...")
                print("   Picture: \(profile.picture ?? "N/A")")
                print("   NIP-05: \(profile.nip05 ?? "N/A")")
            } else {
                print("❌ No profile found")
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func fetchMultipleProfiles(ndk: NDK) async {
        print("\n📋 Demo 2: Fetching multiple profiles with batching")
        print("--------------------------------------------------")
        
        // Some well-known Nostr pubkeys
        let pubkeys = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", // jb55
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
            "97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322", // hodlbod
            "ee11a5dff40c19a555f41fe42b48f00e618c91225622ae37b6c2bb67b76c4e49"  // Michael Dilger
        ]
        
        do {
            let startTime = Date()
            let profiles = try await ndk.profileManager.fetchProfiles(for: pubkeys)
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("✅ Fetched \(profiles.count) profiles in \(String(format: "%.2f", elapsed))s")
            
            for (index, pubkey) in pubkeys.enumerated() {
                if let profile = profiles[pubkey] {
                    let shortPubkey = String(pubkey.prefix(8)) + "..."
                    print("   \(index + 1). \(shortPubkey): \(profile.displayName ?? profile.name ?? "Unknown")")
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func demonstrateCaching(ndk: NDK) async {
        print("\n📋 Demo 3: Demonstrating cache behavior")
        print("---------------------------------------")
        
        let pubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        let user = ndk.getUser(pubkey)
        
        do {
            // First fetch (from network)
            let start1 = Date()
            _ = try await user.fetchProfile()
            let time1 = Date().timeIntervalSince(start1)
            print("✅ First fetch: \(String(format: "%.2f", time1))s (from network)")
            
            // Second fetch (from cache)
            let start2 = Date()
            _ = try await user.fetchProfile()
            let time2 = Date().timeIntervalSince(start2)
            print("✅ Second fetch: \(String(format: "%.3f", time2))s (from cache)")
            
            // Force refresh
            let start3 = Date()
            _ = try await user.fetchProfile(forceRefresh: true)
            let time3 = Date().timeIntervalSince(start3)
            print("✅ Force refresh: \(String(format: "%.2f", time3))s (from network)")
            
            // Cache stats
            let stats = await ndk.profileManager.getCacheStats()
            print("\n📊 Cache statistics:")
            print("   Cached profiles: \(stats.size)")
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func fetchThreadProfiles(ndk: NDK) async {
        print("\n📋 Demo 4: Fetching profiles for a thread")
        print("-----------------------------------------")
        
        do {
            // Fetch some recent text notes
            let filter = NDKFilter(
                kinds: [EventKind.textNote],
                limit: 10
            )
            
            print("🔍 Fetching recent notes...")
            let events = try await ndk.fetchEvents(filters: [filter])
            
            // Get unique authors
            let authors = Array(Set(events.map { $0.pubkey }))
            print("📊 Found \(events.count) notes from \(authors.count) unique authors")
            
            // Fetch all profiles at once
            let startTime = Date()
            let profiles = try await ndk.profileManager.fetchProfiles(for: authors)
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("✅ Fetched \(profiles.count) profiles in \(String(format: "%.2f", elapsed))s")
            
            // Display thread with profiles
            print("\n💬 Recent notes with profiles:")
            for (index, event) in events.prefix(5).enumerated() {
                let profile = profiles[event.pubkey]
                let displayName = profile?.displayName ?? profile?.name ?? "Unknown"
                let content = event.content.prefix(50)
                print("   \(index + 1). \(displayName): \(content)...")
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
}