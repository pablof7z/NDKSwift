import Foundation
import NDKSwift

/// Minimal demo that uses only the working parts of the declarative API
/// This demonstrates the core concepts without relying on components that need migration

@main
struct MinimalDeclarativeDemo {
    static func main() async {
        print("🚀 NDKSwift Minimal Declarative Demo")
        print("=====================================\n")
        
        // Create NDK with in-memory cache (simplest setup)
        let ndk = NDK(
            relayUrls: ["wss://relay.damus.io"],
            cache: MemoryCache()
        )
        
        // Disable outbox to avoid components that might not be migrated yet
        ndk.outboxEnabled = false
        
        print("⏳ Waiting for relay connection...")
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5.0)
        print("✅ Connected to \(connected) relay(s)\n")
        
        // Demo 1: Basic event fetching with declarative API
        await demoBasicFetch(ndk: ndk)
        
        // Demo 2: Transform feature
        await demoTransform(ndk: ndk)
        
        // Demo 3: Multiple data sources (temporal grouping)
        await demoTemporalGrouping(ndk: ndk)
        
        print("\n✅ Demo completed!")
    }
    
    static func demoBasicFetch(ndk: NDK) async {
        print("📋 Demo 1: Basic Event Fetching")
        print("--------------------------------")
        
        // Create a data source for recent notes
        let recentNotes = await ndk.observe(
            filter: NDKFilter(
                kinds: [1],
                limit: 5
            )
        )
        
        // Give it a moment to fetch
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let notes = await recentNotes.data
        print("Found \(notes.count) recent notes")
        
        if let firstNote = notes.first {
            print("Sample: \"\(String(firstNote.content.prefix(50)))...\"")
            print("Author: \(String(firstNote.pubkey.prefix(16)))...")
        }
        print()
    }
    
    static func demoTransform(ndk: NDK) async {
        print("🔄 Demo 2: Transform Feature")
        print("----------------------------")
        
        struct SimpleProfile {
            let name: String
            let about: String?
        }
        
        // Fetch a known profile (jack)
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        let profileData = await ndk.observe(
            filter: NDKFilter(
                authors: [jackPubkey],
                kinds: [0],
                limit: 1
            )
        ) { event in
            // Transform NDKEvent to SimpleProfile
            guard let data = event.content.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            return SimpleProfile(
                name: json["name"] as? String ?? "Unknown",
                about: json["about"] as? String
            )
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        if let profile = await profileData.data.first {
            print("Profile found!")
            print("Name: \(profile.name)")
            if let about = profile.about {
                print("About: \(String(about.prefix(50)))...")
            }
        } else {
            print("Profile not found")
        }
        print()
    }
    
    static func demoTemporalGrouping(ndk: NDK) async {
        print("⏱️ Demo 3: Temporal Grouping")
        print("----------------------------")
        print("Creating multiple data sources rapidly...")
        
        // Create 3 data sources for different kinds quickly
        let kinds: [(Int, String)] = [
            (0, "Profiles"),
            (1, "Notes"),
            (3, "Contact Lists")
        ]
        
        var dataSources: [(String, NDKDataSource<NDKEvent>)] = []
        
        for (kind, name) in kinds {
            let ds = await ndk.observe(
                filter: NDKFilter(
                    kinds: [kind],
                    limit: 3
                )
            )
            dataSources.append((name, ds))
        }
        
        print("Created \(dataSources.count) data sources")
        print("(These should be grouped internally for efficiency)")
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("\nResults:")
        for (name, ds) in dataSources {
            let count = await ds.data.count
            print("- \(name): \(count) events")
        }
    }
}