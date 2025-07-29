import SwiftUI
import NDKSwift

/// A unified relay management view for Nostr apps
public struct NDKUIRelayManagementView: View {
    private let ndk: NDK
    @State private var relays: [NDKRelay] = []
    @State private var showingAddRelay = false
    @State private var newRelayUrl = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    public var body: some View {
        List {
            Section(header: Text("Connected Relays")) {
                ForEach(relays, id: \.url) { relay in
                    RelayRow(relay: relay, onRemove: {
                        removeRelay(relay)
                    })
                }
            }
            
            Section {
                Button(action: { showingAddRelay = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Relay")
                    }
                }
            } footer: {
                Text("Relays are servers that store and distribute Nostr events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Relay Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadRelays()
        }
        .sheet(isPresented: $showingAddRelay) {
            NavigationView {
                AddRelaySheet(
                    relayUrl: $newRelayUrl,
                    onAdd: { url in
                        Task {
                            await addRelay(url)
                            showingAddRelay = false
                            newRelayUrl = ""
                        }
                    },
                    onCancel: {
                        showingAddRelay = false
                        newRelayUrl = ""
                    }
                )
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
            }
        }
    }
    
    private func loadRelays() {
        relays = Array(ndk.pool.relays.values)
            .sorted { $0.url < $1.url }
    }
    
    private func addRelay(_ urlString: String) async {
        isLoading = true
        defer { isLoading = false }
        
        // Clean up URL
        var cleanUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add wss:// if no scheme
        if !cleanUrl.hasPrefix("ws://") && !cleanUrl.hasPrefix("wss://") {
            cleanUrl = "wss://\(cleanUrl)"
        }
        
        // Validate URL
        guard URL(string: cleanUrl) != nil else {
            errorMessage = "Invalid relay URL"
            showingError = true
            return
        }
        
        // Check if already exists
        if relays.contains(where: { $0.url == cleanUrl }) {
            errorMessage = "Relay already added"
            showingError = true
            return
        }
        
        // Add relay
        do {
            let relay = await ndk.addRelayAndConnect(cleanUrl)
            if relay != nil {
                loadRelays()
                
                // Publish updated relay list
                await publishRelayList()
            } else {
                errorMessage = "Failed to connect to relay"
                showingError = true
            }
        }
    }
    
    private func removeRelay(_ relay: NDKRelay) {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            await ndk.removeRelay(relay.url)
            loadRelays()
            
            // Publish updated relay list
            await publishRelayList()
        }
    }
    
    private func publishRelayList() async {
        guard let signer = ndk.signer else { return }
        
        do {
            // Create relay list from current relays
            let relayList = NDKRelayList(ndk: ndk)
            
            // Add all relays with read/write access
            for relay in relays {
                relayList.addRelay(relay.url, access: [.read, .write])
            }
            
            // Sign and publish
            try await relayList.sign()
            _ = try await ndk.publishRelayList(relayList)
        } catch {
            NDKLogger.log(.error, category: .relay, "Failed to publish relay list: \(error)")
        }
    }
}

// MARK: - Relay Row View
private struct RelayRow: View {
    let relay: NDKRelay
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatRelayUrl(relay.url))
                    .font(.body)
                
                HStack(spacing: 12) {
                    // Connection status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(relay.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(relay.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Supported NIPs if available
                    if let supportedNips = relay.info?.supportedNips, !supportedNips.isEmpty {
                        Text("NIPs: \(supportedNips.prefix(3).map(String.init).joined(separator: ", "))\(supportedNips.count > 3 ? "..." : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    private func formatRelayUrl(_ url: String) -> String {
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

// MARK: - Add Relay Sheet
private struct AddRelaySheet: View {
    @Binding var relayUrl: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    // Common relay suggestions
    private let suggestedRelays = [
        "relay.damus.io",
        "nos.lol",
        "relay.primal.net",
        "relay.nostr.band",
        "relay.nostr.wine",
        "relay.nostrgraph.net",
        "relay.current.fyi",
        "relay.snort.social"
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Add Relay")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relay URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("wss://relay.example.com", text: $relayUrl)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Relays")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(suggestedRelays, id: \.self) { relay in
                        Button(action: {
                            relayUrl = relay
                            isTextFieldFocused = true
                        }) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                                    .frame(width: 30)
                                
                                Text(relay)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
                
                Spacer(minLength: 40)
            }
        }
        .navigationBarItems(
            leading: Button("Cancel") {
                onCancel()
            },
            trailing: Button("Add") {
                onAdd(relayUrl)
            }
            .disabled(relayUrl.isEmpty)
        )
        .onAppear {
            isTextFieldFocused = true
        }
    }
}