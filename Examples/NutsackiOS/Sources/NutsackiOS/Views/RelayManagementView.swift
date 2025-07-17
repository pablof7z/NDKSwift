import SwiftUI
import NDKSwift

struct RelayManagementView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var showAddRelay = false
    
    var body: some View {
        List {
            if let ndk = nostrManager.ndk {
                RelayListContent(ndk: ndk)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("NDK not initialized")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
            
            Section {
                Button(action: { showAddRelay = true }) {
                    Label("Add Relay", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Relay Management")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .sheet(isPresented: $showAddRelay) {
            AddRelayView()
        }
    }
}

// Separate view for relay list content that observes NDK relays
struct RelayListContent: View {
    let ndk: NDK
    @StateObject private var relayCollection: NDKRelayCollection
    
    init(ndk: NDK) {
        self.ndk = ndk
        self._relayCollection = StateObject(wrappedValue: ndk.createRelayCollection())
    }
    
    var body: some View {
        Group {
            if relayCollection.relays.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No relays configured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Add relays to connect to the Nostr network")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(relayCollection.relays) { relayInfo in
                        RelayRowView(relayInfo: relayInfo, ndk: ndk)
                    }
                } header: {
                    HStack {
                        Text("Connected Relays")
                        Spacer()
                        Text("\(relayCollection.connectedCount)/\(relayCollection.totalCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}


// Individual relay row using relay info from collection
struct RelayRowView: View {
    let relayInfo: NDKRelayCollection.RelayInfo
    let ndk: NDK
    @State private var showDetails = false
    @State private var relay: NDKRelay?
    @State private var relayState: NDKRelay.State?
    @State private var relayIcon: Image?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Relay icon
                RelayIconView(icon: relayIcon)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(relayInfo.url)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        ConnectionStatusBadge(state: relayInfo.state, style: .full)
                        
                        if let state = relayState,
                           let name = state.info?.name {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            
            // Stats row
            if let state = relayState {
                RelayStatsView(stats: state.stats)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails = true
        }
        .sheet(isPresented: $showDetails) {
            if let relay = relay, let state = relayState {
                RelayDetailView(relay: relay, initialState: state)
            }
        }
        .task {
            // Get the actual relay and its current state
            await loadRelay()
        }
    }
    
    private func loadRelay() async {
        let allRelays = await ndk.relays
        if let foundRelay = allRelays.first(where: { $0.url == relayInfo.url }) {
            self.relay = foundRelay
            
            // Get initial state
            for await state in foundRelay.stateStream {
                await MainActor.run {
                    self.relayState = state
                    
                    // Load relay icon from NIP-11 data if available
                    if let iconURL = state.info?.icon,
                       let url = URL(string: iconURL),
                       relayIcon == nil {
                        Task {
                            if let data = try? await URLSession.shared.data(from: url).0,
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    self.relayIcon = Image(uiImage: uiImage)
                                }
                            }
                        }
                    }
                }
                // Only need the first state for display
                break
            }
        }
    }
}



// MARK: - Relay Detail View

struct RelayDetailView: View {
    let relay: NDKRelay
    let initialState: NDKRelay.State
    
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @State private var currentState: NDKRelay.State
    @State private var showDisconnectAlert = false
    @State private var observationTask: Task<Void, Never>?
    
    init(relay: NDKRelay, initialState: NDKRelay.State) {
        self.relay = relay
        self.initialState = initialState
        self._currentState = State(initialValue: initialState)
    }
    
    var body: some View {
        List {
            // Connection Status
            Section("Connection") {
                LabeledContent("Status", value: statusText)
                
                if let connectedAt = currentState.stats.connectedAt {
                    LabeledContent("Connected Since") {
                        Text(connectedAt, style: .relative)
                    }
                }
                
                if let lastMessage = currentState.stats.lastMessageAt {
                    LabeledContent("Last Message") {
                        Text(lastMessage, style: .relative)
                    }
                }
                
                LabeledContent("Connection Attempts", value: "\(currentState.stats.connectionAttempts)")
                LabeledContent("Successful Connections", value: "\(currentState.stats.successfulConnections)")
            }
            
            // Traffic Statistics
            Section("Traffic") {
                LabeledContent("Messages Sent", value: "\(currentState.stats.messagesSent)")
                LabeledContent("Messages Received", value: "\(currentState.stats.messagesReceived)")
                LabeledContent("Bytes Sent", value: formatBytes(currentState.stats.bytesSent))
                LabeledContent("Bytes Received", value: formatBytes(currentState.stats.bytesReceived))
                
                if let latency = currentState.stats.latency {
                    LabeledContent("Latency", value: String(format: "%.0f ms", latency * 1000))
                }
            }
            
            // Signature Verification Stats
            if currentState.stats.signatureStats.totalEvents > 0 {
                Section {
                    LabeledContent("Total Events", value: "\(currentState.stats.signatureStats.totalEvents)")
                    LabeledContent("Validated", value: "\(currentState.stats.signatureStats.validatedCount)")
                    LabeledContent("Not Validated", value: "\(currentState.stats.signatureStats.nonValidatedCount)")
                    LabeledContent("Validation Ratio") {
                        Text(String(format: "%.1f%%", 
                            currentState.stats.signatureStats.currentValidationRatio * 100))
                    }
                } header: {
                    Text("Signature Verification")
                }
            }
            
            // Relay Information (NIP-11)
            if let info = currentState.info {
                Section {
                    if let name = info.name {
                        LabeledContent("Name", value: name)
                    }
                    if let description = info.description {
                        LabeledContent("Description", value: description)
                    }
                    if let software = info.software {
                        LabeledContent("Software", value: software)
                    }
                    if let version = info.version {
                        LabeledContent("Version", value: version)
                    }
                    if let contact = info.contact {
                        LabeledContent("Contact", value: contact)
                    }
                } header: {
                    Text("Relay Information")
                }
                
                if let supportedNips = info.supportedNips, !supportedNips.isEmpty {
                    Section {
                        Text(supportedNips.map { String($0) }.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text("Supported NIPs")
                    }
                }
            }
            
            // Actions
            Section {
                if case .connected = currentState.connectionState {
                    Button(role: .destructive, action: { showDisconnectAlert = true }) {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: reconnect) {
                        Label("Connect", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationTitle(relay.url)
        .platformNavigationBarTitleDisplayMode(inline: true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Disconnect Relay?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                Task {
                    await relay.disconnect()
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to disconnect from this relay?")
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            stopObserving()
        }
    }
    
    private var statusText: String {
        switch currentState.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting..."
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    private func reconnect() {
        Task {
            do {
                try await relay.connect()
                dismiss()
            } catch {
                print("Failed to reconnect: \(error)")
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func startObserving() {
        observationTask = Task {
            for await state in relay.stateStream {
                await MainActor.run {
                    self.currentState = state
                }
            }
        }
    }
    
    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}

// MARK: - Add Relay View

struct AddRelayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    
    @State private var relayURL = ""
    @State private var isAdding = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Common relays
    let suggestedRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://relayable.org",
        "wss://relay.primal.net"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("wss://relay.example.com", text: $relayURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Relay URL")
                } footer: {
                    Text("Enter a WebSocket URL for a Nostr relay")
                }
                
                Section("Suggested Relays") {
                    ForEach(suggestedRelays, id: \.self) { relay in
                        Button(action: { relayURL = relay }) {
                            HStack {
                                Text(relay)
                                    .foregroundColor(.primary)
                                Spacer()
                                if relayURL == relay {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: addRelay) {
                        if isAdding {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Add Relay")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(relayURL.isEmpty || isAdding)
                }
            }
            .navigationTitle("Add Relay")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addRelay() {
        guard !relayURL.isEmpty else { return }
        
        isAdding = true
        
        Task {
            do {
                // Add relay to NDK and connect to it
                guard let ndk = nostrManager.ndk else {
                    throw NSError(domain: "NutsackiOS", code: 0, userInfo: [NSLocalizedDescriptionKey: "NDK not initialized"])
                }
                
                guard let _ = await ndk.addRelayAndConnect(relayURL) else {
                    throw NSError(domain: "NutsackiOS", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to add relay"])
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isAdding = false
                }
            }
        }
    }
}