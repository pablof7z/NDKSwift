import SwiftUI
import NDKSwiftCore

/// Main container for Relay Intelligence diagnostics
/// Shows overview, live events, hint explorer, and relay pool details
public struct RelayIntelligenceDiagnosticsView: View {
    let ndk: NDK

    @State private var selectedSection = DiagnosticSection.overview
    @State private var statistics: HintIndexStatistics?
    @State private var sourceBreakdown: [HintSource: Int] = [:]
    @State private var poolSummary: (connected: Int, total: Int) = (0, 0)
    @State private var persistentCount = 0
    @State private var dynamicCount = 0
    @State private var mostKnownRelays: [RelayMention] = []
    @State private var refreshTrigger = false

    enum DiagnosticSection: String, CaseIterable {
        case overview = "Overview"
        case outbox = "Outbox"
        case liveFeed = "Live Feed"
        case hints = "Hints"
        case relays = "Relays"
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(DiagnosticSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            switch selectedSection {
            case .overview:
                overviewSection
            case .outbox:
                OutboxExplorerView(ndk: ndk)
            case .liveFeed:
                LiveIntelligenceFeedView(ndk: ndk)
            case .hints:
                HintIndexExplorerView(ndk: ndk)
            case .relays:
                RelayPoolDetailView(ndk: ndk)
            }
        }
        .task {
            await loadStatistics()
        }
        .refreshable {
            await loadStatistics()
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hint Index Stats Card
                statsCard(
                    title: "HintIndex Statistics",
                    icon: "brain.head.profile",
                    color: .purple
                ) {
                    if let stats = statistics {
                        StatRow(label: "Total Hints", value: "\(stats.totalEntries)")
                        StatRow(label: "Unique Pubkeys", value: "\(stats.pubkeyCount)")
                        StatRow(label: "Unique Event IDs", value: "\(stats.eventIdCount)")
                        StatRow(label: "Unique Addresses", value: "\(stats.addressCount)")
                        StatRow(label: "Known Relays", value: "\(stats.uniqueRelayCount)")
                    } else {
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                }

                // Source Breakdown Card
                statsCard(
                    title: "Hint Sources",
                    icon: "chart.pie",
                    color: .blue
                ) {
                    if sourceBreakdown.isEmpty {
                        Text("No hints recorded yet")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(Array(sourceBreakdown.keys.sorted(by: { sourceBreakdown[$0]! > sourceBreakdown[$1]! })), id: \.self) { source in
                            HStack {
                                Circle()
                                    .fill(colorForSource(source))
                                    .frame(width: 8, height: 8)
                                Text(labelForSource(source))
                                    .font(.caption)
                                Spacer()
                                Text("\(sourceBreakdown[source] ?? 0)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Pool Summary Card
                statsCard(
                    title: "Relay Pool",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .green
                ) {
                    StatRow(label: "Connected", value: "\(poolSummary.connected) / \(poolSummary.total)")
                    StatRow(label: "Persistent", value: "\(persistentCount)")
                    StatRow(label: "Dynamic", value: "\(dynamicCount)")
                }

                // Top Relays Card
                statsCard(
                    title: "Most Known Relays",
                    icon: "star.fill",
                    color: .orange
                ) {
                    if mostKnownRelays.isEmpty {
                        Text("No relay data yet")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(Array(mostKnownRelays.prefix(5).enumerated()), id: \.offset) { index, mention in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(formatRelayURL(mention.relay))
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(mention.mentionCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Refresh button
                Button(action: {
                    Task { await loadStatistics() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statsCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func loadStatistics() async {
        // Load HintIndex statistics
        statistics = await ndk.hintIndex.statistics
        sourceBreakdown = await ndk.hintIndex.sourceBreakdown
        mostKnownRelays = await ndk.hintIndex.mostKnownRelays(limit: 10)

        // Load pool statistics
        poolSummary = await ndk.pool.getConnectionSummary()

        // Count persistent vs dynamic
        var persistent = 0
        var dynamic = 0
        let relays = await ndk.pool.relays
        for relay in relays {
            if await relay.isPersistent {
                persistent += 1
            } else {
                dynamic += 1
            }
        }
        persistentCount = persistent
        dynamicCount = dynamic
    }

    private func colorForSource(_ source: HintSource) -> Color {
        switch source {
        case .nip19: return .blue
        case .eventObserved: return .green
        case .userRelayList: return .orange
        case .explicit: return .purple
        }
    }

    private func labelForSource(_ source: HintSource) -> String {
        switch source {
        case .nip19: return "NIP-19 (bech32)"
        case .eventObserved: return "Event Observed"
        case .userRelayList: return "User Relay List"
        case .explicit: return "Explicit"
        }
    }

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
           .replacingOccurrences(of: "ws://", with: "")
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RelayIntelligenceDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        RelayIntelligenceDiagnosticsView(ndk: NDK())
    }
}
#endif
