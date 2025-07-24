import SwiftUI
import NDKSwift

struct RelaySettingsView: View {
    @Environment(RelayManager.self) var relayManager
    @Environment(NDKManager.self) var ndkManager
    @State private var showingAddRelay = false
    @State private var newRelayUrl = ""
    @State private var showingResetConfirmation = false
    
    var body: some View {
        List {
            if let ndk = ndkManager.ndk {
                RelayListContent(ndk: ndk, relayManager: relayManager)
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
            
            // Actions Section
            Section {
                Button(action: { showingAddRelay = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Relay")
                    }
                }
                
                Button(action: { showingResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.orange)
                        Text("Reset to Defaults")
                    }
                }
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddRelay) {
            AddRelayView()
        }
        .confirmationDialog(
            "Reset Relays",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                relayManager.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all custom relays and restore the default relay list.")
        }
    }
}

// Separate view for relay list content that observes NDK relays
struct RelayListContent: View {
    let ndk: NDK
    let relayManager: RelayManager
    @StateObject private var relayCollection: NDKRelayCollection
    
    init(ndk: NDK, relayManager: RelayManager) {
        self.ndk = ndk
        self.relayManager = relayManager
        self._relayCollection = StateObject(wrappedValue: ndk.createRelayCollection())
    }
    
    var body: some View {
        Group {
            // Stats Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(relayCollection.connectedCount) of \(relayCollection.totalCount) connected")
                            .font(.headline)
                        Text("Active relays")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .padding()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            
            // Relay List
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
                Section("Relays") {
                    ForEach(relayCollection.relays) { relayInfo in
                        RelayRow(relayInfo: relayInfo, ndk: ndk, relayManager: relayManager)
                    }
                }
            }
        }
    }
}

struct RelayRow: View {
    let relayInfo: NDKRelayCollection.RelayInfo
    let ndk: NDK
    let relayManager: RelayManager
    @State private var showDetails = false
    @State private var relay: NDKRelay?
    @State private var relayState: NDKRelay.State?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(relayInfo.url)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(relayInfo.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(relayInfo.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let state = relayState,
                       let name = state.info?.name {
                        Text("• \(name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if relayManager.userAddedRelays.contains(relayInfo.url) {
                Button(role: .destructive, action: {
                    relayManager.removeUserRelay(relayInfo.url)
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showDetails) {
            if let relay = relay, let state = relayState {
                RelayDetailView(relay: relay, initialState: state, relayManager: relayManager)
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
    let relayManager: RelayManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentState: NDKRelay.State
    @State private var showDisconnectAlert = false
    @State private var observationTask: Task<Void, Never>?
    
    init(relay: NDKRelay, initialState: NDKRelay.State, relayManager: RelayManager) {
        self.relay = relay
        self.initialState = initialState
        self.relayManager = relayManager
        self._currentState = State(initialValue: initialState)
    }
    
    var body: some View {
        NavigationStack {
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
                    
                    // Allow removing user-added relays
                    if relayManager.userAddedRelays.contains(relay.url) {
                        Button(role: .destructive, action: removeRelay) {
                            Label("Remove from App", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(relay.url)
            .navigationBarTitleDisplayMode(.inline)
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
    
    private func removeRelay() {
        Task {
            // Remove relay from manager
            relayManager.removeUserRelay(relay.url)
            
            await MainActor.run {
                dismiss()
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

struct AddRelayView: View {
    @Environment(RelayManager.self) var relayManager
    @Environment(NDKManager.self) var ndkManager
    @Environment(\.dismiss) var dismiss
    
    @State private var relayUrl = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isAdding = false
    
    let suggestedRelays = [
        RelayConstants.damus,
        RelayConstants.nostrBand,
        "wss://relayable.org", 
        RelayConstants.nosLol,
        RelayConstants.snortSocial,
        RelayConstants.nostrWine
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Input Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relay URL")
                        .font(.headline)
                    
                    TextField("wss://relay.example.com", text: $relayUrl)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Suggested Relays
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Relays")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(suggestedRelays, id: \.self) { relay in
                                // Check both with and without trailing slash
                                if !relayManager.userAddedRelays.contains(relay) && 
                                   !relayManager.userAddedRelays.contains(relay + "/") &&
                                   !relayManager.userAddedRelays.contains(String(relay.dropLast())) {
                                    Button(action: { 
                                        relayUrl = relay
                                        addRelay(relay) 
                                    }) {
                                        HStack {
                                            Text(relay)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .disabled(isAdding)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Add Relay")
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Add") { 
                    addRelay(relayUrl) 
                }
                .disabled(relayUrl.isEmpty || isAdding)
            )
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addRelay(_ url: String) {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedUrl.isEmpty else {
            errorMessage = "Please enter a relay URL"
            showingError = true
            return
        }
        
        guard trimmedUrl.hasPrefix("wss://") || trimmedUrl.hasPrefix("ws://") else {
            errorMessage = "Relay URL must start with wss:// or ws://"
            showingError = true
            return
        }
        
        isAdding = true
        
        Task {
            do {
                // Add relay to NDK and connect to it
                guard let ndk = ndkManager.ndk else {
                    throw NSError(domain: "PostaApp", code: 0, userInfo: [NSLocalizedDescriptionKey: "NDK not initialized"])
                }
                
                guard let _ = await ndk.addRelayAndConnect(trimmedUrl) else {
                    throw NSError(domain: "PostaApp", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to add relay"])
                }
                
                // Persist the relay for future app launches
                relayManager.addUserRelay(trimmedUrl)
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isAdding = false
                }
            }
        }
    }
}