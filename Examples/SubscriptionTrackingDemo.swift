#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - Subscription Tracking Demo

print("🔍 NDKSwift Subscription Tracking Demo")
print("=====================================\n")

// Create NDK instance with subscription tracking enabled
let ndk = NDK(
    relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
    ],
    subscriptionTrackingConfig: NDK.SubscriptionTrackingConfig(
        trackClosedSubscriptions: true,
        maxClosedSubscriptions: 50
    )
)

// Connect to relays
print("📡 Connecting to relays...")
Task {
    await ndk.connect()

    // Wait for connections
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

    print("✅ Connected to \(ndk.relays.filter { $0.isConnected }.count) relays\n")

    // MARK: - Demo 1: Basic Subscription Tracking

    print("Demo 1: Basic Subscription Tracking")
    print("-----------------------------------")

    // Create a subscription for text notes
    let textNoteFilter = NDKFilter(kinds: [1], limit: 20)
    let subscription1 = ndk.subscribe(
        filters: [textNoteFilter],
        options: NDKSubscriptionOptions(closeOnEose: true)
    )

    print("📝 Created subscription for text notes (kind 1)")

    // Check initial tracking state
    let activeCount = await ndk.subscriptionTracker.activeSubscriptionCount()
    print("📊 Active subscriptions: \(activeCount)")

    // Wait for some events
    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

    // Get subscription details
    if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription1.id) {
        print("\n📈 Subscription Details:")
        print("  • ID: \(detail.subscriptionId)")
        print("  • Filter: kinds=\(detail.originalFilter.kinds ?? [])")
        print("  • Unique events: \(detail.metrics.totalUniqueEvents)")
        print("  • Total events: \(detail.metrics.totalEvents)")
        print("  • Active relays: \(detail.metrics.activeRelayCount)")

        print("\n📡 Relay Performance:")
        for (relayUrl, metrics) in detail.relayMetrics {
            print("  • \(relayUrl)")
            print("    - Events: \(metrics.eventsReceived)")
            print("    - EOSE: \(metrics.eoseReceived ? "✓" : "✗")")
            if let timeToEose = metrics.timeToEose {
                print("    - Time to EOSE: \(String(format: "%.2f", timeToEose))s")
            }
        }
    }

    // MARK: - Demo 2: Multiple Subscriptions

    print("\n\nDemo 2: Multiple Subscriptions")
    print("------------------------------")

    // Create multiple subscriptions
    let profileFilter = NDKFilter(kinds: [0], limit: 10)
    let reactionFilter = NDKFilter(kinds: [7], limit: 30)

    let subscription2 = ndk.subscribe(filters: [profileFilter])
    let subscription3 = ndk.subscribe(filters: [reactionFilter])

    print("📝 Created 2 more subscriptions (profiles & reactions)")

    // Wait for events
    try await Task.sleep(nanoseconds: 2_000_000_000)

    // Get global statistics
    let stats = await ndk.subscriptionTracker.getStatistics()
    print("\n🌍 Global Statistics:")
    print("  • Active subscriptions: \(stats.activeSubscriptions)")
    print("  • Total subscriptions: \(stats.totalSubscriptions)")
    print("  • Total unique events: \(stats.totalUniqueEvents)")
    print("  • Total events: \(stats.totalEvents)")
    print("  • Average events/subscription: \(String(format: "%.1f", stats.averageEventsPerSubscription))")

    // MARK: - Demo 3: Relay Performance Comparison

    print("\n\nDemo 3: Relay Performance Analysis")
    print("----------------------------------")

    // Analyze relay performance across all subscriptions
    var relayPerformance: [String: (events: Int, subscriptions: Int, eoses: Int)] = [:]

    let allActive = await ndk.subscriptionTracker.getAllActiveSubscriptions()
    for sub in allActive {
        for (relayUrl, metrics) in sub.relayMetrics {
            var perf = relayPerformance[relayUrl] ?? (events: 0, subscriptions: 0, eoses: 0)
            perf.events += metrics.eventsReceived
            perf.subscriptions += 1
            if metrics.eoseReceived {
                perf.eoses += 1
            }
            relayPerformance[relayUrl] = perf
        }
    }

    print("\n📊 Relay Performance Comparison:")
    for (relay, perf) in relayPerformance.sorted(by: { $0.value.events > $1.value.events }) {
        let avgEvents = Double(perf.events) / Double(perf.subscriptions)
        let eoseRate = Double(perf.eoses) / Double(perf.subscriptions) * 100
        print("  • \(relay)")
        print("    - Total events: \(perf.events)")
        print("    - Avg events/sub: \(String(format: "%.1f", avgEvents))")
        print("    - EOSE rate: \(String(format: "%.0f", eoseRate))%")
    }

    // MARK: - Demo 4: Closed Subscription History

    print("\n\nDemo 4: Closed Subscription History")
    print("-----------------------------------")

    // Close some subscriptions
    subscription2.close()
    subscription3.close()

    // Wait a moment
    try await Task.sleep(nanoseconds: 500_000_000)

    // Check closed subscription history
    let closedSubs = await ndk.subscriptionTracker.getClosedSubscriptions()
    print("\n📚 Closed Subscriptions: \(closedSubs.count)")

    for closed in closedSubs {
        let kindStr = closed.filter.kinds?.map { String($0) }.joined(separator: ",") ?? "all"
        print("\n  • Subscription: \(closed.subscriptionId)")
        print("    - Filter: kinds=[\(kindStr)]")
        print("    - Duration: \(String(format: "%.1f", closed.duration))s")
        print("    - Unique events: \(closed.uniqueEventCount)")
        print("    - Events/second: \(String(format: "%.1f", closed.eventsPerSecond))")
        print("    - Relays used: \(closed.relays.count)")
    }

    // MARK: - Demo 5: Export Tracking Data

    print("\n\nDemo 5: Export Tracking Data")
    print("-----------------------------")

    // Export all tracking data
    let exportData = await ndk.subscriptionTracker.exportTrackingData()

    // Convert to JSON for display
    if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
       let jsonString = String(data: jsonData, encoding: .utf8)
    {
        // Show a snippet of the exported data
        let lines = jsonString.components(separatedBy: "\n")
        let snippet = lines.prefix(20).joined(separator: "\n")
        print("\n📄 Exported Data (first 20 lines):")
        print(snippet)
        print("... (truncated)")

        // Save to file
        let fileURL = URL(fileURLWithPath: "subscription-tracking-export.json")
        try? jsonData.write(to: fileURL)
        print("\n💾 Full export saved to: subscription-tracking-export.json")
    }

    // MARK: - Demo 6: Real-time Monitoring

    print("\n\nDemo 6: Real-time Monitoring")
    print("----------------------------")

    // Create a new subscription and monitor it
    let monitorFilter = NDKFilter(kinds: [1, 7], limit: 50)
    let monitorSub = ndk.subscribe(filters: [monitorFilter])

    print("\n🔄 Monitoring subscription for 10 seconds...")
    print("   (kinds: text notes & reactions)")

    // Monitor for 10 seconds, checking every 2 seconds
    for i in 1 ... 5 {
        try await Task.sleep(nanoseconds: 2_000_000_000)

        if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(monitorSub.id) {
            let uniqueEvents = detail.metrics.totalUniqueEvents
            let totalEvents = detail.metrics.totalEvents
            let dedupRate = totalEvents > 0 ? Double(totalEvents - uniqueEvents) / Double(totalEvents) * 100 : 0

            print("\n  [\(i * 2)s] Events: \(uniqueEvents) unique, \(totalEvents) total (dedup: \(String(format: "%.0f", dedupRate))%)")

            // Show per-relay counts
            for (relay, metrics) in detail.relayMetrics.sorted(by: { $0.value.eventsReceived > $1.value.eventsReceived }) {
                let relayName = relay.replacingOccurrences(of: "wss://", with: "")
                print("       • \(relayName): \(metrics.eventsReceived) events")
            }
        }
    }

    // Close monitoring subscription
    monitorSub.close()

    // MARK: - Cleanup

    print("\n\n🧹 Cleanup")
    print("---------")

    // Clear closed subscription history
    await ndk.subscriptionTracker.clearClosedSubscriptionHistory()
    print("✅ Cleared closed subscription history")

    // Final statistics
    let finalStats = await ndk.subscriptionTracker.getStatistics()
    print("\n📊 Final Statistics:")
    print("  • Active subscriptions: \(finalStats.activeSubscriptions)")
    print("  • Total events processed: \(finalStats.totalEvents)")
    print("  • Closed subscriptions tracked: \(finalStats.closedSubscriptionsTracked)")

    // Disconnect
    await ndk.disconnect()
    print("\n👋 Demo complete!")

    exit(0)
}
