#!/usr/bin/env swift

import Foundation
import NDKSwift

// Migration Guide: From currentValue() to Event-Driven Methods
// =============================================================

// This guide shows how to migrate from the deprecated currentValue() method
// to the new event-driven methods that properly wait for events to arrive.

print("🔄 Migration Guide: currentValue() → Event-Driven Methods")
print("========================================================\n")

// IMPORTANT: Why we use collect() instead of first()
// ==================================================
// When fetching replaceable events (profiles, relay lists, etc.), we should
// ALWAYS use collect() to wait for ALL events from ALL relays, then pick
// the most recent one. Using first() would return whichever event arrives
// first, which might be an outdated event from a slow relay!
//
// Example: User updates profile on Relay A, but Relay B still has old profile.
// - first() might return the old profile if Relay B responds faster
// - collect() waits for both relays and lets us pick the newest event

// Setup
let ndk = NDK()
let filter = NDKFilter(kinds: [1], limit: 10)

// ❌ OLD PATTERN 1: Getting First Event (PROBLEMATIC)
// This pattern has a race condition - currentValue() might return empty
// if called before the subscription receives events from relays
func oldGetFirstEvent() async {
    print("❌ OLD: Getting first event with currentValue()")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    // PROBLEM: This might return empty array!
    let events = await dataSource.currentValue()
    if let event = events.first {
        print("   Found event: \(event.content)")
    } else {
        print("   ⚠️  No events (but they might arrive later!)")
    }
}

// ✅ NEW PATTERN 1: Getting Most Recent Event (CORRECT)
// This collects all events and picks the most recent one
func newGetMostRecentEvent() async {
    print("\n✅ NEW: Getting most recent event with collect()")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    // Collect all events and pick the most recent
    let events = await dataSource.collect(timeout: 5.0)
    if let mostRecent = events.sorted(by: { $0.createdAt > $1.createdAt }).first {
        print("   Found most recent event: \(mostRecent.content)")
    } else {
        print("   No events found after waiting 5 seconds")
    }
}

// ❌ OLD PATTERN 2: Getting All Events (PROBLEMATIC)
func oldGetAllEvents() async {
    print("\n❌ OLD: Getting all events with currentValue()")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    // PROBLEM: Might be incomplete or empty!
    let events = await dataSource.currentValue()
    print("   Found \(events.count) events (might be incomplete!)")
}

// ✅ NEW PATTERN 2: Getting All Events (CORRECT)
// This waits for EOSE (End of Stored Events) from relays
func newGetAllEvents() async {
    print("\n✅ NEW: Getting all events with collect()")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    // This waits for all events until EOSE or timeout
    let events = await dataSource.collect(timeout: 10.0)
    print("   Found \(events.count) events (complete set)")
}

// ❌ OLD PATTERN 3: Checking if Empty (PROBLEMATIC)
func oldCheckIfEmpty() async {
    print("\n❌ OLD: Checking if empty with currentValue()")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    let events = await dataSource.currentValue()
    if events.isEmpty {
        print("   No events found (or maybe they haven't arrived yet?)")
    }
}

// ✅ NEW PATTERN 3: Real-Time Event Processing (CORRECT)
// Process events as they arrive in real-time
func newRealTimeProcessing() async {
    print("\n✅ NEW: Real-time processing with AsyncSequence")
    let dataSource = NDKDataSource(ndk: ndk, filter: filter)
    
    // Process events as they arrive
    var count = 0
    for await event in dataSource.events {
        count += 1
        print("   Event #\(count) arrived: \(event.content)")
        if count >= 3 { break } // Stop after 3 for demo
    }
}

// MIGRATION PATTERNS FOR COMMON USE CASES
// =======================================

// 1. Profile Fetching (e.g., in NDKUser)
extension NDKUser {
    // ❌ OLD
    func fetchProfileOld() async -> NDKUserProfile? {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [0], authors: [pubkey], limit: 1)
        )
        let events = await dataSource.currentValue()
        return events.first?.userProfile()
    }
    
    // ✅ NEW
    func fetchProfileNew() async -> NDKUserProfile? {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [0], authors: [pubkey])
        )
        // Collect all profile events and use the most recent
        let events = await dataSource.collect(timeout: 3.0)
        return events.sorted(by: { $0.createdAt > $1.createdAt }).first?.userProfile()
    }
}

// 2. Wallet Configuration (e.g., in NIP60Wallet)
class WalletExample {
    // ❌ OLD
    func loadConfigOld() async -> WalletConfig? {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.cashuWalletConfig], limit: 1),
            maxAge: 300 // 5 minutes
        )
        let events = await dataSource.currentValue()
        return events.first?.parseWalletConfig()
    }
    
    // ✅ NEW
    func loadConfigNew() async -> WalletConfig? {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.cashuWalletConfig]),
            maxAge: 300 // 5 minutes - might return from cache immediately!
        )
        // Collect all configs and use the most recent
        let events = await dataSource.collect(timeout: 2.0)
        return events.sorted(by: { $0.createdAt > $1.createdAt }).first?.parseWalletConfig()
    }
}

// 3. Collecting Multiple Events (e.g., Zap Receipts)
class ZapExample {
    // ❌ OLD
    func getZapsOld() async -> [NDKEvent] {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.zapReceipt])
        )
        return await dataSource.currentValue()
    }
    
    // ✅ NEW
    func getZapsNew() async -> [NDKEvent] {
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.zapReceipt])
        )
        // Wait for all zaps with 10 second timeout
        return await dataSource.collect(timeout: 10.0)
    }
}

// SPECIAL CASES
// =============

// Case 1: When you truly need a snapshot (rare)
// If you're building a UI that polls periodically, you might want the current
// snapshot without waiting. In this case, use currentValue() but understand
// it might be empty on first call.

// Case 2: Cache-Only Queries
// With cachePolicy: .cacheOnly, currentValue() is safer because no network
// delay is involved. But first() is still better for consistency.
func cacheOnlyExample() async {
    let dataSource = NDKDataSource(
        ndk: ndk,
        filter: filter,
        cachePolicy: .cacheOnly
    )
    
    // With cache-only, events come immediately from cache
    if let event = await dataSource.first(timeout: 0.1) {
        print("Found in cache: \(event.content)")
    }
}

// Summary of Migration Rules:
// ==========================
// 1. For replaceable events (profiles, relay lists, etc.):
//    - Replace `currentValue().first` with `collect() + sort by timestamp`
//    - This ensures you get the MOST RECENT event, not just the first to arrive
// 2. For non-replaceable events (notes, zaps, etc.):
//    - Replace `currentValue()` with `collect(timeout:)`
// 3. For real-time updates, use `for await event in dataSource.events`
// 4. Set appropriate timeouts based on your use case
// 5. With cache-first behavior, cached events arrive immediately!
// 6. NEVER use first() for replaceable events - it might return outdated data

print("\n✅ Migration Guide Complete!")
print("Remember: The new methods properly wait for events to arrive,")
print("eliminating race conditions and empty results.")

// Helper extensions for examples
extension NDKEvent {
    func userProfile() -> NDKUserProfile? { nil }
    func parseWalletConfig() -> WalletConfig? { nil }
}

struct WalletConfig {}