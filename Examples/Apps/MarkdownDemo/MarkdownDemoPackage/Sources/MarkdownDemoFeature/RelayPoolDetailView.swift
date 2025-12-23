import SwiftUI
import NDKSwiftCore

/// Detailed view of all relays in the pool with their states and statistics
public struct RelayPoolDetailView: View {
    let ndk: NDK

    @State private var relays: [RelayInfo] = []
    @State private var isLoading = true
    @State private var expandedRelays: Set<String> = []
    @State private var sortOrder = SortOrder.connectionState

    enum SortOrder: String, CaseIterable {
        case connectionState = "By Status"
        case persistent = "By Type"
        case alphabetical = "A-Z"
        case activity = "By Activity"
    }

    struct RelayInfo: Identifiable {
        let id: String
        let url: String
        let connectionState: NDKRelayConnectionState
        let isPersistent: Bool
        let idleTime: TimeInterval
        let stats: NDKRelayStats
        let origin: NDKRelayOrigin

        var displayUrl: String {
            url.replacingOccurrences(of: "wss://", with: "")
               .replacingOccurrences(of: "ws://", with: "")
        }
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sort picker
            HStack {
                Text("Sort:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                // Summary
                let connected = relays.filter { isConnected($0.connectionState) }.count
                Text("\(connected)/\(relays.count) connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            // Relay list
            if isLoading {
                ProgressView("Loading relays...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if relays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No relays in pool")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedRelays) { relay in
                        RelayRow(
                            relay: relay,
                            isExpanded: expandedRelays.contains(relay.url),
                            onToggle: {
                                if expandedRelays.contains(relay.url) {
                                    expandedRelays.remove(relay.url)
                                } else {
                                    expandedRelays.insert(relay.url)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await loadRelays()
        }
        .refreshable {
            await loadRelays()
        }
    }

    private var sortedRelays: [RelayInfo] {
        switch sortOrder {
        case .connectionState:
            return relays.sorted { connectionPriority($0.connectionState) < connectionPriority($1.connectionState) }
        case .persistent:
            return relays.sorted { ($0.isPersistent ? 0 : 1) < ($1.isPersistent ? 0 : 1) }
        case .alphabetical:
            return relays.sorted { $0.url < $1.url }
        case .activity:
            return relays.sorted { $0.idleTime < $1.idleTime }
        }
    }

    private func connectionPriority(_ state: NDKRelayConnectionState) -> Int {
        switch state {
        case .authenticated: return 0
        case .connected: return 1
        case .connecting: return 2
        case .authRequired: return 3
        case .authenticating: return 4
        case .disconnecting: return 5
        case .disconnected: return 6
        case .failed: return 7
        }
    }

    private func isConnected(_ state: NDKRelayConnectionState) -> Bool {
        switch state {
        case .connected, .authenticated:
            return true
        default:
            return false
        }
    }

    private func loadRelays() async {
        isLoading = true

        var infos: [RelayInfo] = []
        let poolRelays = await ndk.pool.relays

        for relay in poolRelays {
            let connectionState = await relay.connectionState
            let isPersistent = await relay.isPersistent
            let idleTime = await relay.idleTime
            let stats = await relay.stats
            let origin = await relay.origin

            infos.append(RelayInfo(
                id: relay.url,
                url: relay.url,
                connectionState: connectionState,
                isPersistent: isPersistent,
                idleTime: idleTime,
                stats: stats,
                origin: origin
            ))
        }

        relays = infos
        isLoading = false
    }
}

// MARK: - Relay Row

struct RelayRow: View {
    let relay: RelayPoolDetailView.RelayInfo
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button(action: onToggle) {
                HStack {
                    // Status indicator
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    // URL and badges
                    VStack(alignment: .leading, spacing: 2) {
                        Text(relay.displayUrl)
                            .font(.body)
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            // Persistent badge
                            if relay.isPersistent {
                                Badge(text: "Persistent", color: .blue)
                            } else {
                                Badge(text: "Dynamic", color: .orange)
                            }

                            // Origin badge
                            Badge(text: originLabel, color: .gray)

                            // Connection state
                            Badge(text: statusLabel, color: statusColor)
                        }
                    }

                    Spacer()

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        StatCell(label: "Messages Sent", value: "\(relay.stats.messagesSent)")
                        StatCell(label: "Messages Received", value: "\(relay.stats.messagesReceived)")
                        StatCell(label: "Bytes Sent", value: formatBytes(relay.stats.bytesSent))
                        StatCell(label: "Bytes Received", value: formatBytes(relay.stats.bytesReceived))
                        StatCell(label: "Connection Attempts", value: "\(relay.stats.connectionAttempts)")
                        StatCell(label: "Successful Connections", value: "\(relay.stats.successfulConnections)")
                    }

                    // Idle time
                    HStack {
                        Text("Idle Time:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatIdleTime(relay.idleTime))
                            .font(.caption.monospacedDigit())
                    }

                    // Connected at
                    if let connectedAt = relay.stats.connectedAt {
                        HStack {
                            Text("Connected At:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(connectedAt, style: .time)
                                .font(.caption)
                        }
                    }

                    // Latency
                    if let latency = relay.stats.latency {
                        HStack {
                            Text("Latency:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f ms", latency * 1000))
                                .font(.caption.monospacedDigit())
                        }
                    }

                    // Full URL
                    HStack {
                        Text("URL:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(relay.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var statusColor: Color {
        switch relay.connectionState {
        case .connected, .authenticated:
            return .green
        case .connecting, .authenticating:
            return .yellow
        case .authRequired:
            return .orange
        case .disconnected, .disconnecting:
            return .gray
        case .failed:
            return .red
        }
    }

    private var statusLabel: String {
        switch relay.connectionState {
        case .connected: return "Connected"
        case .authenticated: return "Authenticated"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating"
        case .authRequired: return "Auth Required"
        case .disconnected: return "Disconnected"
        case .disconnecting: return "Disconnecting"
        case .failed(let error): return "Failed: \(error.prefix(20))"
        }
    }

    private var originLabel: String {
        switch relay.origin {
        case .explicit: return "Explicit"
        case .outbox: return "Outbox"
        case .outboxConfig: return "Config"
        case .fallback: return "Fallback"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func formatIdleTime(_ time: TimeInterval) -> String {
        if time == .infinity {
            return "Never active"
        } else if time < 1 {
            return "Just now"
        } else if time < 60 {
            return String(format: "%.0f sec ago", time)
        } else if time < 3600 {
            return String(format: "%.0f min ago", time / 60)
        } else {
            return String(format: "%.1f hrs ago", time / 3600)
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Stat Cell

struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#if DEBUG
struct RelayPoolDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RelayPoolDetailView(ndk: NDK())
    }
}
#endif
