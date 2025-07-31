#!/usr/bin/env swift

import Foundation
import NDKSwift

// Demo showing subscription grouping metrics in action

@main
struct SubscriptionMetricsDemo {
    static func main() async {
        print("🚀 NDKSwift Subscription Grouping Metrics Demo")
        print("=" * 50)
        
        // Initialize NDK
        let ndk = NDK()
        
        // Reset metrics for clean demo
        await ndk.resetSubscriptionMetrics()
        
        // Create various subscription patterns
        print("\n📊 Creating subscriptions...")
        
        // Pattern 1: Multiple identical filters (should group)
        let filter1 = NDKFilter(kinds: [1], authors: ["alice"])
        let sub1 = ndk.subscribe(filter: filter1)
        let sub2 = ndk.subscribe(filter: filter1)
        let sub3 = ndk.subscribe(filter: filter1)
        print("✓ Created 3 subscriptions with identical filters")
        
        // Pattern 2: Different filters (won't group)
        let filter2 = NDKFilter(kinds: [1], authors: ["bob"])
        let sub4 = ndk.subscribe(filter: filter2)
        print("✓ Created 1 subscription with different filter")
        
        // Pattern 3: Non-groupable subscription
        let options = NDKSubscriptionOptions()
        options.groupable = false
        let sub5 = ndk.subscribe(filter: filter1, options: options)
        print("✓ Created 1 non-groupable subscription")
        
        // Wait for grouping to occur
        print("\n⏳ Waiting for grouping to execute...")
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Get metrics
        let metrics = await ndk.getSubscriptionMetrics()
        
        // Display results
        print("\n📈 Metrics Results:")
        print("-" * 50)
        print(metrics.summary)
        
        // Detailed analysis
        print("\n🔍 Detailed Analysis:")
        print("• Total subscriptions: \(metrics.totalSubscriptions)")
        print("• Groupable subscriptions: \(metrics.totalSubscriptions - metrics.nonGroupableSubscriptions)")
        print("• Non-groupable subscriptions: \(metrics.nonGroupableSubscriptions)")
        print("• Grouping efficiency: \(String(format: "%.1f%%", metrics.groupingEfficiency * 100))")
        
        if metrics.totalReqMessages > 0 {
            print("\n📨 Message Statistics:")
            print("• REQ messages sent: \(metrics.totalReqMessages)")
            print("• REQ messages saved: \(metrics.reqMessagesSaved)")
            print("• Message reduction: \(String(format: "%.1f%%", metrics.messageReduction * 100))")
            print("• Average group size: \(String(format: "%.2f", metrics.averageGroupSize))")
        }
        
        // Relay-specific metrics
        if !metrics.relayMetrics.isEmpty {
            print("\n🌐 Per-Relay Metrics:")
            for (relay, relayMetrics) in metrics.relayMetrics {
                print("• \(relay):")
                print("  - REQ messages: \(relayMetrics.totalReqMessages)")
                print("  - Average group size: \(String(format: "%.2f", relayMetrics.averageGroupSize))")
            }
        }
        
        print("\n✨ Demo complete!")
    }
}

// String extension for repeating
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}