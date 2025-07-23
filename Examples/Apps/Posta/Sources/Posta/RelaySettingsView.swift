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
            // Stats Section
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(relayManager.relays.filter { $0.isConnected }.count) of \(relayManager.relays.count) connected")
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
            Section("Relays") {
                ForEach(relayManager.relays) { relay in
                    RelayRow(
                        relay: relay,
                        onToggle: { relayManager.toggleRelay(relay) },
                        onDelete: { relayManager.removeRelay(relay) }
                    )
                }
            }
            
            // Add Relay
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
        .onAppear {
            // NDK is now managed centrally
        }
    }
}

struct RelayRow: View {
    let relay: RelayManager.RelayInfo
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(relay.url)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(relay.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(relay.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { relay.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AddRelayView: View {
    @Environment(RelayManager.self) var relayManager
    @Environment(\.dismiss) var dismiss
    
    @State private var relayUrl = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    let suggestedRelays = [
        "wss://relay.nostr.band",
        "wss://nostr.wine",
        "wss://relay.primal.net",
        "wss://nostr-pub.wellorder.net",
        "wss://relay.nostr.info",
        "wss://relay.snort.social",
        "wss://nostr.fmt.wiz.biz",
        "wss://relay.nostr.bg"
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
                                if !relayManager.relays.contains(where: { $0.url == relay || $0.url == relay + "/" }) {
                                    Button(action: { addRelay(relay) }) {
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
                trailing: Button("Add") { addRelay(relayUrl) }
                    .disabled(relayUrl.isEmpty)
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
        
        relayManager.addRelay(trimmedUrl)
        dismiss()
    }
}