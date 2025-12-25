import SwiftUI
import UIKit
import NDKSwiftCore
import NDKSwiftNostrDB

struct DeveloperToolsView: View {
    @Environment(ChirpState.self) private var state

    @State private var stats: NdbStat?
    @State private var databaseSize: Int64 = 0
    @State private var relayCount: Int = 0
    @State private var connectedRelayCount: Int = 0
    @State private var signerPubkey: String?
    @State private var cachePath: String?
    @State private var isLoading = true

    var body: some View {
        List {
            // Quick Stats Section
            Section("Quick Stats") {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading stats...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    QuickStatRow(label: "Total Events", value: formatNumber(stats?.totalEvents ?? 0))
                    QuickStatRow(label: "Profiles Cached", value: formatNumber(stats?.databases[.profile]?.count ?? 0))
                    QuickStatRow(label: "Database Size", value: formatBytes(databaseSize))
                    QuickStatRow(label: "Connected Relays", value: "\(connectedRelayCount)/\(relayCount)")
                }
            }

            // Database Tools
            Section("Database") {
                NavigationLink {
                    NostrDBInspectorView()
                } label: {
                    ToolRow(
                        icon: "cylinder.split.1x2",
                        title: "NostrDB Inspector",
                        subtitle: "Database indexes, event counts, storage",
                        color: .blue
                    )
                }

                NavigationLink {
                    EventInspectorView()
                } label: {
                    ToolRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Event Inspector",
                        subtitle: "Search and browse cached events",
                        color: .pink
                    )
                }
            }

            // Network Tools
            Section("Network") {
                NavigationLink {
                    RelayDashboardView()
                } label: {
                    ToolRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Relay Monitor",
                        subtitle: "Connection states and message counts",
                        color: .green
                    )
                }

                NavigationLink {
                    SubscriptionsView()
                } label: {
                    ToolRow(
                        icon: "list.bullet.rectangle",
                        title: "Subscriptions",
                        subtitle: "Active subscriptions and REQ optimization",
                        color: .orange
                    )
                }

                NavigationLink {
                    OutboxStatsView()
                } label: {
                    ToolRow(
                        icon: "arrow.left.arrow.right.circle",
                        title: "Outbox Inspector",
                        subtitle: "Relay selection and user tracking",
                        color: .indigo
                    )
                }

                NavigationLink {
                    OutboxLiveStatsView()
                } label: {
                    ToolRow(
                        icon: "waveform.path.ecg",
                        title: "Live Discoveries",
                        subtitle: "Real-time relay discovery stream",
                        color: .purple
                    )
                }

                NavigationLink {
                    OutboxRelayMappingView()
                } label: {
                    ToolRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "Relay Mapping",
                        subtitle: "Which users use which relays",
                        color: .teal
                    )
                }
            }

            // Logging & Telemetry
            Section("Logging & Telemetry") {
                NavigationLink {
                    LogsView()
                } label: {
                    ToolRow(
                        icon: "doc.plaintext",
                        title: "Log Viewer",
                        subtitle: "Real-time NDK logs",
                        color: .mint
                    )
                }

                NavigationLink {
                    TelemetrySettingsView()
                } label: {
                    ToolRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Telemetry",
                        subtitle: "OpenTelemetry tracing",
                        color: .purple
                    )
                }
            }

            // Quick Actions
            Section("Quick Actions") {
                Button {
                    Task { await refreshStats() }
                } label: {
                    Label("Refresh Stats", systemImage: "arrow.clockwise")
                }

                if let pubkey = signerPubkey {
                    Button {
                        UIPasteboard.general.string = pubkey
                    } label: {
                        Label("Copy Pubkey", systemImage: "doc.on.doc")
                    }
                }
            }

            // Info Section
            if let path = cachePath {
                Section("Info") {
                    LabeledContent("Cache Path") {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Developer Tools")
        .task {
            await refreshStats()
        }
        .refreshable {
            await refreshStats()
        }
    }

    private func refreshStats() async {
        isLoading = true

        if let cache = state.ndk.cache as? NDKNostrDBCache {
            stats = await cache.getStats()
            databaseSize = await cache.getDatabaseSize()
            cachePath = await cache.getCachePath()
        } else {
            stats = nil
            databaseSize = 0
            cachePath = nil
        }

        relayCount = state.relayCollection.totalCount
        connectedRelayCount = state.relayCollection.connectedCount

        if let signer = state.ndk.signer {
            signerPubkey = try? await signer.pubkey
        }

        isLoading = false
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

private struct QuickStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperToolsView()
    }
}
