#!/usr/bin/env swift

// Test script to verify custom subscription IDs flow correctly
// Run with: swift Examples/TestCustomSubscriptionId.swift

import Foundation
import NDKSwift

// Enable detailed logging to trace subscription ID flow
NDKLogger.level = .trace

// Mock components to intercept subscription creation
class SubscriptionCapture {
    static var capturedSubscriptions: [(id: String, filter: NDKFilter)] = []
}

// Extension to intercept InternalSubscription creation
extension InternalSubscriptionManager {
    func logSubscriptionCreation(id: String, filters: [NDKFilter]) {
        print("\n📋 InternalSubscriptionManager.createSubscription called:")
        print("   ID: \(id)")
        print("   Filters: \(filters)")
        SubscriptionCapture.capturedSubscriptions.append((id: id, filter: filters.first ?? NDKFilter()))
    }
}

// Main test
Task {
    print("🧪 Testing Custom Subscription ID Propagation\n")
    
    // Create NDK instance
    let ndk = NDK()
    
    print("=== Test 1: Custom subscription ID ===")
    let customId = "my-custom-wallet-id"
    print("Creating DataSource with custom ID: '\(customId)'")
    
    let dataSource1 = NDKDataSource<NDKEvent>(
        ndk: ndk,
        filter: NDKFilter(kinds: [EventKind.cashuToken], limit: 10),
        subscriptionId: customId
    )
    
    // Give it time to propagate
    try await Task.sleep(nanoseconds: 200_000_000) // 200ms
    
    print("\n=== Test 2: Auto-generated ID ===")
    print("Creating DataSource without custom ID")
    
    let dataSource2 = NDKDataSource<NDKEvent>(
        ndk: ndk,
        filter: NDKFilter(kinds: [EventKind.nutzap], limit: 10)
    )
    
    // Give it time to propagate
    try await Task.sleep(nanoseconds: 200_000_000) // 200ms
    
    print("\n=== Test 3: Multiple custom IDs ===")
    let customId3 = "nip60-quotes"
    let customId4 = "nip60-tokens"
    
    print("Creating DataSource with ID: '\(customId3)'")
    let dataSource3 = NDKDataSource<NDKEvent>(
        ndk: ndk,
        filter: NDKFilter(kinds: [7375], authors: ["pubkey1"]),
        subscriptionId: customId3
    )
    
    print("Creating DataSource with ID: '\(customId4)'")
    let dataSource4 = NDKDataSource<NDKEvent>(
        ndk: ndk,
        filter: NDKFilter(kinds: [7376], authors: ["pubkey2"]),
        subscriptionId: customId4
    )
    
    // Give it time to propagate
    try await Task.sleep(nanoseconds: 200_000_000) // 200ms
    
    print("\n📊 Summary:")
    print("Expected custom IDs: '\(customId)', '\(customId3)', '\(customId4)'")
    print("Expected auto-generated ID pattern: 'nutzap_<random>'")
    
    print("\n✅ Test complete!")
    print("\nNote: Check the trace logs above to see if custom subscription IDs")
    print("are preserved through the NDKDataRequirementManager flow.")
    print("\nLook for lines containing:")
    print("- 'registerRequirement' with subscriptionId")
    print("- 'Creating internal subscription' with the final ID")
    print("\nThe custom IDs should NOT have random suffixes added!")
    
    // Keep references alive
    _ = dataSource1
    _ = dataSource2
    _ = dataSource3
    _ = dataSource4
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))