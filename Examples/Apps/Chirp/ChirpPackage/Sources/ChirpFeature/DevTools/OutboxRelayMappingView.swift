import SwiftUI
import UIKit
@preconcurrency import NDKSwiftCore

struct OutboxRelayMappingView: View {
    @Environment(ChirpState.self) private var state

    @State private var relayMappings: [RelayWithAuthors] = []
    @State private var relayStates: [RelayURL: NDKRelay.State] = [:]
    @State private var selectedMapping: RelayWithAuthors?
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Building relay mappings...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if relayMappings.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No relay mappings found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("Summary") {
                    LabeledContent("Total Relays") {
                        Text("\(relayMappings.count)")
                            .font(.system(.body, design: .monospaced))
                    }

                    LabeledContent("Connected Relays") {
                        let connectedCount = relayMappings.filter { mapping in
                            if let state = relayStates[mapping.relayURL] {
                                return state.connectionState == .connected || state.connectionState == .authenticated
                            }
                            return false
                        }.count
                        Text("\(connectedCount)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }

                Section("Relays (\(relayMappings.count))") {
                    ForEach(sortedMappings, id: \.id) { mapping in
                        RelayMappingRow(
                            mapping: mapping,
                            state: relayStates[mapping.relayURL]
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedMapping = mapping
                        }
                    }
                }
            }
        }
        .navigationTitle("Relay Mapping")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMappings()
        }
        .refreshable {
            await loadMappings()
        }
        .sheet(item: $selectedMapping) { mapping in
            NavigationStack {
                RelayMappingDetailView(
                    mapping: mapping,
                    state: relayStates[mapping.relayURL]
                )
            }
        }
    }

    private var sortedMappings: [RelayWithAuthors] {
        relayMappings.sorted { mapping1, mapping2 in
            let total1 = mapping1.readAuthors.count + mapping1.writeAuthors.count
            let total2 = mapping2.readAuthors.count + mapping2.writeAuthors.count
            return total1 > total2
        }
    }

    private func loadMappings() async {
        isLoading = true

        let ndk = state.ndk
        let trackedItems = await ndk.outbox.getAllCachedItems()

        // Build inverse mapping: relay URL -> authors
        var mappingDict: [String: (readAuthors: Set<String>, writeAuthors: Set<String>)] = [:]

        for item in trackedItems {
            // Read relays
            for relayInfo in item.readRelays {
                if mappingDict[relayInfo.url] == nil {
                    mappingDict[relayInfo.url] = (readAuthors: Set(), writeAuthors: Set())
                }
                mappingDict[relayInfo.url]?.readAuthors.insert(item.pubkey)
            }

            // Write relays
            for relayInfo in item.writeRelays {
                if mappingDict[relayInfo.url] == nil {
                    mappingDict[relayInfo.url] = (readAuthors: Set(), writeAuthors: Set())
                }
                mappingDict[relayInfo.url]?.writeAuthors.insert(item.pubkey)
            }
        }

        // Convert to RelayWithAuthors array
        relayMappings = mappingDict.map { url, authors in
            RelayWithAuthors(
                relayURL: url,
                readAuthors: authors.readAuthors,
                writeAuthors: authors.writeAuthors
            )
        }

        // Load relay states for matching NDK relays
        let ndkRelays = await ndk.relays
        for relay in ndkRelays {
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

        isLoading = false
    }
}

// MARK: - Data Model

struct RelayWithAuthors: Identifiable {
    let relayURL: String
    let readAuthors: Set<String>
    let writeAuthors: Set<String>

    var id: String { relayURL }

    var totalAuthors: Int {
        readAuthors.union(writeAuthors).count
    }
}

// MARK: - Relay Mapping Row

private struct RelayMappingRow: View {
    let mapping: RelayWithAuthors
    let state: NDKRelay.State?

    var body: some View {
        HStack(spacing: 12) {
            // Connection status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                // Relay URL
                Text(formatRelayURL(mapping.relayURL))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)

                // Author counts
                HStack(spacing: 16) {
                    Label("\(mapping.readAuthors.count) read", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(mapping.writeAuthors.count) write", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(mapping.totalAuthors) total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}

// MARK: - Relay Mapping Detail View

private struct RelayMappingDetailView: View {
    let mapping: RelayWithAuthors
    let state: NDKRelay.State?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Relay Info Section
            Section("Relay") {
                HStack {
                    Text(mapping.relayURL)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = mapping.relayURL
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }

                if let state = state {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(statusText)
                                .foregroundStyle(statusColor)
                        }
                    }

                    if let latency = state.stats.latency {
                        LabeledContent("Latency") {
                            Text(String(format: "%.0fms", latency * 1000))
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    LabeledContent("Messages Received") {
                        Text("\(state.stats.messagesReceived)")
                            .font(.system(.body, design: .monospaced))
                    }

                    LabeledContent("Messages Sent") {
                        Text("\(state.stats.messagesSent)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            // Summary Section
            Section("Summary") {
                LabeledContent("Total Authors") {
                    Text("\(mapping.totalAuthors)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Read Authors") {
                    Text("\(mapping.readAuthors.count)")
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("Write Authors") {
                    Text("\(mapping.writeAuthors.count)")
                        .font(.system(.body, design: .monospaced))
                }
            }

            // Read Authors Section
            if !mapping.readAuthors.isEmpty {
                Section("Read Authors (\(mapping.readAuthors.count))") {
                    ForEach(Array(mapping.readAuthors.sorted()), id: \.self) { pubkey in
                        AuthorRow(pubkey: pubkey)
                    }
                }
            }

            // Write Authors Section
            if !mapping.writeAuthors.isEmpty {
                Section("Write Authors (\(mapping.writeAuthors.count))") {
                    ForEach(Array(mapping.writeAuthors.sorted()), id: \.self) { pubkey in
                        AuthorRow(pubkey: pubkey)
                    }
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
}

// MARK: - Author Row

private struct AuthorRow: View {
    let pubkey: String

    var body: some View {
        HStack {
            Text(formatPubkey(pubkey))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Button {
                UIPasteboard.general.string = pubkey
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatPubkey(_ key: String) -> String {
        String(key.prefix(8)) + "..." + String(key.suffix(8))
    }
}

#Preview {
    NavigationStack {
        OutboxRelayMappingView()
    }
}
