// This is a standalone Swift script that demonstrates the declarative API concepts
// It shows what the API would look like if the migration was complete
// Run with: swift StandaloneDeclarativeDemo.swift

import Foundation

// Mock types to demonstrate the API
struct NDKEvent {
    let id: String
    let pubkey: String
    let content: String
    let kind: Int
    let createdAt: Int64
    let tags: [[String]]
}

struct NDKFilter {
    var kinds: [Int]?
    var authors: [String]?
    var limit: Int?
    var since: Int64?
    var tags: [[String]] = []
}

@MainActor
class NDKDataSource<T>: ObservableObject {
    @Published private(set) var data: [T] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    
    init(filter: NDKFilter, transform: ((NDKEvent) -> T?)? = nil) {
        print("🔄 Creating data source with filter:")
        print("   Kinds: \(filter.kinds ?? [])")
        print("   Authors: \(filter.authors?.map { String($0.prefix(8)) + "..." } ?? [])")
        print("   Limit: \(filter.limit ?? 0)")
        
        // Simulate async data loading
        Task {
            isLoading = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Simulate receiving events
            let mockEvents = createMockEvents(for: filter)
            
            if let transform = transform {
                data = mockEvents.compactMap(transform)
            } else if T.self == NDKEvent.self {
                data = mockEvents as! [T]
            }
            
            isLoading = false
            print("✅ Data source loaded \(data.count) items")
        }
    }
    
    private func createMockEvents(for filter: NDKFilter) -> [NDKEvent] {
        var events: [NDKEvent] = []
        let count = min(filter.limit ?? 5, 5)
        
        for i in 0..<count {
            let event = NDKEvent(
                id: UUID().uuidString,
                pubkey: filter.authors?.first ?? "mock_pubkey_\(i)",
                content: generateMockContent(for: filter.kinds?.first ?? 1),
                kind: filter.kinds?.first ?? 1,
                createdAt: Int64(Date().timeIntervalSince1970) - Int64(i * 60),
                tags: []
            )
            events.append(event)
        }
        
        return events
    }
    
    private func generateMockContent(for kind: Int) -> String {
        switch kind {
        case 0:
            return """
            {"name":"Mock User","about":"This is a mock profile for demo purposes","picture":"https://example.com/pic.jpg"}
            """
        case 1:
            return "This is a mock note #\(Int.random(in: 1...100)) demonstrating the declarative API!"
        case 3:
            return "Mock contact list data"
        case 7:
            return "👍"
        default:
            return "Mock event content for kind \(kind)"
        }
    }
}

// Demo functions
struct StandaloneDeclarativeDemo {
    static func main() async {
        print("🚀 NDKSwift Declarative API Demonstration")
        print("=========================================\n")
        
        await demonstrateBasicUsage()
        await demonstrateTransform()
        await demonstrateMultipleSources()
        await demonstrateComplexFilters()
        
        print("\n✨ Demo completed!")
        print("\nKey Features Demonstrated:")
        print("- ✅ Declarative data sources that auto-manage subscriptions")
        print("- ✅ Transform functions for data mapping")
        print("- ✅ Temporal grouping of multiple sources")
        print("- ✅ Complex filter combinations")
        print("- ✅ Automatic lifecycle management")
        print("\nAll without manual subscription management! 🎉")
    }
    
    @MainActor
    static func demonstrateBasicUsage() async {
        print("📌 1. Basic Usage - Simple Note Fetching")
        print("---------------------------------------")
        
        let notesData = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1],
                limit: 3
            )
        )
        
        // Wait for data
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        print("\nResults:")
        for (i, note) in notesData.data.enumerated() {
            print("  [\(i+1)] \(note.content)")
        }
        print()
    }
    
    @MainActor
    static func demonstrateTransform() async {
        print("📌 2. Transform Demo - Profile to Custom Type")
        print("--------------------------------------------")
        
        struct SimpleProfile {
            let name: String
            let about: String
        }
        
        let profileData = NDKDataSource<SimpleProfile>(
            filter: NDKFilter(
                kinds: [0],
                authors: ["82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"],
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
                about: json["about"] as? String ?? "No description"
            )
        }
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        if let profile = profileData.data.first {
            print("\nTransformed Profile:")
            print("  Name: \(profile.name)")
            print("  About: \(profile.about)")
        }
        print()
    }
    
    @MainActor
    static func demonstrateMultipleSources() async {
        print("📌 3. Multiple Data Sources (Temporal Grouping)")
        print("----------------------------------------------")
        print("Creating 3 data sources within 100ms window...\n")
        
        let authors = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
            "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        ]
        
        var sources: [NDKDataSource<NDKEvent>] = []
        
        // Create sources rapidly
        for author in authors {
            let source = NDKDataSource<NDKEvent>(
                filter: NDKFilter(
                    kinds: [1],
                    authors: [author],
                    limit: 2
                )
            )
            sources.append(source)
        }
        
        print("💡 In a real implementation, these would be grouped into fewer subscriptions")
        print("   due to the 100ms temporal grouping window\n")
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        print("Results:")
        for (i, source) in sources.enumerated() {
            print("  Author \(i+1): \(source.data.count) notes fetched")
        }
        print()
    }
    
    @MainActor
    static func demonstrateComplexFilters() async {
        print("📌 4. Complex Filters with Tag Support")
        print("-------------------------------------")
        
        // Complex filter with multiple criteria
        var complexFilter = NDKFilter(
            kinds: [1, 30023], // Notes and long-form content
            limit: 5
        )
        complexFilter.tags = [["t", "bitcoin"], ["t", "nostr"]] // Hashtag filters
        
        let complexData = NDKDataSource<NDKEvent>(filter: complexFilter)
        
        print("Filter includes:")
        print("  - Kinds: 1 (notes) and 30023 (articles)")
        print("  - Tags: #bitcoin and #nostr")
        print("  - Limit: 5 events")
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        print("\nIn production, this would fetch real events matching all criteria")
        print("Found \(complexData.data.count) matching events")
        print()
    }
}

// Run the demo
Task {
    await StandaloneDeclarativeDemo.main()
    exit(0)
}

RunLoop.main.run()