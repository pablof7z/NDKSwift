import SwiftUI
@preconcurrency import NDKSwiftCore

struct OutboxLiveStatsView: View {
    @Environment(ChirpState.self) private var state

    @State private var recentUpdates: [OutboxUpdateLog] = []
    @State private var isLoading = true
    @State private var cachedItemsCount = 0

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading stats...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Current Stats Section
                Section("Current Statistics") {
                    LabeledContent("Cached Users") {
                        Text("\(cachedItemsCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    LabeledContent("Recent Discoveries") {
                        Text("\(recentUpdates.count)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // Recent Updates Section
                Section("Recent Discoveries (\(recentUpdates.count))") {
                    if recentUpdates.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No recent discoveries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("New relay discoveries will appear here")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(recentUpdates) { update in
                            UpdateLogRow(update: update)
                        }
                    }
                }
            }
        }
        .navigationTitle("Live Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitialData()
            await subscribeToUpdates()
        }
        .refreshable {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        isLoading = true

        let ndk = state.ndk
        cachedItemsCount = await ndk.outbox.getAllCachedItems().count

        isLoading = false
    }

    private func subscribeToUpdates() async {
        let ndk = state.ndk
        let discoveries = await ndk.outbox.relayDiscoveries
        for await update in discoveries {
            await MainActor.run {
                // Create log entry
                let log = OutboxUpdateLog(
                    pubkey: update.pubkey,
                    readRelayCount: update.readRelays.count,
                    writeRelayCount: update.writeRelays.count,
                    timestamp: update.timestamp
                )

                // Prepend to recent updates (limit to 20)
                recentUpdates.insert(log, at: 0)
                if recentUpdates.count > 20 {
                    recentUpdates.removeLast()
                }

                // Refresh stats
                Task {
                    let ndk = state.ndk
                    cachedItemsCount = await ndk.outbox.getAllCachedItems().count
                }
            }
        }
    }
}

// MARK: - Data Model

struct OutboxUpdateLog: Identifiable {
    let id = UUID()
    let pubkey: String
    let readRelayCount: Int
    let writeRelayCount: Int
    let timestamp: Date
}

// MARK: - Update Log Row

private struct UpdateLogRow: View {
    let update: OutboxUpdateLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with pubkey and timestamp
            HStack {
                Text(formatPubkey(update.pubkey))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                Text(formatTime(update.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Relay counts
            HStack(spacing: 16) {
                Label("\(update.readRelayCount) read", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(update.writeRelayCount) write", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // New badge for recent updates (< 5 seconds old)
                if Date().timeIntervalSince(update.timestamp) < 5 {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..."
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        OutboxLiveStatsView()
    }
}
