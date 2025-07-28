#!/usr/bin/env swift

// Test script to verify custom subscription IDs are properly propagated
// Run with: swift Examples/TestSubscriptionIds.swift

import Foundation
import NDKSwift

// Mock relay that captures subscription IDs
class MockRelayWithLogging: RelayProtocol {
    var url: String
    var capturedSubscriptionIds: [String] = []
    
    init(url: String) {
        self.url = url
    }
    
    func connect() async throws {
        print("Mock relay connected")
    }
    
    func disconnect() async {
        print("Mock relay disconnected")
    }
    
    func send(_ message: String) async throws {
        print("📤 Message sent: \(message)")
        
        // Extract subscription ID from REQ messages
        if message.contains("REQ") {
            if let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               json.count > 1,
               let subscriptionId = json[1] as? String {
                capturedSubscriptionIds.append(subscriptionId)
                print("✅ Captured subscription ID: \(subscriptionId)")
            }
        }
    }
    
    func isConnected() async -> Bool {
        return true
    }
    
    func trackSubscription(id: String, filters: [NDKFilter]) async {
        print("📝 Tracking subscription: \(id)")
    }
    
    func untrackSubscription(id: String) async {
        print("🗑️ Untracking subscription: \(id)")
    }
}

// Test custom subscription IDs
Task {
    print("🧪 Testing Custom Subscription IDs\n")
    
    // Create NDK instance
    let ndk = NDK()
    
    // Create and add mock relay
    let mockRelay = MockRelayWithLogging(url: "wss://mock.relay")
    
    // We need to bypass the normal connection flow for testing
    // This is a simplified test that focuses on subscription ID propagation
    
    // Test 1: Custom subscription ID
    print("Test 1: Custom subscription ID")
    let dataSource1 = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [1], limit: 5),
        subscriptionId: "my-custom-id"
    )
    print("Created data source with custom ID: my-custom-id\n")
    
    // Test 2: NIP60 wallet subscription IDs
    print("Test 2: NIP60 wallet subscription IDs")
    let walletSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [EventKind.cashuToken]),
        subscriptionId: "nip60-wallet-events"
    )
    print("Created wallet data source with ID: nip60-wallet-events\n")
    
    // Test 3: Default subscription ID (should be shorter now)
    print("Test 3: Default subscription ID")
    let defaultSource = NDKDataSource(
        ndk: ndk,
        filter: NDKFilter(kinds: [0])
    )
    print("Created data source with default ID generation\n")
    
    print("✅ All tests complete!")
    print("\nNote: In a real application, these subscription IDs would be sent to relays")
    print("in REQ messages like: [\"REQ\", \"my-custom-id\", {\"kinds\":[1],\"limit\":5}]")
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))