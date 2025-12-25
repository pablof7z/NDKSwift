import SwiftUI
import NDKSwiftCore

struct SubscriptionsView: View {
    @Environment(ChirpState.self) private var state
    @State private var snapshot: MetricsSnapshot?

    var body: some View {
        List {
            if let snapshot = snapshot {
                Section("Overview") {
                    LabeledContent("Total Subscriptions", value: "\(snapshot.totalSubscriptions)")
                    LabeledContent("Grouped Subscriptions", value: "\(snapshot.groupedSubscriptions)")
                    LabeledContent("Non-Groupable", value: "\(snapshot.nonGroupableSubscriptions)")
                }

                Section("REQ Messages") {
                    LabeledContent("Messages Sent", value: "\(snapshot.totalReqMessages)")
                    LabeledContent("Messages Saved", value: "\(snapshot.reqMessagesSaved)")
                    LabeledContent("Average Group Size") {
                        Text(String(format: "%.2f", snapshot.averageGroupSize))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Efficiency") {
                    LabeledContent("Grouping Efficiency") {
                        Text(String(format: "%.1f%%", snapshot.groupingEfficiency * 100))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Message Reduction") {
                        Text(String(format: "%.1f%%", snapshot.messageReduction * 100))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Time Saved") {
                        Text(String(format: "%.2fs", snapshot.totalTimeSaved))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Delay Statistics") {
                    LabeledContent("Total Delays", value: "\(snapshot.delayStatistics.totalDelays)")
                    LabeledContent("Average Actual") {
                        Text(String(format: "%.3fs", snapshot.delayStatistics.averageActualDelay))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Average Configured") {
                        Text(String(format: "%.3fs", snapshot.delayStatistics.averageConfiguredDelay))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("At Least Count", value: "\(snapshot.delayStatistics.atLeastCount)")
                    LabeledContent("At Most Count", value: "\(snapshot.delayStatistics.atMostCount)")
                }

                if !snapshot.relayMetrics.isEmpty {
                    Section("Per-Relay Metrics") {
                        ForEach(Array(snapshot.relayMetrics.keys.sorted()), id: \.self) { relay in
                            if let metrics = snapshot.relayMetrics[relay] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(relay)
                                        .font(.subheadline)
                                    HStack {
                                        Text("REQ Messages:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(metrics.totalReqMessages)")
                                            .font(.caption)
                                    }
                                    HStack {
                                        Text("Avg Group Size:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.2f", metrics.averageGroupSize))
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("Loading subscription metrics...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Subscriptions")
        .task {
            await loadMetrics()
        }
        .refreshable {
            await loadMetrics()
        }
    }

    private func loadMetrics() async {
        snapshot = await NDKSubscriptionMetrics.getSnapshot()
    }
}

#Preview {
    NavigationStack {
        SubscriptionsView()
    }
}
