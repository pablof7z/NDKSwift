import SwiftUI
import UIKit
@preconcurrency import NDKSwiftCore

struct OutboxStatsView: View {
    @Environment(ChirpState.self) private var state
    @State private var cachedItems: [NDKOutboxItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading outbox data...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Overview Section
                Section("Overview") {
                    LabeledContent("Tracked Users") {
                        Text("\(cachedItems.count)")
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Unique Relays") {
                        Text("\(uniqueRelayCount)")
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Avg Read Relays") {
                        Text(String(format: "%.1f", averageReadRelays))
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Avg Write Relays") {
                        Text(String(format: "%.1f", averageWriteRelays))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Source Distribution
                if !cachedItems.isEmpty {
                    Section("Source Distribution") {
                        ForEach(sourceDistribution, id: \.source) { item in
                            HStack {
                                SourceBadge(source: item.source)
                                Spacer()
                                Text("\(item.count)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Tracked Users
                if !cachedItems.isEmpty {
                    Section("Tracked Users (\(cachedItems.count))") {
                        ForEach(sortedItems, id: \.pubkey) { item in
                            NavigationLink {
                                OutboxItemDetailView(item: item, ndk: state.ndk)
                            } label: {
                                TrackedUserRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Outbox Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCachedItems()
        }
        .refreshable {
            await loadCachedItems()
        }
    }

    private var uniqueRelayCount: Int {
        var allRelays = Set<String>()
        for item in cachedItems {
            allRelays.formUnion(item.allRelayURLs)
        }
        return allRelays.count
    }

    private var averageReadRelays: Double {
        guard !cachedItems.isEmpty else { return 0 }
        let total = cachedItems.reduce(0) { $0 + $1.readRelays.count }
        return Double(total) / Double(cachedItems.count)
    }

    private var averageWriteRelays: Double {
        guard !cachedItems.isEmpty else { return 0 }
        let total = cachedItems.reduce(0) { $0 + $1.writeRelays.count }
        return Double(total) / Double(cachedItems.count)
    }

    private var sortedItems: [NDKOutboxItem] {
        cachedItems.sorted { item1, item2 in
            let totalRelays1 = item1.readRelays.count + item1.writeRelays.count
            let totalRelays2 = item2.readRelays.count + item2.writeRelays.count
            return totalRelays1 > totalRelays2
        }
    }

    private var sourceDistribution: [(source: RelayListSource, count: Int)] {
        var counts: [RelayListSource: Int] = [:]
        for item in cachedItems {
            counts[item.source, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func loadCachedItems() async {
        isLoading = true
        let ndk = state.ndk
        cachedItems = await ndk.outbox.getAllCachedItems()
        isLoading = false
    }
}

// MARK: - Source Badge

private struct SourceBadge: View {
    let source: RelayListSource

    var body: some View {
        Text(source.rawValue.uppercased())
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .foregroundStyle(.white)
            .cornerRadius(4)
    }

    private var badgeColor: Color {
        switch source {
        case .nip65:
            return .blue
        case .contactList:
            return .green
        case .manual:
            return .orange
        case .unknown:
            return .gray
        }
    }
}

// MARK: - Tracked User Row

private struct TrackedUserRow: View {
    let item: NDKOutboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatPubkey(item.pubkey))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                SourceBadge(source: item.source)
            }

            HStack(spacing: 16) {
                Label("\(item.readRelays.count) read", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(item.writeRelays.count) write", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatRelativeDate(item.fetchedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..."
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Detail View

struct OutboxItemDetailView: View {
    let item: NDKOutboxItem
    let ndk: NDK

    @State private var relayScores: [String: Double] = [:]
    @State private var isLoadingScores = true

    var body: some View {
        List {
            // User Section
            Section("User") {
                HStack {
                    Text(item.pubkey)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = item.pubkey
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }

                LabeledContent("Source") {
                    SourceBadge(source: item.source)
                }

                LabeledContent("Fetched At") {
                    Text(formatDate(item.fetchedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Age") {
                    Text(formatRelativeDate(item.fetchedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Read Relays Section
            if !item.readRelays.isEmpty {
                Section("Read Relays (\(item.readRelays.count))") {
                    ForEach(Array(item.readRelays).sorted(by: { $0.url < $1.url }), id: \.url) { relayInfo in
                        RelayInfoRow(
                            relayInfo: relayInfo,
                            score: relayScores[relayInfo.url],
                            isLoadingScores: isLoadingScores
                        )
                    }
                }
            }

            // Write Relays Section
            if !item.writeRelays.isEmpty {
                Section("Write Relays (\(item.writeRelays.count))") {
                    ForEach(Array(item.writeRelays).sorted(by: { $0.url < $1.url }), id: \.url) { relayInfo in
                        RelayInfoRow(
                            relayInfo: relayInfo,
                            score: relayScores[relayInfo.url],
                            isLoadingScores: isLoadingScores
                        )
                    }
                }
            }
        }
        .navigationTitle("User Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRelayScores()
        }
    }

    private func loadRelayScores() async {
        isLoadingScores = true

        var scores: [String: Double] = [:]
        let allRelays = item.readRelays.union(item.writeRelays)

        for relayInfo in allRelays {
            let score = await ndk.outbox.getRelayScore(relay: relayInfo.url, for: item.pubkey)
            scores[relayInfo.url] = score
        }

        relayScores = scores
        isLoadingScores = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Relay Info Row

private struct RelayInfoRow: View {
    let relayInfo: NDKSwiftCore.RelayInfo
    let score: Double?
    let isLoadingScores: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Relay URL
            Text(formatRelayURL(relayInfo.url))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            // Metadata row
            HStack(spacing: 12) {
                // Score
                if isLoadingScores {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if let score = score {
                    Label(formatScore(score), systemImage: "chart.bar")
                        .font(.caption2)
                        .foregroundStyle(scoreColor(score))
                }

                if let metadata = relayInfo.metadata {
                    // Response time
                    if let avgResponseTime = metadata.avgResponseTime {
                        Label(formatResponseTime(avgResponseTime), systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Failure count
                    if metadata.failureCount > 0 {
                        Label("\(metadata.failureCount) fails", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    // Auth/payment badges
                    if metadata.authRequired {
                        Text("AUTH")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(3)
                    }

                    if metadata.paymentRequired {
                        Text("PAID")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }

    private func formatScore(_ score: Double) -> String {
        String(format: "%.2f", score)
    }

    private func formatResponseTime(_ ms: Double) -> String {
        String(format: "%.0fms", ms)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

extension RelayListSource: CustomStringConvertible {
    public var description: String {
        switch self {
        case .nip65: return "NIP-65"
        case .contactList: return "Contact List"
        case .manual: return "Manual"
        case .unknown: return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        OutboxStatsView()
    }
}
