import Foundation
import NDKSwift

/// Demonstrates the new declarative API for NDKSwift
/// Shows how to use NDKDataSource for automatic subscription management

@main
struct DeclarativeDemo {
    static func main() async {
        print("NDKSwift Declarative API Demo")
        print("=============================\n")
        
        // Initialize NDK with SQLite cache
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol"
            ]
        )
        
        // Wait for relays to connect (proper implementation)
        let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5.0)
        print("Connected to \(connectedCount) relay(s)\n")
        
        await demonstrateBasicUsage(ndk: ndk)
        await demonstrateMultipleDataSources(ndk: ndk)
        await demonstrateTemporalGrouping(ndk: ndk)
        
        print("\nDemo completed!")
    }
    
    static func demonstrateBasicUsage(ndk: NDK) async {
        print("1. Basic Usage - Fetching Profile")
        print("---------------------------------")
        
        // Jack Dorsey's pubkey
        let pubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        let profileData = await ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [0],
                limit: 1
            )
        ) { event in
            // Transform event to profile
            let content = event.content
            guard !content.isEmpty,
                  let data = content.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: data) else {
                return nil
            }
            return profile
        }
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let profileDataCopy = await profileData.data
        if let profile = profileDataCopy.first {
            print("✓ Found profile: \(profile.displayName ?? profile.name ?? "Unknown")")
            print("  Bio: \(profile.about ?? "No bio")")
        } else {
            print("✗ No profile found")
        }
        
        print("\n")
    }
    
    static func demonstrateMultipleDataSources(ndk: NDK) async {
        print("2. Multiple Data Sources")
        print("------------------------")
        
        // Create multiple data sources that will be automatically grouped
        let authors = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"  // fiatjaf
        ]
        
        // These will be grouped into a single subscription internally
        let notes = await ndk.observe(
            filter: NDKFilter(authors: authors, kinds: [1], limit: 10)
        )
        
        let reactions = await ndk.observe(
            filter: NDKFilter(authors: authors, kinds: [7], limit: 20)
        )
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let notesData = await notes.data
        let reactionsData = await reactions.data
        
        print("✓ Notes collected: \(notesData.count)")
        print("✓ Reactions collected: \(reactionsData.count)")
        
        // Show sample note
        if let firstNote = notesData.first {
            print("\nSample note:")
            print("  Author: \(String(firstNote.pubkey.prefix(8)))...")
            print("  Content: \(String(firstNote.content.prefix(50)))...")
        }
        
        print("\n")
    }
    
    static func demonstrateTemporalGrouping(ndk: NDK) async {
        print("3. Temporal Grouping Demo")
        print("-------------------------")
        
        // Create multiple data sources rapidly - they should be grouped
        var dataSources: [NDKDataSource<NDKEvent>] = []
        
        print("Creating 5 data sources within 100ms window...")
        
        // Create 5 data sources for different authors
        let testPubkeys = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
            "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245",
            "00000000827ffaa94bfea288c3dfce4422c794fbb96625b6b31e9049f729d700",
            "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93"
        ]
        
        for pubkey in testPubkeys {
            let dataSource = await ndk.observe(
                filter: NDKFilter(
                    authors: [pubkey],
                    kinds: [0],
                    limit: 1
                )
            )
            dataSources.append(dataSource)
        }
        
        print("✓ Created \(dataSources.count) data sources rapidly")
        print("  These should be grouped into fewer subscriptions internally")
        print("  (Check debug logs to verify grouping behavior)")
        
        // Wait for any data
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        var profilesFound = 0
        for dataSource in dataSources {
            let data = await dataSource.data
            if !data.isEmpty {
                profilesFound += 1
            }
        }
        
        print("✓ Found \(profilesFound) profiles out of \(dataSources.count) requested")
    }
}

// MARK: - Helper Extensions

extension NDKEvent {
    var referencedEventId: String? {
        // Find 'e' tag
        tags.first { $0.count > 1 && $0[0] == "e" }?[1]
    }
}