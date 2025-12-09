import SwiftUI
import NDKSwift

struct BlossomSettingsView: View {
    @ObservedObject var manager: NDKBlossomServerManager
    @State private var showAddServer = false
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(manager.userServers.count)")
                            .font(.title.bold())
                        Text("Servers Configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "externaldrive.badge.icloud")
                        .font(.title2)
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                }
            }

            Section("Your Servers") {
                ForEach(Array(manager.userServers.enumerated()), id: \.element) { index, server in
                    BlossomServerRow(
                        serverUrl: server,
                        isPrimary: index == 0,
                        onRemove: {
                            manager.removeUserServer(server)
                        }
                    )
                }
                .onMove { source, destination in
                    manager.moveUserServer(from: source, to: destination)
                }

                Button {
                    showAddServer = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(OlasTheme.Colors.deepTeal)
                        Text("Add Server")
                    }
                }
            }

            Section {
                Text("Servers are tried in order during uploads. Drag to reorder priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Blossom Servers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddServer) {
            AddBlossomServerSheet(
                existingServers: manager.userServers,
                onAdd: { url in
                    manager.addUserServer(url)
                    showAddServer = false
                }
            )
        }
    }
}

struct BlossomServerRow: View {
    let serverUrl: String
    let isPrimary: Bool
    let onRemove: () -> Void

    @State private var showDeleteConfirmation = false

    private var displayUrl: String {
        serverUrl
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayUrl)
                    .font(.body)

                if isPrimary {
                    Text("Primary")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OlasTheme.Colors.deepTeal)
                        .cornerRadius(4)
                }
            }

            Spacer()

            Button {
                if isPrimary && true { // Could check if there are other servers
                    showDeleteConfirmation = true
                } else {
                    onRemove()
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .confirmationDialog(
            "Remove Primary Server?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                onRemove()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is your primary upload server. The next server in the list will become primary.")
        }
    }
}

struct AddBlossomServerSheet: View {
    let existingServers: [String]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var serverUrl = ""

    private let suggestedServers = [
        "https://blossom.primal.net",
        "https://nostr.build",
        "https://void.cat"
    ]

    private var availableSuggestions: [String] {
        suggestedServers.filter { !existingServers.contains($0) }
    }

    private var normalizedUrl: String {
        let trimmed = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private var isValidUrl: Bool {
        let url = normalizedUrl
        guard !url.isEmpty else { return false }
        guard URL(string: url) != nil else { return false }
        return !existingServers.contains(url)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Enter Server URL") {
                    TextField("blossom.example.com", text: $serverUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                if !availableSuggestions.isEmpty {
                    Section("Suggested Servers") {
                        ForEach(availableSuggestions, id: \.self) { server in
                            Button {
                                serverUrl = server.replacingOccurrences(of: "https://", with: "")
                            } label: {
                                HStack {
                                    Text(server.replacingOccurrences(of: "https://", with: ""))
                                    Spacer()
                                    if normalizedUrl == server {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(OlasTheme.Colors.deepTeal)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(normalizedUrl)
                    }
                    .disabled(!isValidUrl)
                }
            }
        }
    }
}
