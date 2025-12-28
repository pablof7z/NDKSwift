import SwiftUI
@preconcurrency import NDKSwiftCore

struct AppRelaysView: View {
    @Environment(ChirpState.self) private var state
    @State private var showingAddSheet = false
    @State private var newRelayURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var savedRelayURLs: [String] = []

    var body: some View {
        List {
            if savedRelayURLs.isEmpty {
                ContentUnavailableView(
                    "No Relays",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Add relays to connect to the network")
                )
            } else {
                Section {
                    ForEach(savedRelayURLs, id: \.self) { url in
                        AppRelayRow(url: url, ndk: state.ndk)
                    }
                    .onDelete(perform: deleteRelays)
                }

                Section {
                    HStack {
                        Text("Connected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(connectedCount) / \(savedRelayURLs.count)")
                    }
                }
            }
        }
        .navigationTitle("App Relays")
        .onAppear {
            loadSavedRelays()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddRelaySheet(
                relayURL: $newRelayURL,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onAdd: { url in
                    Task {
                        await addRelay(url)
                    }
                },
                onCancel: {
                    showingAddSheet = false
                    newRelayURL = ""
                    errorMessage = nil
                }
            )
        }
    }

    private var connectedCount: Int {
        savedRelayURLs.filter { url in
            if let relay = state.ndk.appRelays.first(where: { $0.url == url }) {
                let connState = relay.ui.connectionState
                return connState == .connected || connState == .authenticated
            }
            return false
        }.count
    }

    private func loadSavedRelays() {
        savedRelayURLs = ChirpState.loadSavedAppRelays()
    }

    private func addRelay(_ urlString: String) async {
        isLoading = true
        errorMessage = nil

        let cleanUrl = ensureWebSocketScheme(urlString)

        guard isValidRelayURL(cleanUrl) else {
            errorMessage = "Invalid relay URL"
            isLoading = false
            return
        }

        // Persist to UserDefaults first
        ChirpState.addSavedAppRelay(cleanUrl)
        loadSavedRelays()

        // Then add to NDK pool
        _ = await state.ndk.addRelay(cleanUrl)

        isLoading = false
        showingAddSheet = false
        newRelayURL = ""
    }

    private func deleteRelays(at offsets: IndexSet) {
        let relaysToDelete = offsets.map { savedRelayURLs[$0] }
        for url in relaysToDelete {
            // Remove from UserDefaults first
            ChirpState.removeSavedAppRelay(url)
        }
        loadSavedRelays()

        // Then remove from NDK pool
        Task {
            for url in relaysToDelete {
                await state.ndk.removeRelay(url)
            }
        }
    }

    private func ensureWebSocketScheme(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") {
            return trimmed
        }
        return "wss://\(trimmed)"
    }

    private func isValidRelayURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              (scheme == "wss" || scheme == "ws"),
              url.host != nil else {
            return false
        }
        return true
    }
}

struct AppRelayRow: View {
    let url: String
    let ndk: NDK

    private var relay: NDKRelay? {
        ndk.appRelays.first { $0.url == url }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(formatURL(url))
                    .font(.body)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = relay?.ui.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func formatURL(_ url: String) -> String {
        var formatted = url
        if formatted.hasPrefix("wss://") {
            formatted = String(formatted.dropFirst(6))
        } else if formatted.hasPrefix("ws://") {
            formatted = String(formatted.dropFirst(5))
        }
        if formatted.hasSuffix("/") {
            formatted = String(formatted.dropLast())
        }
        return formatted
    }

    private var statusColor: Color {
        guard let relay = relay else {
            return .gray
        }
        switch relay.ui.connectionState {
        case .connected, .authenticated:
            return .green
        case .connecting, .authenticating:
            return .orange
        case .disconnected, .disconnecting:
            return .gray
        case .authRequired:
            return .yellow
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        guard let relay = relay else {
            return "Not in pool"
        }
        switch relay.ui.connectionState {
        case .connected:
            if let lastConnected = relay.ui.lastConnectedAt {
                return "Connected at \(lastConnected.formatted(date: .omitted, time: .shortened))"
            }
            return "Connected"
        case .authenticated:
            return "Authenticated"
        case .connecting:
            return "Connecting..."
        case .authenticating:
            return "Authenticating..."
        case .authRequired(let challenge):
            return "Auth Required (\(challenge.prefix(8))...)"
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting..."
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

struct AddRelaySheet: View {
    @Binding var relayURL: String
    let isLoading: Bool
    let errorMessage: String?
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    private let suggestedRelays = [
        "relay.damus.io",
        "nos.lol",
        "relay.primal.net",
        "relay.nostr.band",
        "purplepag.es",
        "relay.snort.social",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("wss://relay.example.com", text: $relayURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Relay URL")
                }

                Section("Suggested Relays") {
                    ForEach(suggestedRelays, id: \.self) { relay in
                        Button {
                            relayURL = relay
                        } label: {
                            HStack {
                                Text(relay)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if relayURL == relay {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Add") {
                            onAdd(relayURL)
                        }
                        .disabled(relayURL.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return NavigationStack {
        AppRelaysView()
            .environment(state)
    }
}
