#!/usr/bin/env swift

import Foundation

/*
 * Optimistic Publishing Demo for NDKSwift
 * 
 * This demonstrates how optimistic publishing provides immediate UI feedback
 * when events are published, without waiting for relay confirmation.
 */

// Import NDKSwift when running as a compiled program
// import NDKSwift

// Mock implementations for demo purposes
struct NDKEvent {
    let id: String
    let pubkey: String
    let createdAt: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let signature: String
}

struct NDKFilter {
    let kinds: [Int]?
    let authors: [String]?
    let limit: Int?
    
    init(kinds: [Int]? = nil, authors: [String]? = nil, limit: Int? = nil) {
        self.kinds = kinds
        self.authors = authors
        self.limit = limit
    }
}

struct NDKOptimisticPublishingConfig {
    var enabled: Bool = true
    var cacheUnpublishedEvents: Bool = true
    var dispatchToSubscriptions: Bool = true
    
    static let disabled = NDKOptimisticPublishingConfig(
        enabled: false,
        cacheUnpublishedEvents: false,
        dispatchToSubscriptions: false
    )
}

struct NDKSubscriptionOptions {
    var skipOptimisticEvents: Bool = false
}

enum EventConfirmationState {
    case optimistic
    case confirmed(fromRelay: String)
    
    var isConfirmed: Bool {
        switch self {
        case .optimistic: return false
        case .confirmed: return true
        }
    }
}

// Demo implementation
class OptimisticPublishingDemo {
    
    func runDemo() async {
        print("🚀 NDKSwift Optimistic Publishing Demo")
        print("=====================================")
        
        await demonstrateOptimisticPublishing()
        await demonstrateEventConfirmation()
        await demonstrateSubscriptionOptions()
        await demonstrateDisabledOptimisticPublishing()
    }
    
    private func demonstrateOptimisticPublishing() async {
        print("\n📝 Demo 1: Optimistic Publishing Flow")
        print("------------------------------------")
        
        // 1. User creates a note
        let note = NDKEvent(
            id: "abcd1234",
            pubkey: "user_pubkey",
            createdAt: Int64(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Hello Nostr! This is my first note.",
            signature: "signature_here"
        )
        
        print("📱 User types: '\(note.content)'")
        print("🔄 User hits 'Post' button...")
        
        // 2. With optimistic publishing enabled:
        print("\n⚡ OPTIMISTIC PUBLISHING ENABLED:")
        print("   1. Event immediately dispatched to subscriptions")
        print("   2. Event cached as 'optimistic' state")
        print("   3. UI shows note immediately with 'sending...' indicator")
        print("   4. Event sent to relays in background")
        
        // 3. Show immediate UI feedback
        await simulateImmediateUIUpdate(note)
        
        // 4. Simulate relay confirmation
        await simulateRelayConfirmation(note)
    }
    
    private func demonstrateEventConfirmation() async {
        print("\n✅ Demo 2: Event Confirmation Flow")
        print("----------------------------------")
        
        // Initial state
        var state = EventConfirmationState.optimistic
        print("Initial state: \(state.isConfirmed ? "confirmed" : "optimistic")")
        
        // Simulate relay confirmation
        state = .confirmed(fromRelay: "wss://relay.damus.io")
        print("After relay OK: \(state.isConfirmed ? "confirmed" : "optimistic")")
        
        if case .confirmed(let relay) = state {
            print("✅ Confirmed by relay: \(relay)")
        }
    }
    
    private func demonstrateSubscriptionOptions() async {
        print("\n🔧 Demo 3: Subscription Configuration")
        print("------------------------------------")
        
        // Default behavior: receive optimistic events
        let defaultOptions = NDKSubscriptionOptions()
        print("Default subscription: skipOptimisticEvents = \(defaultOptions.skipOptimisticEvents)")
        print("   → Will receive optimistic events for instant updates")
        
        // Opt-out behavior: skip optimistic events
        var strictOptions = NDKSubscriptionOptions()
        strictOptions.skipOptimisticEvents = true
        print("Strict subscription: skipOptimisticEvents = \(strictOptions.skipOptimisticEvents)")
        print("   → Will only receive confirmed events from relays")
    }
    
    private func demonstrateDisabledOptimisticPublishing() async {
        print("\n🚫 Demo 4: Disabled Optimistic Publishing")
        print("----------------------------------------")
        
        let config = NDKOptimisticPublishingConfig.disabled
        print("Optimistic publishing disabled:")
        print("   - enabled: \(config.enabled)")
        print("   - cacheUnpublishedEvents: \(config.cacheUnpublishedEvents)")
        print("   - dispatchToSubscriptions: \(config.dispatchToSubscriptions)")
        print("   → Traditional behavior: wait for relay confirmation")
    }
    
    // Helper methods for simulation
    private func simulateImmediateUIUpdate(_ event: NDKEvent) async {
        print("\n🎯 Subscription receives optimistic event:")
        print("   Event ID: \(event.id)")
        print("   Content: \(event.content)")
        print("   State: optimistic (showing 'sending...')")
        
        // Simulate UI update delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        print("   ✨ UI updated instantly!")
    }
    
    private func simulateRelayConfirmation(_ event: NDKEvent) async {
        print("\n📡 Relay processing (background):")
        print("   Sending to wss://relay.damus.io...")
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        print("   ✅ OK message received from relay")
        print("   📦 Cache updated: optimistic → confirmed")
        print("   🎯 UI updated: 'sending...' → 'sent'")
    }
}

// Run the demo
let demo = OptimisticPublishingDemo()
await demo.runDemo()

print("\n🎉 Demo Complete!")
print("================")
print("Key Benefits of Optimistic Publishing:")
print("• Instant UI feedback improves user experience")
print("• Events appear immediately in subscriptions")
print("• Network latency doesn't block UI updates")
print("• Automatic deduplication prevents duplicate events")
print("• Cache tracks confirmation state for rich UI")