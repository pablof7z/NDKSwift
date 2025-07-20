import Foundation
import NDKSwift

/// Individual feature showcase scripts that can be run separately
/// Each demonstrates a specific aspect of the declarative API

// MARK: - 1. Basic Data Source

@main
struct BasicDataSourceDemo {
    static func main() async {
        print("📊 Basic Data Source Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://nos.lol"])
        await ndk.waitForRelayConnections(minimumRelays: 1)
        
        // Create a simple data source for Bitcoin-related notes
        let bitcoinNotes = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                kinds: [1],
                limit: 10,
                tags: ["t": ["bitcoin"]]
            )
        )
        
        print("⏳ Fetching Bitcoin-related notes...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let notes = await bitcoinNotes.data
        print("📝 Found \(notes.count) Bitcoin notes\n")
        
        for (i, note) in notes.prefix(3).enumerated() {
            print("[\(i+1)] \(String(note.content.prefix(100)))...")
        }
    }
}

// MARK: - 2. Transform Demo

struct TransformDemo {
    struct SimpleNote {
        let author: String
        let content: String
        let timestamp: Date
    }
    
    static func main() async {
        print("🔄 Transform Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io"])
        await ndk.waitForRelayConnections()
        
        // Create data source with custom transform
        let simpleNotes = await NDKDataSource<SimpleNote>(
            ndk: ndk,
            filter: NDKFilter(kinds: [1], limit: 5)
        ) { event in
            SimpleNote(
                author: String(event.pubkey.prefix(8)) + "...",
                content: event.content,
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt))
            )
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let notes = await simpleNotes.data
        for note in notes {
            print("👤 \(note.author)")
            print("📅 \(note.timestamp)")
            print("💬 \(String(note.content.prefix(50)))...\n")
        }
    }
}

// MARK: - 3. Reactive Updates Demo

struct ReactiveUpdatesDemo {
    static func main() async {
        print("🔄 Reactive Updates Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://relay.nostr.band"])
        await ndk.waitForRelayConnections(minimumRelays: 2)
        
        // Monitor a specific tag for real-time updates
        let nostrTopic = await NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(
                kinds: [1],
                since: Timestamp(Date().timeIntervalSince1970 - 300), // Last 5 minutes
                tags: ["t": ["nostr"]]
            )
        )
        
        print("👀 Monitoring #nostr topic...")
        print("Initial count: \(await nostrTopic.data.count)")
        
        // Check periodically for new events
        for i in 1...3 {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            print("Update \(i): \(await nostrTopic.data.count) events")
        }
    }
}

// MARK: - 4. Profile Fetching Demo

struct ProfileFetchingDemo {
    static func main() async {
        print("👤 Profile Fetching Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://purplepag.es"])
        await ndk.waitForRelayConnections()
        
        // Notable Nostr users
        let notableUsers = [
            ("82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", "jack"),
            ("3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", "fiatjaf"),
            ("32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245", "jb55")
        ]
        
        // Create profile data sources
        var profileSources: [(String, NDKDataSource<NDKUserProfile>)] = []
        
        for (pubkey, name) in notableUsers {
            let profileData = await NDKDataSource<NDKUserProfile>(
                ndk: ndk,
                filter: NDKFilter(authors: [pubkey], kinds: [0], limit: 1)
            ) { event in
                guard let data = event.content.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: data) else {
                    return nil
                }
                return profile
            }
            profileSources.append((name, profileData))
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        print("📋 Profiles:\n")
        for (expectedName, source) in profileSources {
            if let profile = await source.data.first {
                let displayName = profile.displayName ?? profile.name ?? "Unknown"
                print("✅ \(expectedName): \(displayName)")
                if let about = profile.about {
                    print("   Bio: \(String(about.prefix(60)))...")
                }
            } else {
                print("❌ \(expectedName): Not found")
            }
            print()
        }
    }
}

// MARK: - 5. Tag Filtering Demo

struct TagFilteringDemo {
    static func main() async {
        print("🏷️ Tag Filtering Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://relay.nostr.band"])
        await ndk.waitForRelayConnections()
        
        // Create data sources for different hashtags
        let topics = ["bitcoin", "nostr", "lightning", "programming"]
        var topicSources: [(String, NDKDataSource<NDKEvent>)] = []
        
        print("📊 Creating data sources for topics: \(topics.joined(separator: ", "))")
        
        for topic in topics {
            let source = await NDKDataSource<NDKEvent>(
                ndk: ndk,
                filter: NDKFilter(
                    kinds: [1],
                    since: Timestamp(Date().timeIntervalSince1970 - 3600), // Last hour
                    limit: 20,
                    tags: ["t": [topic]]
                )
            )
            topicSources.append((topic, source))
        }
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        print("\n📈 Topic Activity (last hour):\n")
        for (topic, source) in topicSources {
            let count = await source.data.count
            let bar = String(repeating: "█", count: min(count, 20))
            print("#\(topic): \(bar) (\(count))")
        }
    }
}

// MARK: - 6. Complex Filter Demo

struct ComplexFilterDemo {
    static func main() async {
        print("🔍 Complex Filter Demo\n")
        
        let ndk = NDK(relayUrls: ["wss://relay.damus.io", "wss://relay.nostr.band"])
        await ndk.waitForRelayConnections()
        
        // Monitor multiple event types from specific authors
        let authors = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ]
        
        // Different event types
        let eventTypes = [
            (kinds: [1], name: "Notes"),
            (kinds: [6], name: "Reposts"),
            (kinds: [7], name: "Reactions"),
            (kinds: [3], name: "Contact Lists"),
            (kinds: [0], name: "Metadata")
        ]
        
        print("📊 Monitoring activity from selected authors...\n")
        
        var sources: [(String, NDKDataSource<NDKEvent>)] = []
        
        for (kinds, name) in eventTypes {
            let source = await NDKDataSource<NDKEvent>(
                ndk: ndk,
                filter: NDKFilter(
                    authors: authors,
                    kinds: kinds,
                    since: Timestamp(Date().timeIntervalSince1970 - 86400), // Last 24h
                    limit: 50
                )
            )
            sources.append((name, source))
        }
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        for (name, source) in sources {
            let count = await source.data.count
            print("\(name): \(count) events")
        }
    }
}

// MARK: - Helper to run specific demos

enum DemoChoice: String, CaseIterable {
    case basic = "1"
    case transform = "2"
    case reactive = "3"
    case profile = "4"
    case tags = "5"
    case complex = "6"
    
    var name: String {
        switch self {
        case .basic: return "Basic Data Source"
        case .transform: return "Transform Demo"
        case .reactive: return "Reactive Updates"
        case .profile: return "Profile Fetching"
        case .tags: return "Tag Filtering"
        case .complex: return "Complex Filters"
        }
    }
    
    func run() async {
        switch self {
        case .basic: await BasicDataSourceDemo.main()
        case .transform: await TransformDemo.main()
        case .reactive: await ReactiveUpdatesDemo.main()
        case .profile: await ProfileFetchingDemo.main()
        case .tags: await TagFilteringDemo.main()
        case .complex: await ComplexFilterDemo.main()
        }
    }
}

// Uncomment the demo you want to run:
// await DemoChoice.basic.run()
// await DemoChoice.transform.run()
// await DemoChoice.reactive.run()
// await DemoChoice.profile.run()
// await DemoChoice.tags.run()
// await DemoChoice.complex.run()