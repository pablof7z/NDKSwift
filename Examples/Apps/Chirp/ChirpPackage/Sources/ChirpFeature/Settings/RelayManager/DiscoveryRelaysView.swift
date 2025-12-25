import SwiftUI
import NDKSwiftCore

struct DiscoveryRelaysView: View {
    @Environment(ChirpState.self) private var state
    @State private var relays: [String] = []
    @State private var showingAddSheet = false
    @State private var newRelayURL = ""

    private let defaultRelays = ["wss://purplepag.es"]
    private let storageKey = "chirp_discovery_relays"

    var body: some View {
        List {
            Section {
                ForEach(relays, id: \.self) { relay in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatURL(relay))
                            .font(.body)
                        Text("Discovery relay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteRelays)
            } header: {
                Text("Discovery Relays")
            } footer: {
                Text("These relays are used to discover new content and trending topics. They aggregate popular content across the network.")
            }

            Section {
                Button {
                    resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Discovery Relays")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            loadRelays()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDiscoveryRelaySheet(
                relayURL: $newRelayURL,
                onAdd: { url in
                    addRelay(url)
                    showingAddSheet = false
                    newRelayURL = ""
                },
                onCancel: {
                    showingAddSheet = false
                    newRelayURL = ""
                }
            )
        }
    }

    private func loadRelays() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            relays = saved
        } else {
            relays = defaultRelays
        }
    }

    private func saveRelays() {
        UserDefaults.standard.set(relays, forKey: storageKey)
    }

    private func addRelay(_ urlString: String) {
        let cleanUrl = ensureWebSocketScheme(urlString)
        guard !relays.contains(cleanUrl) else { return }

        relays.append(cleanUrl)
        saveRelays()
    }

    private func deleteRelays(at offsets: IndexSet) {
        relays.remove(atOffsets: offsets)
        saveRelays()
    }

    private func resetToDefaults() {
        relays = defaultRelays
        saveRelays()
    }

    private func ensureWebSocketScheme(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") {
            return trimmed
        }
        return "wss://\(trimmed)"
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
}

struct AddDiscoveryRelaySheet: View {
    @Binding var relayURL: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    private let suggestedRelays = [
        "purplepag.es",
        "relay.noswhere.com",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Relay URL") {
                    TextField("wss://relay.example.com", text: $relayURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Suggested") {
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
            .navigationTitle("Add Discovery Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(relayURL)
                    }
                    .disabled(relayURL.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return NavigationStack {
        DiscoveryRelaysView()
            .environment(state)
    }
}
