#!/usr/bin/env swift

// Standalone demo showing the FUNDAMENTAL features added in Step 2
// Run with: swift FundamentalFeaturesDemo.swift

import Foundation

// MARK: - Mock Types

struct NDKEvent {
    let id: String
    let pubkey: String
    let kind: Int
    let content: String
    let createdAt: Int64
    let tags: [[String]]
}

struct NDKFilter {
    var kinds: [Int]?
    var authors: [String]?
    var tags: [String: [String]]?
}

@MainActor
class NDKDataSource<T>: ObservableObject {
    @Published private(set) var data: [T] = []
    @Published private(set) var isLoading = false
    private let filter: NDKFilter
    private let ndk: NDK
    
    init(ndk: NDK, filter: NDKFilter) {
        self.ndk = ndk
        self.filter = filter
    }
    
    func start() async {
        isLoading = true
        
        // Simulate loading
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Add mock data based on filter
        if let kinds = filter.kinds {
            for kind in kinds {
                if kind == 1 {
                    data.append(NDKEvent(
                        id: UUID().uuidString,
                        pubkey: filter.authors?.first ?? "alice",
                        kind: 1,
                        content: "Hello from \(filter.authors?.first ?? "alice")",
                        createdAt: Int64(Date().timeIntervalSince1970),
                        tags: []
                    ) as! T)
                }
            }
        }
        
        isLoading = false
    }
}

class NDK {
    let cache = MockCache()
    let dataRequirementManager = MockDataRequirementManager()
    
    @MainActor
    func dataSource<T>(filter: NDKFilter) -> NDKDataSource<T> {
        return NDKDataSource(ndk: self, filter: filter)
    }
}

class MockCache {
    private var events: [String: (event: NDKEvent, relays: Set<String>)] = [:]
    
    func processEvent(_ event: NDKEvent, from relay: String, subscriptionId: String) async {
        // Store event with relay source
        if var existing = events[event.id] {
            existing.relays.insert(relay)
            events[event.id] = existing
        } else {
            events[event.id] = (event, [relay])
        }
        
        print("📥 Event \(event.id) received from relay: \(relay)")
    }
    
    func getRelaySources(eventId: String) async -> Set<String> {
        return events[eventId]?.relays ?? []
    }
}

class MockDataRequirementManager {
    // Simulates smart filter aggregation
    func aggregateFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        print("\n🔄 Smart Filter Aggregation:")
        print("Input: \(filters.count) filters")
        
        // Group compatible filters
        let groups = groupCompatibleFilters(filters)
        print("Output: \(groups.count) aggregated filter(s)")
        
        for (i, group) in groups.enumerated() {
            print("  Group \(i + 1): \(group.count) compatible filters combined")
        }
        
        return groups.map { aggregateSingleGroup($0) }
    }
    
    private func groupCompatibleFilters(_ filters: [NDKFilter]) -> [[NDKFilter]] {
        var groups: [[NDKFilter]] = []
        
        for filter in filters {
            var addedToGroup = false
            
            for i in 0..<groups.count {
                if canCombineFilters(groups[i][0], filter) {
                    groups[i].append(filter)
                    addedToGroup = true
                    break
                }
            }
            
            if !addedToGroup {
                groups.append([filter])
            }
        }
        
        return groups
    }
    
    private func canCombineFilters(_ f1: NDKFilter, _ f2: NDKFilter) -> Bool {
        // Check kinds compatibility
        if let k1 = f1.kinds, let k2 = f2.kinds {
            if Set(k1).isDisjoint(with: Set(k2)) {
                print("    ❌ Filters incompatible: no overlap in kinds")
                return false
            }
        }
        
        // Check authors compatibility
        if let a1 = f1.authors, let a2 = f2.authors {
            if Set(a1).isDisjoint(with: Set(a2)) {
                print("    ❌ Filters incompatible: no overlap in authors")
                return false
            }
        }
        
        print("    ✅ Filters compatible: can be combined efficiently")
        return true
    }
    
    private func aggregateSingleGroup(_ filters: [NDKFilter]) -> NDKFilter {
        var result = NDKFilter()
        
        // Merge all kinds
        var allKinds = Set<Int>()
        for f in filters {
            if let kinds = f.kinds {
                allKinds.formUnion(kinds)
            }
        }
        result.kinds = Array(allKinds)
        
        // Merge all authors
        var allAuthors = Set<String>()
        for f in filters {
            if let authors = f.authors {
                allAuthors.formUnion(authors)
            }
        }
        result.authors = Array(allAuthors)
        
        return result
    }
}

// MARK: - Demo

print("=== NDKSwift Fundamental Features Demo ===\n")

// Feature 1: Relay Source Tracking
print("📡 Feature 1: Relay Source Tracking")
print("Applications MUST know which relays provided each event (critical for NIP60 wallets)")

@MainActor
func demoRelayTracking() async {
    let ndk = NDK()
    let event = NDKEvent(
        id: "test123",
        pubkey: "alice",
        kind: 1,
        content: "Test message",
        createdAt: Int64(Date().timeIntervalSince1970),
        tags: []
    )
    
    // Process same event from multiple relays
    await ndk.cache.processEvent(event, from: "wss://relay1.example.com", subscriptionId: "sub1")
    await ndk.cache.processEvent(event, from: "wss://relay2.example.com", subscriptionId: "sub1")
    await ndk.cache.processEvent(event, from: "wss://relay3.example.com", subscriptionId: "sub2")
    
    // Query relay sources
    let sources = await ndk.cache.getRelaySources(eventId: "test123")
    print("Event found on \(sources.count) relays: \(sources.sorted())")
    print()
}

// Feature 2: Smart Filter Aggregation
print("\n🧠 Feature 2: Smart Filter Aggregation")
print("Prevents inefficient subscriptions by detecting incompatible filters")

func demoSmartAggregation() {
    let manager = MockDataRequirementManager()
    
    // Example 1: Compatible filters (can be combined)
    print("\nExample 1: Compatible filters")
    let compatibleFilters = [
        NDKFilter(kinds: [1], authors: ["alice"]),
        NDKFilter(kinds: [1], authors: ["bob"]),
        NDKFilter(kinds: [1], authors: ["charlie"])
    ]
    _ = manager.aggregateFilters(compatibleFilters)
    
    // Example 2: Incompatible filters (must be separate)
    print("\nExample 2: Incompatible filters")
    let incompatibleFilters = [
        NDKFilter(kinds: [1], authors: ["alice"]),
        NDKFilter(kinds: [2], authors: ["bob"]),
        NDKFilter(kinds: [3], authors: ["charlie"])
    ]
    _ = manager.aggregateFilters(incompatibleFilters)
    
    // Example 3: Mixed compatibility
    print("\nExample 3: Mixed compatibility")
    let mixedFilters = [
        NDKFilter(kinds: [1, 2], authors: ["alice"]),
        NDKFilter(kinds: [2, 3], authors: ["bob"]),
        NDKFilter(kinds: [4], authors: ["charlie"]),
        NDKFilter(kinds: [1], authors: ["alice", "bob"])
    ]
    _ = manager.aggregateFilters(mixedFilters)
}

// Feature 3: Memory Safety with Weak Observers
print("\n\n🛡️ Feature 3: Memory Safety with Weak Observer Pattern")
print("Automatic cleanup prevents memory leaks")

class TemporaryObserver {
    let id: String
    
    init(id: String) {
        self.id = id
        print("  👤 Observer \(id) created")
    }
    
    deinit {
        print("  ♻️ Observer \(id) deallocated")
    }
}

func demoWeakObservers() {
    print("\nCreating temporary observers...")
    
    // Create observers in a scope so they get deallocated
    autoreleasepool {
        let observer1 = TemporaryObserver(id: "A")
        let observer2 = TemporaryObserver(id: "B")
        let observer3 = TemporaryObserver(id: "C")
        
        // In real implementation, these would be added to cache
        // and automatically cleaned up when deallocated
        _ = observer1
        _ = observer2
        _ = observer3
    }
    
    print("All observers have been safely deallocated")
    print("In production, the cache periodically cleans up nil weak references")
}

// Run demos
Task {
    await demoRelayTracking()
    demoSmartAggregation()
    demoWeakObservers()
    
    print("\n\n✅ All fundamental features demonstrated!")
    print("\nThese features are REQUIRED for production use:")
    print("- Relay tracking is essential for NIP60 wallets")
    print("- Smart aggregation prevents network inefficiency")
    print("- Weak observers prevent memory leaks")
    
    exit(0)
}

RunLoop.main.run()