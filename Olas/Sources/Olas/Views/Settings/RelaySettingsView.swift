import SwiftUI
import NDKSwift

struct RelaySettingsView: View {
    let ndk: NDK
    @State private var relays: [RelayInfo] = []
    @State private var showAddRelay = false
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        let connectedCount = relays.filter { $0.isConnected }.count
                        Text("\(connectedCount)/\(relays.count)")
                            .font(.title.bold())
                        Text("Relays Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(relays.contains { $0.isConnected } ? .green : .red)
                        .frame(width: 12, height: 12)
                }
            }

            Section("Relays") {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(relays) { relay in
                        RelayRowView(relay: relay) {
                            Task {
                                await ndk.removeRelay(relay.url)
                                await loadRelays()
                            }
                        }
                    }

                    Button {
                        showAddRelay = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(OlasTheme.Colors.deepTeal)
                            Text("Add Relay")
                        }
                    }
                }
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRelays()
        }
        .refreshable {
            await loadRelays()
        }
        .sheet(isPresented: $showAddRelay) {
            AddRelayView { url in
                Task {
                    await ndk.addRelay(url)
                    await loadRelays()
                    showAddRelay = false
                }
            }
        }
    }

    private func loadRelays() async {
        isLoading = true
        defer { isLoading = false }

        let poolRelays = await ndk.relays
        var infos: [RelayInfo] = []

        for relay in poolRelays {
            let state = await relay.connectionState
            let isConnected = state == .connected || state == .authenticated
            infos.append(RelayInfo(url: relay.url, isConnected: isConnected))
        }

        relays = infos.sorted { $0.url < $1.url }
    }
}

struct RelayInfo: Identifiable {
    let url: String
    let isConnected: Bool

    var id: String { url }
}

struct RelayRowView: View {
    let relay: RelayInfo
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(relay.url.replacingOccurrences(of: "wss://", with: ""))
                    .font(.body)

                HStack(spacing: 4) {
                    Circle()
                        .fill(relay.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(relay.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct AddRelayView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void
    @State private var relayUrl = ""

    private let suggestedRelays = [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://relay.snort.social"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Enter Relay URL") {
                    TextField("wss://relay.example.com", text: $relayUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Suggested Relays") {
                    ForEach(suggestedRelays, id: \.self) { relay in
                        Button {
                            relayUrl = relay
                        } label: {
                            HStack {
                                Text(relay.replacingOccurrences(of: "wss://", with: ""))
                                Spacer()
                                if relayUrl == relay {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let url = relayUrl.hasPrefix("wss://") ? relayUrl : "wss://\(relayUrl)"
                        onAdd(url)
                    }
                    .disabled(relayUrl.isEmpty)
                }
            }
        }
    }
}
