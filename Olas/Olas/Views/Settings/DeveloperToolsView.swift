import SwiftUI
import NDKSwift

struct DeveloperToolsView: View {
    let ndk: NDK

    @State private var stats: NdbStat?
    @State private var databaseSize: Int64 = 0
    @State private var relayCount: Int = 0
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
                    QuickStatRow(label: "Connected Relays", value: "\(relayCount)")
                }
            }

            // Tools Section
            Section("Inspection Tools") {
                NavigationLink(destination: NostrDBStatsView(ndk: ndk)) {
                    ToolRow(icon: "cylinder.split.1x2", title: "NostrDB Stats", subtitle: "Database indexes, event counts, storage", color: .blue)
                }

                NavigationLink(destination: EventInspectorView(ndk: ndk)) {
                    ToolRow(icon: "doc.text.magnifyingglass", title: "Event Inspector", subtitle: "Browse and search cached events", color: .purple)
                }

                NavigationLink(destination: RelayMonitorView(ndk: ndk)) {
                    ToolRow(icon: "antenna.radiowaves.left.and.right", title: "Relay Monitor", subtitle: "Connection states and message counts", color: .green)
                }
            }

            Section("Logging") {
                NavigationLink(destination: LogViewerView()) {
                    ToolRow(icon: "doc.plaintext", title: "Log Viewer", subtitle: "Real-time NDK logs", color: .orange)
                }

                NavigationLink(destination: NetworkTrafficView()) {
                    ToolRow(icon: "arrow.left.arrow.right", title: "Network Traffic", subtitle: "Raw Nostr protocol messages", color: .red)
                }
            }

            // Quick Actions Section
            Section("Quick Actions") {
                Button {
                    Task { await refreshStats() }
                } label: {
                    Label("Refresh Stats", systemImage: "arrow.clockwise")
                }

                Button {
                    toggleLogLevel()
                } label: {
                    Label("Toggle Log Level (\(NDKLogger.logLevel.description))", systemImage: "slider.horizontal.3")
                }

                Button {
                    NDKLogger.logNetworkTraffic.toggle()
                } label: {
                    Label(
                        NDKLogger.logNetworkTraffic ? "Disable Network Logging" : "Enable Network Logging",
                        systemImage: NDKLogger.logNetworkTraffic ? "wifi.slash" : "wifi"
                    )
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
            Section("Info") {
                if let path = cachePath {
                    LabeledContent("Cache Path") {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                LabeledContent("NDK Log Level") {
                    Text(NDKLogger.logLevel.description)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Network Logging") {
                    Text(NDKLogger.logNetworkTraffic ? "Enabled" : "Disabled")
                        .foregroundStyle(NDKLogger.logNetworkTraffic ? .green : .secondary)
                }
            }
        }
        .navigationTitle("Developer Tools")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await refreshStats()
        }
        .refreshable {
            await refreshStats()
        }
    }

    private func refreshStats() async {
        isLoading = true
        if let cache = ndk.cache as? NDKNostrDBCache {
            stats = await cache.getStats()
            databaseSize = await cache.getDatabaseSize()
            cachePath = await cache.getCachePath()
        }
        relayCount = await ndk.relays.count
        if let signer = ndk.signer {
            signerPubkey = try? await signer.pubkey
        }
        isLoading = false
    }

    private func toggleLogLevel() {
        switch NDKLogger.logLevel {
        case .info:
            NDKLogger.logLevel = .debug
        case .debug:
            NDKLogger.logLevel = .trace
        case .trace:
            NDKLogger.logLevel = .info
        default:
            NDKLogger.logLevel = .info
        }
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
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
                .cornerRadius(8)

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
