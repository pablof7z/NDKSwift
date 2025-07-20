import Foundation
import NDKSwift

/// Comprehensive demonstration of the declarative NDKSwift API
/// Shows all implemented features: data sources, cache observation, temporal grouping,
/// filter aggregation, and outbox model integration

@main
struct ComprehensiveDeclarativeDemo {
    static func main() async {
        print("🚀 NDKSwift Comprehensive Declarative API Demo")
        print("=" * 50 + "\n")
        
        do {
            // Initialize NDK with SQLite cache for persistence
            let cachePath = FileManager.default.temporaryDirectory.appendingPathComponent("demo_cache.db").path
            let cache = try await NDKSQLiteCache(path: cachePath)
        
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol",
                "wss://relay.primal.net"
            ],
            cache: cache
        )
        
        // Enable outbox model (it's on by default, but being explicit)
        ndk.outboxEnabled = true
        
        // Wait for relay connections
        print("⏳ Connecting to relays...")
        let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 2, timeout: 10.0)
        print("✅ Connected to \(connectedCount) relay(s)\n")
        
        // Run all demonstrations
        await demonstrateCacheObservation(ndk: ndk)
        await demonstrateTemporalGrouping(ndk: ndk)
        await demonstrateFilterAggregation(ndk: ndk)
        await demonstrateOutboxModel(ndk: ndk)
        await demonstrateComplexScenario(ndk: ndk)
        
        print("\n🎉 Demo completed!")
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - 1. Cache Observation Demo
    
    static func demonstrateCacheObservation(ndk: NDK) async {
        print("📦 1. Cache Observation Demo")
        print("-" * 30)
        print("Shows how cache automatically notifies data sources of new events\n")
        
        // Create a data source for a specific author
        let fiatjafPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        
        let notesData = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                authors: [fiatjafPubkey],
                kinds: [1], // text notes
                limit: 5
            )
        )
        
        print("📊 Initial data count: \(await notesData.data.count)")
        
        // Simulate cache update (in real app, this happens when events arrive)
        print("💾 Simulating cache updates...")
        
        // Wait a bit for any real events
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("📊 Updated data count: \(await notesData.data.count)")
        
        if await !notesData.data.isEmpty {
            let firstNote = await notesData.data.first!
            print("📝 Sample note: \(String(firstNote.content.prefix(60)))...")
        }
        
        print()
    }
    
    // MARK: - 2. Temporal Grouping Demo
    
    static func demonstrateTemporalGrouping(ndk: NDK) async {
        print("⏱️ 2. Temporal Grouping Demo")
        print("-" * 30)
        print("Shows how multiple data sources created within 100ms are grouped\n")
        
        let pubkeys = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
            "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", // jb55
            "00000000827ffaa94bfea288c3dfce4422c794fbb96625b6b31e9049f729d700", // anthony
            "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93"  // Gigi
        ]
        
        print("🔄 Creating 5 data sources rapidly (should be grouped)...")
        
        var dataSources: [NDKDataSource<NDKUserProfile>] = []
        
        // Create all data sources as fast as possible
        for pubkey in pubkeys {
            let ds = await NDKDataSource<NDKUserProfile>(
                ndk: ndk,
                filter: NDKFilter(
                    authors: [pubkey],
                    kinds: [0], // metadata
                    limit: 1
                )
            ) { event in
                // Transform to profile
                guard let data = event.content.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: data) else {
                    return nil
                }
                return profile
            }
            dataSources.append(ds)
        }
        
        print("✅ Created \(dataSources.count) data sources")
        print("💡 These should be internally grouped into fewer subscriptions")
        print("   (Enable debug logs to see actual subscription count)")
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Check results
        var foundProfiles = 0
        for (index, ds) in dataSources.enumerated() {
            let data = await ds.data
            if let profile = data.first {
                foundProfiles += 1
                let name = profile.displayName ?? profile.name ?? "Unknown"
                print("👤 [\(index + 1)] Found: \(name)")
            }
        }
        
        print("📊 Found \(foundProfiles)/\(dataSources.count) profiles")
        print()
    }
    
    // MARK: - 3. Filter Aggregation Demo
    
    static func demonstrateFilterAggregation(ndk: NDK) async {
        print("🔀 3. Filter Aggregation Demo")
        print("-" * 30)
        print("Shows how filters are intelligently combined\n")
        
        // Create multiple overlapping filters
        print("📋 Creating data sources with overlapping filters...")
        
        // Data source 1: Jack's notes and reactions
        let ds1 = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                authors: ["82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"],
                kinds: [1, 7], // notes and reactions
                limit: 10
            )
        )
        
        // Data source 2: Fiatjaf's notes
        let ds2 = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                authors: ["3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
                kinds: [1], // just notes
                limit: 5
            )
        )
        
        // Data source 3: Both authors' reactions
        let ds3 = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                authors: [
                    "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
                    "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
                ],
                kinds: [7], // reactions
                limit: 20
            )
        )
        
        print("✅ Created 3 data sources with overlapping filters")
        print("🔄 Internal aggregation will optimize these into efficient subscriptions")
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("\n📊 Results:")
        print("  DS1 (Jack's notes+reactions): \(await ds1.data.count) events")
        print("  DS2 (Fiatjaf's notes): \(await ds2.data.count) events")
        print("  DS3 (Both authors' reactions): \(await ds3.data.count) events")
        
        print()
    }
    
    // MARK: - 4. Outbox Model Demo
    
    static func demonstrateOutboxModel(ndk: NDK) async {
        print("📬 4. Outbox Model Demo")
        print("-" * 30)
        print("Shows how subscriptions are routed to author-specific relays\n")
        
        // For this demo, we'll track specific authors who likely have different relay preferences
        let authors = [
            ("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", "jack"),
            ("3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", "fiatjaf"),
            ("32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", "jb55")
        ]
        
        print("🔍 Fetching relay lists (NIP-65) for authors...")
        
        // First, fetch relay lists to see where each author publishes
        for (pubkey, name) in authors {
            let relayListData = await NDKDataSource<[String]>(
                ndk: ndk,
                filter: NDKFilter(
                    authors: [pubkey],
                    kinds: [10002], // NIP-65 relay list
                    limit: 1
                )
            ) { event in
                // Extract relay URLs from 'r' tags
                var relays: [String] = []
                for tag in event.tags {
                    if tag.count >= 2 && tag[0] == "r" {
                        relays.append(tag[1])
                    }
                }
                return relays.isEmpty ? nil : relays
            }
            
            // Wait a bit
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if let relayList = await relayListData.data.first {
                print("📡 \(name)'s relays: \(relayList.prefix(3).joined(separator: ", "))")
                if relayList.count > 3 {
                    print("    (and \(relayList.count - 3) more...)")
                }
            } else {
                print("❓ \(name): No relay list found")
            }
        }
        
        print("\n🚀 Creating subscription for all authors...")
        print("   The outbox model will route to appropriate relays automatically!")
        
        // Now create a data source for all authors
        let allAuthorsData = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                authors: authors.map { $0.0 },
                kinds: [1],
                limit: 15
            )
        )
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let events = await allAuthorsData.data
        print("\n📊 Fetched \(events.count) notes total")
        
        // Count by author
        var eventsByAuthor: [String: Int] = [:]
        for event in events {
            eventsByAuthor[event.pubkey, default: 0] += 1
        }
        
        for (pubkey, name) in authors {
            let count = eventsByAuthor[pubkey] ?? 0
            print("  \(name): \(count) notes")
        }
        
        print()
    }
    
    // MARK: - 5. Complex Real-World Scenario
    
    static func demonstrateComplexScenario(ndk: NDK) async {
        print("🌟 5. Complex Real-World Scenario")
        print("-" * 30)
        print("Simulates a social feed with replies and reactions\n")
        
        // Get some popular notes first
        let popularNotes = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                kinds: [1],
                limit: 5
            )
        )
        
        // Wait for notes
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        let notes = await popularNotes.data
        guard !notes.isEmpty else {
            print("❌ No notes found for complex demo")
            return
        }
        
        print("📝 Found \(notes.count) recent notes")
        
        // For each note, create data sources for replies and reactions
        var replySources: [NDKDataSource<NDKEvent>] = []
        var reactionSources: [NDKDataSource<String>] = []
        
        for note in notes.prefix(3) {
            // Replies (kind 1 with 'e' tag referencing the note)
            let replySource = await NDKDataSource<NDKEvent>(
                ndk: ndk,
                filter: NDKFilter(
                    kinds: [1],
                    limit: 10,
                    tags: ["e": [note.id]]
                )
            )
            replySources.append(replySource)
            
            // Reactions (kind 7 with 'e' tag)
            let reactionSource = await NDKDataSource<String>(
                ndk: ndk,
                filter: NDKFilter(
                    kinds: [7],
                    limit: 50,
                    tags: ["e": [note.id]]
                )
            ) { event in
                // Extract reaction content (emoji or +/-)
                return event.content.isEmpty ? "👍" : event.content
            }
            reactionSources.append(reactionSource)
        }
        
        print("🔄 Created \(replySources.count * 2) data sources for replies and reactions")
        print("   These will be efficiently grouped and routed via outbox model")
        
        // Wait for all data
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        
        print("\n📊 Results for top 3 notes:")
        for (index, note) in notes.prefix(3).enumerated() {
            let replies = await replySources[index].data
            let reactions = await reactionSources[index].data
            
            let preview = String(note.content.prefix(50))
                .replacingOccurrences(of: "\n", with: " ")
            
            print("\n📄 Note \(index + 1): \"\(preview)...\"")
            print("  💬 Replies: \(replies.count)")
            print("  ❤️ Reactions: \(reactions.count)")
            
            if !reactions.isEmpty {
                // Count unique reactions
                let uniqueReactions = Dictionary(grouping: reactions) { $0 }
                    .mapValues { $0.count }
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                
                print("  🎯 Top reactions: " + uniqueReactions
                    .map { "\($0.key)×\($0.value)" }
                    .joined(separator: " "))
            }
        }
        
        print()
    }
}

// MARK: - Helper Extensions

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}