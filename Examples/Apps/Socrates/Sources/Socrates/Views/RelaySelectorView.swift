import SwiftUI
import NDKSwift

struct RelaySelectorView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @Binding var selectedRelay: String?
    @Binding var isPresented: Bool
    
    @State private var relayStates: [RelayInfo] = []
    @State private var observerTask: Task<Void, Never>?
    
    struct RelayInfo: Identifiable {
        let id = UUID()
        let url: String
        let isConnected: Bool
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SELECT RELAY")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.3))
            
            // All relays option
            RelaySelectorRowView(
                title: "All Relays",
                subtitle: "\(relayStates.filter { $0.isConnected }.count) connected",
                isSelected: selectedRelay == nil,
                isConnected: true
            ) {
                selectedRelay = nil
                isPresented = false
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Individual relays
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(relayStates) { relay in
                        RelaySelectorRowView(
                            title: formatRelayUrl(relay.url),
                            subtitle: relay.isConnected ? "Connected" : "Disconnected",
                            isSelected: selectedRelay == relay.url,
                            isConnected: relay.isConnected
                        ) {
                            selectedRelay = relay.url
                            isPresented = false
                        }
                        
                        if relay.id != relayStates.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.95))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(20)
        .onAppear {
            startObservingRelays()
        }
        .onDisappear {
            observerTask?.cancel()
        }
    }
    
    private func formatRelayUrl(_ url: String) -> String {
        // Remove wss:// prefix and trailing slash for cleaner display
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
    
    private func startObservingRelays() {
        guard let ndk = nostrManager.ndk else { return }
        
        observerTask = Task {
            // Get initial relay states
            let relays = await ndk.relays
            var states: [RelayInfo] = []
            
            for relay in relays {
                let connectionState = await relay.connectionState
                let isConnected = connectionState == .connected
                states.append(RelayInfo(url: relay.url, isConnected: isConnected))
            }
            
            await MainActor.run {
                self.relayStates = states.sorted { $0.url < $1.url }
            }
            
            // Listen for relay changes
            let changes = await ndk.relayChanges
            for await change in changes {
                switch change {
                case .relayAdded(let relay):
                    let isConnected = await relay.connectionState == .connected
                    await MainActor.run {
                        if !self.relayStates.contains(where: { $0.url == relay.url }) {
                            self.relayStates.append(RelayInfo(url: relay.url, isConnected: isConnected))
                            self.relayStates.sort { $0.url < $1.url }
                        }
                    }
                    
                case .relayRemoved(let url):
                    await MainActor.run {
                        self.relayStates.removeAll { $0.url == url }
                    }
                    
                case .relayConnected(let relay):
                    await MainActor.run {
                        if let index = self.relayStates.firstIndex(where: { $0.url == relay.url }) {
                            self.relayStates[index] = RelayInfo(url: relay.url, isConnected: true)
                        }
                    }
                    
                case .relayDisconnected(let relay):
                    await MainActor.run {
                        if let index = self.relayStates.firstIndex(where: { $0.url == relay.url }) {
                            self.relayStates[index] = RelayInfo(url: relay.url, isConnected: false)
                        }
                    }
                }
            }
        }
    }
}

struct RelaySelectorRowView: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isConnected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Connection indicator
                Circle()
                    .fill(isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 8, height: 8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isSelected ? Color.purple.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}