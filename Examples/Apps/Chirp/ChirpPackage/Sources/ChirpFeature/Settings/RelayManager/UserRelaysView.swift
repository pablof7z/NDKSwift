import SwiftUI
@preconcurrency import NDKSwiftCore

struct UserRelaysView: View {
    @Environment(ChirpState.self) private var state
    @State private var relayList: NDKRelayList?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showingAddSheet = false
    @State private var newRelayURL = ""
    @State private var newRelayAccess: Set<NDKRelayAccess> = [.read, .write]
    @State private var errorMessage: String?
    @State private var hasUnsavedChanges = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading relay list...")
            } else if let relayList = relayList {
                relayListContent(relayList)
            } else {
                VStack(spacing: 24) {
                    ContentUnavailableView(
                        "No Relay List",
                        systemImage: "person.text.rectangle.slash",
                        description: Text("Create your relay list to let others know where to find you")
                    )

                    Button("Create Relay List") {
                        createRelayList()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("User Relays")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if relayList != nil {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if hasUnsavedChanges {
                    Button {
                        Task { await saveRelayList() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task {
            await loadRelayList()
        }
        .refreshable {
            await loadRelayList()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddUserRelaySheet(
                relayURL: $newRelayURL,
                access: $newRelayAccess,
                onAdd: { url, access in
                    addRelay(url, access: access)
                    showingAddSheet = false
                    newRelayURL = ""
                    newRelayAccess = [.read, .write]
                },
                onCancel: {
                    showingAddSheet = false
                    newRelayURL = ""
                    newRelayAccess = [.read, .write]
                }
            )
        }
    }

    @ViewBuilder
    private func relayListContent(_ list: NDKRelayList) -> some View {
        List {
            if !list.readRelays.isEmpty || !list.writeRelays.isEmpty {
                let readOnly = list.relayEntries.filter { $0.canRead && !$0.canWrite }
                let writeOnly = list.relayEntries.filter { $0.canWrite && !$0.canRead }
                let readWrite = list.relayEntries.filter { $0.canRead && $0.canWrite }

                if !readWrite.isEmpty {
                    Section("Read & Write") {
                        ForEach(readWrite, id: \.relay.url) { entry in
                            UserRelayRow(entry: entry, onUpdateAccess: { newAccess in
                                updateRelayAccess(entry.relay.url, access: newAccess)
                            })
                        }
                        .onDelete { offsets in
                            deleteRelays(entries: readWrite, at: offsets)
                        }
                    }
                }

                if !readOnly.isEmpty {
                    Section("Read Only") {
                        ForEach(readOnly, id: \.relay.url) { entry in
                            UserRelayRow(entry: entry, onUpdateAccess: { newAccess in
                                updateRelayAccess(entry.relay.url, access: newAccess)
                            })
                        }
                        .onDelete { offsets in
                            deleteRelays(entries: readOnly, at: offsets)
                        }
                    }
                }

                if !writeOnly.isEmpty {
                    Section("Write Only") {
                        ForEach(writeOnly, id: \.relay.url) { entry in
                            UserRelayRow(entry: entry, onUpdateAccess: { newAccess in
                                updateRelayAccess(entry.relay.url, access: newAccess)
                            })
                        }
                        .onDelete { offsets in
                            deleteRelays(entries: writeOnly, at: offsets)
                        }
                    }
                }

                Section {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if hasUnsavedChanges {
                        Label("You have unsaved changes", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Your relay list (NIP-65) tells other clients where to find your events and where to send events to you.")
                }
            } else {
                ContentUnavailableView(
                    "No Relays",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Add relays to your list")
                )
            }
        }
    }

    private func loadRelayList() async {
        isLoading = true
        defer { isLoading = false }

        do {
            relayList = try await state.ndk.fetchRelayList()
            hasUnsavedChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createRelayList() {
        let newList = NDKRelayList(ndk: state.ndk)

        // Add default relays
        newList.addRelay("wss://relay.damus.io")
        newList.addRelay("wss://nos.lol")
        newList.addRelay("wss://relay.primal.net")

        relayList = newList
        hasUnsavedChanges = true
    }

    private func addRelay(_ urlString: String, access: Set<NDKRelayAccess>) {
        guard let list = relayList else { return }

        let cleanUrl = ensureWebSocketScheme(urlString)
        list.addRelay(cleanUrl, access: access)
        hasUnsavedChanges = true

        // Force view update
        relayList = list
    }

    private func updateRelayAccess(_ url: String, access: Set<NDKRelayAccess>) {
        guard let list = relayList else { return }

        list.updateRelayAccess(url, access: access)
        hasUnsavedChanges = true

        // Force view update
        relayList = list
    }

    private func deleteRelays(entries: [NDKRelayListEntry], at offsets: IndexSet) {
        guard let list = relayList else { return }

        for index in offsets {
            let entry = entries[index]
            list.removeRelay(entry.relay.url)
        }

        hasUnsavedChanges = true
        relayList = list
    }

    private func saveRelayList() async {
        guard let list = relayList else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await state.ndk.publishRelayList(list)
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func ensureWebSocketScheme(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("wss://") || trimmed.hasPrefix("ws://") {
            return trimmed
        }
        return "wss://\(trimmed)"
    }
}

struct UserRelayRow: View {
    let entry: NDKRelayListEntry
    let onUpdateAccess: (Set<NDKRelayAccess>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatURL(entry.relay.url))
                .font(.body)

            HStack(spacing: 16) {
                Toggle("Read", isOn: Binding(
                    get: { entry.canRead },
                    set: { newValue in
                        var access = entry.access
                        if newValue {
                            access.insert(.read)
                        } else {
                            access.remove(.read)
                        }
                        if !access.isEmpty {
                            onUpdateAccess(access)
                        }
                    }
                ))
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(entry.canRead ? .blue : .gray)

                Toggle("Write", isOn: Binding(
                    get: { entry.canWrite },
                    set: { newValue in
                        var access = entry.access
                        if newValue {
                            access.insert(.write)
                        } else {
                            access.remove(.write)
                        }
                        if !access.isEmpty {
                            onUpdateAccess(access)
                        }
                    }
                ))
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(entry.canWrite ? .green : .gray)
            }
            .font(.caption)
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
}

struct AddUserRelaySheet: View {
    @Binding var relayURL: String
    @Binding var access: Set<NDKRelayAccess>
    let onAdd: (String, Set<NDKRelayAccess>) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay URL") {
                    TextField("wss://relay.example.com", text: $relayURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("Read", isOn: Binding(
                        get: { access.contains(.read) },
                        set: { if $0 { access.insert(.read) } else { access.remove(.read) } }
                    ))

                    Toggle("Write", isOn: Binding(
                        get: { access.contains(.write) },
                        set: { if $0 { access.insert(.write) } else { access.remove(.write) } }
                    ))
                } header: {
                    Text("Access")
                } footer: {
                    Text("Read: Others can find your events here\nWrite: You publish events here")
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(relayURL, access)
                    }
                    .disabled(relayURL.isEmpty || access.isEmpty)
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
        UserRelaysView()
            .environment(state)
    }
}
