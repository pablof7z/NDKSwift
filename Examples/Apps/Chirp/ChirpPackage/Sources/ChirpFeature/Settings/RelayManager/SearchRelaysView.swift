import SwiftUI
import NDKSwiftCore

struct SearchRelaysView: View {
    @Environment(ChirpState.self) private var state
    @State private var relays: [String] = []
    @State private var showingAddSheet = false
    @State private var newRelayURL = ""

    private let defaultRelays = ["wss://relay.nostr.band"]
    private let storageKey = "chirp_search_relays"

    var body: some View {
        List {
            Section {
                ForEach(relays, id: \.self) { relay in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatURL(relay))
                            .font(.body)
                        Text("Search relay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteRelays)
            } header: {
                Text("Search Relays")
            } footer: {
                Text("These relays provide search capabilities across the Nostr network. They index events and enable powerful search functionality.")
            }

            Section {
                Button {
                    resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Search Relays")
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
            AddSearchRelaySheet(
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

struct AddSearchRelaySheet: View {
    @Binding var relayURL: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    private let suggestedRelays = [
        "relay.nostr.band",
        "search.nos.today",
        "nostr.wine",
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
            .navigationTitle("Add Search Relay")
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
    let relayCollection = NDKRelayCollection(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager, relayCollection: relayCollection)

    return NavigationStack {
        SearchRelaysView()
            .environment(state)
    }
}
