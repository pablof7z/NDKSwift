import SwiftUI
import NDKSwift
import CashuSwift

struct WalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    
    @State private var mints: [MintInfo] = []
    @State private var relays: [String] = []
    @State private var hasWalletInfo = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAddMintSheet = false
    @State private var showAddRelaySheet = false
    @State private var showDiscoveredMints = false
    @State private var discoveredMints: [DiscoveredMint] = []
    @State private var isDiscovering = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Wallet Configuration Warning
                if !hasWalletInfo && walletManager.activeWallet != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Wallet Not Published")
                                    .font(.headline)
                            }
                            Text("Your wallet configuration hasn't been published to relays. Publishing ensures your wallet data is synchronized across devices.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Publish Wallet Configuration") {
                                Task { await saveSettings() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Mints Section
                Section {
                    if mints.isEmpty {
                        ContentUnavailableView(
                            "No Mints Configured",
                            systemImage: "building.columns",
                            description: Text("Add mints to start using ecash")
                        )
                    } else {
                        ForEach(mints, id: \.url.absoluteString) { mint in
                            MintSettingsRow(mintInfo: mint) {
                                mints.removeAll { $0.url == mint.url }
                            }
                        }
                    }
                    
                    // Add mint buttons
                    HStack(spacing: 16) {
                        Button(action: { showAddMintSheet = true }) {
                            Label("Add Mint", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button(action: discoverMints) {
                            if isDiscovering {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Discovering...")
                                }
                            } else {
                                Label("Discover", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDiscovering)
                    }
                } header: {
                    Text("Mints")
                } footer: {
                    Text("Mints are Cashu servers that issue and redeem ecash tokens")
                }
                
                // Relays Section
                Section {
                    if relays.isEmpty {
                        ContentUnavailableView(
                            "No Relays Configured",
                            systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("Add relays to sync your wallet data")
                        )
                    } else {
                        ForEach(relays, id: \.self) { relay in
                            RelaySettingsRow(relayURL: relay) {
                                relays.removeAll { $0 == relay }
                            }
                        }
                    }
                    
                    Button(action: { showAddRelaySheet = true }) {
                        Label("Add Relay", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Wallet Relays")
                } footer: {
                    Text("These relays will be used to sync your wallet events and mint lists")
                }
            }
            .navigationTitle("Wallet Settings")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSettings() }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showAddMintSheet) {
                AddMintSheet { url in
                    if let mintInfo = try? await fetchMintInfo(url: url) {
                        mints.append(mintInfo)
                    }
                }
            }
            .sheet(isPresented: $showAddRelaySheet) {
                AddRelaySheet { relay in
                    if !relays.contains(relay) {
                        relays.append(relay)
                    }
                }
            }
            .sheet(isPresented: $showDiscoveredMints) {
                DiscoveredMintsSheet(discoveredMints: discoveredMints) { selectedMints in
                    for mint in selectedMints {
                        if !mints.contains(where: { $0.url == mint.url }) {
                            if let mintInfo = try? await fetchMintInfo(url: mint.url) {
                                mints.append(mintInfo)
                            }
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .task {
                await loadCurrentSettings()
            }
        }
    }
    
    private func loadCurrentSettings() async {
        isLoading = true
        
        // Load current configuration directly from the wallet
        if let wallet = walletManager.activeWallet {
            // Get mints from the wallet's mint manager
            let mintURLs = await wallet.mints.getMintURLs()
            let mintURLObjects = mintURLs.compactMap { URL(string: $0) }
            mints = mintURLObjects.map { MintInfo(url: $0, name: $0.host ?? "Unknown Mint") }
            
            // Get relays from the wallet's configuration
            relays = await wallet.walletConfigRelays
            
            // Check if wallet info exists
            hasWalletInfo = await checkWalletInfo()
        }
        
        isLoading = false
    }
    
    private func checkWalletInfo() async -> Bool {
        guard let ndk = nostrManager.ndk,
              let pubkey = try? await ndk.signer?.pubkey else { return false }
        
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [17375]
        )
        
        do {
            let events = try await ndk.fetchEvents([filter])
            return !events.isEmpty
        } catch {
            return false
        }
    }
    
    
    private func fetchMintInfo(url: URL) async throws -> MintInfo {
        // For now, just return a basic MintInfo
        // TODO: Properly fetch mint info when CashuSwift API is available
        return MintInfo(url: url, name: url.host ?? "Unknown Mint")
    }
    
    private func saveSettings() async {
        isSaving = true
        
        do {
            guard let wallet = walletManager.activeWallet else {
                throw WalletError.noActiveWallet
            }
            
            // Convert mints to URL strings
            let mintURLs = mints.map { $0.url.absoluteString }
            
            // Setup wallet with new configuration
            try await wallet.setup(
                mints: mintURLs,
                relays: relays,
                publishMintList: true
            )
            
            // Update wallet info flag
            hasWalletInfo = true
            
            dismiss()
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
            showError = true
        }
        
        isSaving = false
    }
    
    private func discoverMints() {
        isDiscovering = true
        discoveredMints = []
        
        Task {
            guard let ndk = nostrManager.ndk else { 
                await MainActor.run {
                    isDiscovering = false
                }
                return 
            }
            
            let discoveryManager = MintDiscoveryManager(ndk: ndk)
            var hasReceivedMints = false
            
            for await mints in discoveryManager.discoverMintsStream() {
                await MainActor.run {
                    discoveredMints = mints
                    
                    if !hasReceivedMints && !mints.isEmpty {
                        hasReceivedMints = true
                        showDiscoveredMints = true
                    }
                    
                    if isDiscovering && !mints.isEmpty {
                        isDiscovering = false
                    }
                }
            }
            
            await MainActor.run {
                isDiscovering = false
            }
        }
    }
}

// MARK: - Mint Row
struct MintSettingsRow: View {
    let mintInfo: MintInfo
    let onDelete: () -> Void
    @State private var balance: Int64 = 0
    @State private var favicon: Image?
    @Environment(WalletManager.self) private var walletManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Favicon
            Group {
                if let favicon = favicon {
                    favicon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "building.columns.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 40, height: 40)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mintInfo.name ?? mintInfo.url.host ?? "Unknown Mint")
                    .font(.headline)
                Text(mintInfo.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(balance)")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("sats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .task {
            await updateBalance()
            await loadFavicon()
        }
    }
    
    private func updateBalance() async {
        guard let wallet = walletManager.activeWallet else { return }
        let mintBalance = await wallet.getBalance(mint: mintInfo.url)
        await MainActor.run {
            balance = mintBalance
        }
    }
    
    private func loadFavicon() async {
        guard let host = mintInfo.url.host else { return }
        let faviconURL = URL(string: "https://\(host)/favicon.ico")
        
        // Simple favicon loading - in production you'd want proper caching
        if let url = faviconURL,
           let data = try? await URLSession.shared.data(from: url).0,
           let uiImage = UIImage(data: data) {
            await MainActor.run {
                favicon = Image(uiImage: uiImage)
            }
        }
    }
}

// MARK: - Relay Row
struct RelaySettingsRow: View {
    let relayURL: String
    let onDelete: () -> Void
    @State private var relayState: NDKRelay.State?
    @State private var relayIcon: Image?
    @State private var observationTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Relay Icon
            RelayIconView(icon: relayIcon)
            
            VStack(alignment: .leading, spacing: 4) {
                // Use NIP-11 name if available, otherwise use hostname
                Text(relayState?.info?.name ?? getRelayHost(relayURL) ?? "Unknown Relay")
                    .font(.headline)
                    
                HStack(spacing: 8) {
                    Text(relayURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Connection status indicator
                    if let state = relayState {
                        ConnectionStatusBadge(state: state.connectionState, style: .compact)
                    }
                }
            }
            
            Spacer()
            
            // Show NIP-11 info if available
            if let info = relayState?.info {
                RelayInfoView(info: info, style: .compact)
            }
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .task {
            await loadRelayInfo()
        }
        .onDisappear {
            stopObserving()
        }
    }
    
    private func getRelayHost(_ url: String) -> String? {
        URL(string: url)?.host
    }
    
    private func loadRelayInfo() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Get the relay from NDK
        let relays = await ndk.relays
        guard let relay = relays.first(where: { $0.url == relayURL }) else {
            // If relay not found in NDK, just use basic formatting
            if getRelayHost(relayURL) != nil {
                await MainActor.run {
                    relayState = NDKRelay.State(
                        connectionState: .disconnected,
                        stats: NDKRelayStats(),
                        info: nil
                    )
                }
            }
            return
        }
        
        // Start observing relay state
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


// MARK: - Add Mint Sheet
struct AddMintSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mintURL = ""
    @State private var isValidating = false
    let onAdd: (URL) async -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://mint.example.com", text: $mintURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Mint URL")
                } footer: {
                    Text("Enter the URL of a Cashu mint")
                }
            }
            .navigationTitle("Add Mint")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let url = URL(string: mintURL) else { return }
                        Task {
                            await onAdd(url)
                            dismiss()
                        }
                    }
                    .disabled(mintURL.isEmpty || isValidating)
                }
            }
        }
    }
}

// MARK: - Add Relay Sheet
struct AddRelaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var relayURL = ""
    let onAdd: (String) -> Void
    
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
                    Text("Enter a Nostr relay URL (must start with wss:// or ws://)")
                }
            }
            .navigationTitle("Add Relay")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard relayURL.starts(with: "wss://") || relayURL.starts(with: "ws://") else { return }
                        onAdd(relayURL)
                        dismiss()
                    }
                    .disabled(relayURL.isEmpty || (!relayURL.starts(with: "wss://") && !relayURL.starts(with: "ws://")))
                }
            }
        }
    }
}

// MARK: - Discovered Mints Sheet  
struct DiscoveredMintsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let discoveredMints: [DiscoveredMint]
    let onSelect: ([DiscoveredMint]) async -> Void
    @State private var selectedMints: Set<String> = []
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(discoveredMints, id: \.url) { mint in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mint.name ?? mint.url.host ?? "Unknown Mint")
                                .font(.headline)
                            Text(mint.url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if selectedMints.contains(mint.url.absoluteString) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedMints.contains(mint.url.absoluteString) {
                            selectedMints.remove(mint.url.absoluteString)
                        } else {
                            selectedMints.insert(mint.url.absoluteString)
                        }
                    }
                }
            }
            .navigationTitle("Discovered Mints")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Selected") {
                        Task {
                            let selected = discoveredMints.filter { selectedMints.contains($0.url.absoluteString) }
                            await onSelect(selected)
                            dismiss()
                        }
                    }
                    .disabled(selectedMints.isEmpty)
                }
            }
        }
    }
}

// MARK: - Supporting Types
