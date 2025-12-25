import SwiftUI
@preconcurrency import NDKSwiftCore

struct RelayDashboardView: View {
    @Environment(ChirpState.self) private var state

    @State private var relays: [NDKRelay] = []
    @State private var relayStates: [RelayURL: NDKRelay.State] = [:]
    @State private var selectedRelay: NDKRelay?
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading relays...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if relays.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No relays configured")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                // Summary section
                Section("Summary") {
                    HStack {
                        Text("Total Relays")
                        Spacer()
                        Text("\(relays.count)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Connected")
                        Spacer()
                        Text("\(connectedCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text("Disconnected")
                        Spacer()
                        Text("\(disconnectedCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(disconnectedCount > 0 ? .red : .secondary)
                    }
                }

                // Relay list
                Section("Relays") {
                    ForEach(sortedRelays, id: \.url) { relay in
                        RelayMonitorRowView(
                            relay: relay,
                            state: relayStates[relay.url]
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedRelay = relay
                        }
                    }
                }
            }
        }
        .navigationTitle("Relay Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await reconnectAll()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadRelayStates()
            isLoading = false

            // Subscribe to state updates for each relay
            for relay in relays {
                Task {
                    for await newState in relay.stateStream {
                        await MainActor.run {
                            relayStates[relay.url] = newState
                        }
                    }
                }
            }
        }
        .refreshable {
            await loadRelayStates()
        }
        .sheet(item: $selectedRelay) { relay in
            NavigationStack {
                RelayDetailView(relay: relay, state: relayStates[relay.url])
            }
        }
    }

    private var sortedRelays: [NDKRelay] {
        relays.sorted { relay1, relay2 in
            let state1 = relayStates[relay1.url]?.connectionState
            let state2 = relayStates[relay2.url]?.connectionState

            let isConnected1 = state1 == .connected || state1 == .authenticated
            let isConnected2 = state2 == .connected || state2 == .authenticated

            if isConnected1 && !isConnected2 { return true }
            if !isConnected1 && isConnected2 { return false }
            return relay1.url < relay2.url
        }
    }

    private var connectedCount: Int {
        relayStates.values.filter { state in
            state.connectionState == .connected || state.connectionState == .authenticated
        }.count
    }

    private var disconnectedCount: Int {
        relays.count - connectedCount
    }

    private func loadRelayStates() async {
        let ndk = state.ndk
        relays = await ndk.relays
        for relay in relays {
            let relayState = NDKRelay.State(
                connectionState: await relay.connectionState,
                stats: await relay.stats,
                info: await relay.info,
                activeSubscriptions: await relay.activeSubscriptions
            )
            await MainActor.run {
                relayStates[relay.url] = relayState
            }
        }
    }

    private func reconnectAll() async {
        for relay in relays {
            let connState = await relay.connectionState
            if connState != .connected && connState != .authenticated && connState != .connecting {
                try? await relay.connect()
            }
        }
    }
}

// MARK: - Relay Monitor Row View

private struct RelayMonitorRowView: View {
    let relay: NDKRelay
    let state: NDKRelay.State?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(relay.url)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if let stats = state?.stats {
                        Label("\(stats.messagesReceived)", systemImage: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Label("\(stats.messagesSent)", systemImage: "arrow.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let latency = stats.latency {
                            Label(String(format: "%.0fms", latency * 1000), systemImage: "timer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        guard let connectionState = state?.connectionState else {
            return .gray
        }

        switch connectionState {
        case .connected, .authenticated:
            return .green
        case .connecting, .authenticating:
            return .yellow
        case .disconnected, .disconnecting:
            return .gray
        case .authRequired:
            return .orange
        case .failed:
            return .red
        }
    }
}

// MARK: - Relay Detail View

private struct RelayDetailView: View {
    let relay: NDKRelay
    let state: NDKRelay.State?

    @Environment(\.dismiss) private var dismiss
    @State private var isReconnecting = false

    var body: some View {
        List {
            // Connection section
            Section("Connection") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                }

                if let connectedAt = state?.stats.connectedAt {
                    LabeledContent("Connected At") {
                        Text(formatDate(connectedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastMessage = state?.stats.lastMessageAt {
                    LabeledContent("Last Activity") {
                        Text(formatRelativeDate(lastMessage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let latency = state?.stats.latency {
                    LabeledContent("Latency") {
                        Text(String(format: "%.0fms", latency * 1000))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            // Statistics section
            Section("Statistics") {
                LabeledContent("Messages Received") {
                    Text("\(state?.stats.messagesReceived ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Messages Sent") {
                    Text("\(state?.stats.messagesSent ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Bytes Received") {
                    Text(formatBytes(Int64(state?.stats.bytesReceived ?? 0)))
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Bytes Sent") {
                    Text(formatBytes(Int64(state?.stats.bytesSent ?? 0)))
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Connection Attempts") {
                    Text("\(state?.stats.connectionAttempts ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Successful Connections") {
                    Text("\(state?.stats.successfulConnections ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }
            }

            // Signature verification section
            if let sigStats = state?.stats.signatureStats {
                Section("Signature Verification") {
                    LabeledContent("Validated") {
                        Text("\(sigStats.validatedCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    LabeledContent("Skipped (Sampling)") {
                        Text("\(sigStats.nonValidatedCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Validation Ratio") {
                        Text(String(format: "%.0f%%", sigStats.currentValidationRatio * 100))
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            // Relay info section (NIP-11)
            if let info = state?.info {
                Section("Relay Information (NIP-11)") {
                    if let name = info.name {
                        LabeledContent("Name") {
                            Text(name)
                        }
                    }

                    if let description = info.description {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(description)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    if let software = info.software {
                        LabeledContent("Software") {
                            Text(software)
                                .font(.caption)
                        }
                    }

                    if let version = info.version {
                        LabeledContent("Version") {
                            Text(version)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    if let nips = info.supportedNips, !nips.isEmpty {
                        LabeledContent("Supported NIPs") {
                            Text(nips.map { "\($0)" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let contact = info.contact {
                        LabeledContent("Contact") {
                            Text(contact)
                                .font(.caption)
                        }
                    }
                }
            }

            // Active subscriptions section
            if let subscriptions = state?.activeSubscriptions, !subscriptions.isEmpty {
                Section("Active Subscriptions (\(subscriptions.count))") {
                    ForEach(subscriptions, id: \.id) { sub in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sub.id)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)

                            HStack(spacing: 12) {
                                Text("\(sub.eventCount) events")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text("\(sub.filters.count) filters")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if let lastEvent = sub.lastEventAt {
                                    Text(formatRelativeDate(lastEvent))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Actions section
            Section {
                Button {
                    Task {
                        isReconnecting = true
                        await relay.disconnect()
                        try? await relay.connect()
                        isReconnecting = false
                    }
                } label: {
                    HStack {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                        if isReconnecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isReconnecting)

                Button {
                    UIPasteboard.general.string = relay.url
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle("Relay Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var statusColor: Color {
        guard let connectionState = state?.connectionState else {
            return .gray
        }

        switch connectionState {
        case .connected, .authenticated:
            return .green
        case .connecting, .authenticating:
            return .yellow
        case .disconnected, .disconnecting:
            return .gray
        case .authRequired:
            return .orange
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        guard let connectionState = state?.connectionState else {
            return "Unknown"
        }

        switch connectionState {
        case .connected:
            return "Connected"
        case .authenticated:
            return "Authenticated"
        case .connecting:
            return "Connecting..."
        case .authenticating:
            return "Authenticating..."
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting..."
        case .authRequired:
            return "Auth Required"
        case let .failed(message):
            return "Failed: \(message)"
        }
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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        RelayDashboardView()
    }
}
