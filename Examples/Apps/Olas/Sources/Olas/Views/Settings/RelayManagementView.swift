import SwiftUI
import NDKSwift

struct RelayManagementView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var relays: [RelayInfo] = []
    @State private var newRelayURL = ""
    @State private var showAddRelay = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isConnecting = false
    @State private var relayToRemove: RelayInfo?
    @State private var showRemoveConfirmation = false
    
    struct RelayInfo: Identifiable {
        let id = UUID()
        let url: String
        var status: RelayStatus
        var isRead: Bool
        var isWrite: Bool
        var latency: Int? // in milliseconds
    }
    
    enum RelayStatus {
        case connected
        case connecting
        case disconnected
        case error
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .connecting: return .orange
            case .disconnected: return .gray
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .connected: return "circle.fill"
            case .connecting: return "circle.dotted"
            case .disconnected: return "circle"
            case .error: return "exclamationmark.circle"
            }
        }
    }
    
    var body: some View {
        ZStack {
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with add button
                HStack {
                    Text("Relay Management")
                        .font(OlasDesign.Typography.title)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Spacer()
                    
                    Button(action: {
                        showAddRelay = true
                        OlasDesign.Haptic.selection()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .padding(OlasDesign.Spacing.lg)
                
                // Relay statistics
                relayStatsView
                    .padding(.horizontal, OlasDesign.Spacing.lg)
                    .padding(.bottom, OlasDesign.Spacing.lg)
                
                // Relay list
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.md) {
                        ForEach(relays) { relay in
                            relayRow(relay)
                        }
                    }
                    .padding(OlasDesign.Spacing.lg)
                }
            }
        }
        .onAppear {
            loadRelays()
        }
        .sheet(isPresented: $showAddRelay) {
            addRelaySheet
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Remove Relay", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let relay = relayToRemove {
                    removeRelay(relay)
                }
            }
        } message: {
            Text("Are you sure you want to remove \(relayToRemove?.url ?? "")?")
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var relayStatsView: some View {
        HStack(spacing: OlasDesign.Spacing.lg) {
            statsCard(
                title: "Connected",
                value: "\(relays.filter { $0.status == .connected }.count)",
                color: .green
            )
            
            statsCard(
                title: "Total",
                value: "\(relays.count)",
                color: OlasDesign.Colors.primary
            )
            
            statsCard(
                title: "Avg Latency",
                value: formatLatency(averageLatency()),
                color: .blue
            )
        }
    }
    
    @ViewBuilder
    private func statsCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            Text(value)
                .font(OlasDesign.Typography.title)
                .foregroundColor(color)
            
            Text(title)
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func relayRow(_ relay: RelayInfo) -> some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Status indicator
            Image(systemName: relay.status.icon)
                .foregroundColor(relay.status.color)
                .font(.body)
            
            // Relay info
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                Text(relay.url)
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                    .lineLimit(1)
                
                HStack(spacing: OlasDesign.Spacing.sm) {
                    if relay.isRead {
                        Label("Read", systemImage: "arrow.down.circle")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    if relay.isWrite {
                        Label("Write", systemImage: "arrow.up.circle")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    if let latency = relay.latency {
                        Label("\(latency)ms", systemImage: "speedometer")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            Menu {
                Button(action: {
                    toggleRead(relay)
                }) {
                    Label(relay.isRead ? "Disable Read" : "Enable Read", systemImage: "arrow.down.circle")
                }
                
                Button(action: {
                    toggleWrite(relay)
                }) {
                    Label(relay.isWrite ? "Disable Write" : "Enable Write", systemImage: "arrow.up.circle")
                }
                
                if relay.status == .disconnected {
                    Button(action: {
                        reconnectRelay(relay)
                    }) {
                        Label("Reconnect", systemImage: "arrow.counterclockwise")
                    }
                }
                
                Button(role: .destructive, action: {
                    relayToRemove = relay
                    showRemoveConfirmation = true
                }) {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var addRelaySheet: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: OlasDesign.Spacing.lg) {
                    Text("Add New Relay")
                        .font(OlasDesign.Typography.title2)
                        .foregroundColor(OlasDesign.Colors.text)
                        .padding(.top, OlasDesign.Spacing.lg)
                    
                    VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                        Text("Relay URL")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                        
                        TextField("wss://relay.example.com", text: $newRelayURL)
                            .textFieldStyle(.plain)
                            .padding(OlasDesign.Spacing.md)
                            .background(OlasDesign.Colors.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
                            )
                            #if os(iOS)
                            .autocapitalization(.none)
                            #endif
                            .disableAutocorrection(true)
                    }
                    
                    // Popular relays
                    VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                        Text("Popular Relays")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: OlasDesign.Spacing.sm) {
                                ForEach(popularRelays, id: \.self) { relay in
                                    Button(action: {
                                        newRelayURL = relay
                                        OlasDesign.Haptic.selection()
                                    }) {
                                        Text(relay)
                                            .font(OlasDesign.Typography.caption)
                                            .padding(.horizontal, OlasDesign.Spacing.md)
                                            .padding(.vertical, OlasDesign.Spacing.sm)
                                            .background(OlasDesign.Colors.surface)
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(OlasDesign.Colors.border, lineWidth: 1)
                                            )
                                    }
                                    .foregroundColor(OlasDesign.Colors.text)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: OlasDesign.Spacing.md) {
                        OlasButton(
                            title: "Cancel",
                            action: {
                                showAddRelay = false
                                newRelayURL = ""
                            },
                            style: .secondary
                        )
                        
                        OlasButton(
                            title: isConnecting ? "Connecting..." : "Add Relay",
                            action: addNewRelay,
                            style: .primary,
                            isLoading: isConnecting
                        )
                        .disabled(newRelayURL.isEmpty || isConnecting)
                    }
                    .padding(.bottom, OlasDesign.Spacing.lg)
                }
                .padding(.horizontal, OlasDesign.Spacing.lg)
            }
        }
    }
    
    // MARK: - Data
    
    private let popularRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
        "wss://nostr.wine",
        "wss://relay.snort.social"
    ]
    
    // MARK: - Methods
    
    private func loadRelays() {
        guard let ndk = nostrManager.ndk else { return }
        
        relays = ndk.relayPool.relays.map { relay in
            RelayInfo(
                url: relay.url,
                status: relay.status == .connected ? .connected : .disconnected,
                isRead: true,
                isWrite: true,
                latency: nil
            )
        }
        
        // Measure latency for connected relays
        for (index, relay) in relays.enumerated() where relay.status == .connected {
            measureLatency(for: relay) { latency in
                if let latency = latency {
                    relays[index].latency = latency
                }
            }
        }
    }
    
    private func addNewRelay() {
        guard !newRelayURL.isEmpty, let ndk = nostrManager.ndk else { return }
        
        isConnecting = true
        
        Task {
            do {
                // Normalize the URL
                var normalizedURL = newRelayURL
                if !normalizedURL.hasPrefix("wss://") && !normalizedURL.hasPrefix("ws://") {
                    normalizedURL = "wss://\(normalizedURL)"
                }
                
                // Add relay to pool
                try await ndk.relayPool.addRelay(normalizedURL)
                
                await MainActor.run {
                    OlasDesign.Haptic.success()
                    showAddRelay = false
                    newRelayURL = ""
                    loadRelays()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add relay: \(error.localizedDescription)"
                    showError = true
                    OlasDesign.Haptic.error()
                }
            }
            
            await MainActor.run {
                isConnecting = false
            }
        }
    }
    
    private func removeRelay(_ relay: RelayInfo) {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            // Remove from pool
            ndk.relayPool.removeRelay(relay.url)
            
            await MainActor.run {
                relays.removeAll { $0.id == relay.id }
                OlasDesign.Haptic.success()
            }
        }
    }
    
    private func toggleRead(_ relay: RelayInfo) {
        if let index = relays.firstIndex(where: { $0.id == relay.id }) {
            relays[index].isRead.toggle()
            // TODO: Update relay configuration in NDK
        }
    }
    
    private func toggleWrite(_ relay: RelayInfo) {
        if let index = relays.firstIndex(where: { $0.id == relay.id }) {
            relays[index].isWrite.toggle()
            // TODO: Update relay configuration in NDK
        }
    }
    
    private func reconnectRelay(_ relay: RelayInfo) {
        guard let ndk = nostrManager.ndk else { return }
        
        if let index = relays.firstIndex(where: { $0.id == relay.id }) {
            relays[index].status = .connecting
            
            Task {
                // Reconnect
                if let ndkRelay = ndk.relayPool.relays.first(where: { $0.url == relay.url }) {
                    try? await ndkRelay.connect()
                }
                
                await MainActor.run {
                    loadRelays()
                }
            }
        }
    }
    
    private func measureLatency(for relay: RelayInfo, completion: @escaping (Int?) -> Void) {
        // Simple latency measurement - in production, you'd send a ping event
        let start = Date()
        
        Task {
            // Simulate latency measurement
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            await MainActor.run {
                completion(latency)
            }
        }
    }
    
    private func averageLatency() -> Int? {
        let latencies = relays.compactMap { $0.latency }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / latencies.count
    }
    
    private func formatLatency(_ latency: Int?) -> String {
        guard let latency = latency else { return "N/A" }
        return "\(latency)ms"
    }
}

// MARK: - Preview

struct RelayManagementView_Previews: PreviewProvider {
    static var previews: some View {
        RelayManagementView()
            .environmentObject(AppState())
    }
}