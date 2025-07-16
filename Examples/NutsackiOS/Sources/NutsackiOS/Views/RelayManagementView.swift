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
    @State private var relays: [NDKRelay] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading relays...")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if relays.isEmpty {
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
                    ForEach(relays, id: \.url) { relay in
                        RelayRowView(relay: relay)
                    }
                } header: {
                    HStack {
                        Text("Connected Relays")
                        Spacer()
                        RelayConnectionCounter(relays: relays)
                    }
                }
            }
        }
        .task {
            await loadRelays()
        }
    }
    
    private func loadRelays() async {
        let allRelays = await ndk.relays
        await MainActor.run {
            self.relays = allRelays.sorted { $0.url < $1.url }
            self.isLoading = false
        }
    }
}

// View that counts connected relays reactively
struct RelayConnectionCounter: View {
    let relays: [NDKRelay]
    @State private var connectedCount = 0
    @State private var tasks: [Task<Void, Never>] = []
    
    var body: some View {
        Text("\(connectedCount)/\(relays.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onAppear {
                startObserving()
            }
            .onDisappear {
                stopObserving()
            }
    }
    
    private func startObserving() {
        // Cancel any existing tasks
        stopObserving()
        
        // Create a task for each relay to observe its state
        for relay in relays {
            let task = Task {
                for await state in relay.stateStream {
                    await MainActor.run {
                        updateConnectedCount()
                    }
                }
            }
            tasks.append(task)
        }
        
        // Initial count
        Task {
            await updateConnectedCountAsync()
        }
    }
    
    private func stopObserving() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }
    
    private func updateConnectedCount() {
        Task {
            await updateConnectedCountAsync()
        }
    }
    
    private func updateConnectedCountAsync() async {
        var count = 0
        for relay in relays {
            let state = await relay.connectionState
            if case .connected = state {
                count += 1
            }
        }
        await MainActor.run {
            self.connectedCount = count
        }
    }
}

// Individual relay row that observes its own state
struct RelayRowView: View {
    let relay: NDKRelay
    @State private var relayState: NDKRelay.State?
    @State private var showDetails = false
    @State private var observationTask: Task<Void, Never>?
    @State private var relayIcon: Image?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Relay icon
                Group {
                    if let relayIcon = relayIcon {
                        relayIcon
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.url)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        if let state = relayState {
                            ConnectionStatusBadge(state: state.connectionState)
                            
                            if let name = state.info?.name {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            
            // Stats row
            if let state = relayState {
                HStack(spacing: 16) {
                    StatItem(
                        icon: "arrow.up",
                        value: "\(state.stats.messagesSent)",
                        label: "sent"
                    )
                    
                    StatItem(
                        icon: "arrow.down",
                        value: "\(state.stats.messagesReceived)",
                        label: "received"
                    )
                    
                    if let latency = state.stats.latency {
                        StatItem(
                            icon: "timer",
                            value: String(format: "%.0fms", latency * 1000),
                            label: "latency"
                        )
                    }
                    
                    if state.stats.connectionAttempts > 0 {
                        let successRate = Double(state.stats.successfulConnections) / Double(state.stats.connectionAttempts) * 100
                        StatItem(
                            icon: "checkmark.circle",
                            value: String(format: "%.0f%%", successRate),
                            label: "success"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails = true
        }
        .sheet(isPresented: $showDetails) {
            if let state = relayState {
                RelayDetailView(relay: relay, initialState: state)
            }
        }
        .onAppear {
            startObserving()
        }
        .onDisappear {
            stopObserving()
        }
    }
    
    private func startObserving() {
        observationTask = Task {
            for await state in relay.stateStream {
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
            }
        }
    }
    
    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}

struct ConnectionStatusBadge: View {
    let state: NDKRelayConnectionState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.2))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .disconnecting:
            return .orange
        case .failed:
            return .red
        }
    }
    
    private var statusText: String {
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting"
        case .failed:
            return "Failed"
        }
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(value)
                    .fontWeight(.medium)
            }
            Text(label)
                .font(.system(size: 9))
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
                // Add relay to NDK
                await nostrManager.ndk?.addRelay(relayURL)
                
                // Connect to the relay
                // Connect to the newly added relay
                if let ndk = nostrManager.ndk {
                    let relays = await ndk.relays
                    if let relay = relays.first(where: { $0.url == relayURL }) {
                        try await relay.connect()
                    }
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