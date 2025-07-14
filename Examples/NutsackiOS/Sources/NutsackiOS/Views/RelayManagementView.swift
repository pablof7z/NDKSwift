import SwiftUI
import NDKSwift

struct RelayManagementView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var relays: [RelayInfo] = []
    @State private var isLoading = true
    @State private var showAddRelay = false
    @State private var updateTimer: Timer?
    
    struct RelayInfo: Identifiable {
        let id = UUID()
        let relay: NDKRelay
        var state: NDKRelayConnectionState
        var stats: NDKRelayStats
        var info: NDKRelayInformation?
    }
    
    var body: some View {
        NavigationStack {
            List {
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
                        ForEach(relays) { relayInfo in
                            RelayRow(relayInfo: relayInfo)
                        }
                    } header: {
                        HStack {
                            Text("Connected Relays")
                            Spacer()
                            Text("\(connectedCount)/\(relays.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: { showAddRelay = true }) {
                        Label("Add Relay", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Relay Management")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: refreshRelays) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showAddRelay) {
                AddRelayView()
            }
            .task {
                await loadRelays()
                startUpdateTimer()
            }
            .onDisappear {
                stopUpdateTimer()
            }
        }
    }
    
    private var connectedCount: Int {
        relays.filter { 
            if case .connected = $0.state { return true }
            return false
        }.count
    }
    
    private func loadRelays() async {
        guard let ndk = nostrManager.ndk else { return }
        
        let allRelays = await ndk.relays
        var relayInfos: [RelayInfo] = []
        
        for relay in allRelays {
            let state = await relay.connectionState
            let stats = await relay.stats
            let info = await relay.info
            
            relayInfos.append(RelayInfo(
                relay: relay,
                state: state,
                stats: stats,
                info: info
            ))
        }
        
        await MainActor.run {
            self.relays = relayInfos.sorted { $0.relay.url < $1.relay.url }
            self.isLoading = false
        }
    }
    
    private func refreshRelays() {
        Task {
            await loadRelays()
        }
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await loadRelays()
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
}

struct RelayRow: View {
    let relayInfo: RelayManagementView.RelayInfo
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(relayInfo.relay.url)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        ConnectionStatusBadge(state: relayInfo.state)
                        
                        if let name = relayInfo.info?.name {
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
            HStack(spacing: 16) {
                StatItem(
                    icon: "arrow.up",
                    value: "\(relayInfo.stats.messagesSent)",
                    label: "sent"
                )
                
                StatItem(
                    icon: "arrow.down",
                    value: "\(relayInfo.stats.messagesReceived)",
                    label: "received"
                )
                
                if let latency = relayInfo.stats.latency {
                    StatItem(
                        icon: "timer",
                        value: String(format: "%.0fms", latency * 1000),
                        label: "latency"
                    )
                }
                
                if relayInfo.stats.connectionAttempts > 0 {
                    let successRate = Double(relayInfo.stats.successfulConnections) / Double(relayInfo.stats.connectionAttempts) * 100
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            showDetails = true
        }
        .sheet(isPresented: $showDetails) {
            RelayDetailView(relayInfo: relayInfo)
        }
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
    let relayInfo: RelayManagementView.RelayInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @State private var showDisconnectAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // Connection Status
                Section("Connection") {
                    LabeledContent("Status", value: statusText)
                    
                    if let connectedAt = relayInfo.stats.connectedAt {
                        LabeledContent("Connected Since") {
                            Text(connectedAt, style: .relative)
                        }
                    }
                    
                    if let lastMessage = relayInfo.stats.lastMessageAt {
                        LabeledContent("Last Message") {
                            Text(lastMessage, style: .relative)
                        }
                    }
                    
                    LabeledContent("Connection Attempts", value: "\(relayInfo.stats.connectionAttempts)")
                    LabeledContent("Successful Connections", value: "\(relayInfo.stats.successfulConnections)")
                }
                
                // Traffic Statistics
                Section("Traffic") {
                    LabeledContent("Messages Sent", value: "\(relayInfo.stats.messagesSent)")
                    LabeledContent("Messages Received", value: "\(relayInfo.stats.messagesReceived)")
                    LabeledContent("Bytes Sent", value: formatBytes(relayInfo.stats.bytesSent))
                    LabeledContent("Bytes Received", value: formatBytes(relayInfo.stats.bytesReceived))
                    
                    if let latency = relayInfo.stats.latency {
                        LabeledContent("Latency", value: String(format: "%.0f ms", latency * 1000))
                    }
                }
                
                // Signature Verification Stats
                if relayInfo.stats.signatureStats.totalEvents > 0 {
                    Section {
                        LabeledContent("Total Events", value: "\(relayInfo.stats.signatureStats.totalEvents)")
                        LabeledContent("Validated", value: "\(relayInfo.stats.signatureStats.validatedCount)")
                        LabeledContent("Not Validated", value: "\(relayInfo.stats.signatureStats.nonValidatedCount)")
                        LabeledContent("Validation Ratio") {
                            Text(String(format: "%.1f%%", 
                                relayInfo.stats.signatureStats.currentValidationRatio * 100))
                        }
                    } header: {
                        Text("Signature Verification")
                    }
                }
                
                // Relay Information (NIP-11)
                if let info = relayInfo.info {
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
                    if case .connected = relayInfo.state {
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
            .navigationTitle(relayInfo.relay.url)
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
                        await relayInfo.relay.disconnect()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to disconnect from this relay?")
            }
        }
    }
    
    private var statusText: String {
        switch relayInfo.state {
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
                try await relayInfo.relay.connect()
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
        "wss://relay.snort.social",
        "wss://nos.lol",
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
                nostrManager.ndk?.addRelay(relayURL)
                
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