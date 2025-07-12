import SwiftUI
import SwiftData
import NDKSwift

struct MintsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var walletManager: WalletManager
    @Query private var wallets: [CashuWallet]
    @State private var selectedWallet: CashuWallet?
    @State private var showAddMint = false
    @State private var showDiscoverMints = false
    @State private var isDiscovering = false
    
    var mints: [Mint] {
        if let wallet = selectedWallet {
            return wallet.mints
        }
        return wallets.flatMap { $0.mints }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Wallet selector if multiple wallets
                if wallets.count > 1 {
                    Section {
                        Picker("Wallet", selection: $selectedWallet) {
                            Text("All Wallets").tag(nil as CashuWallet?)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as CashuWallet?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section {
                    ForEach(mints) { mint in
                        NavigationLink(destination: MintDetailView(mint: mint)) {
                            MintRow(mint: mint)
                        }
                    }
                } header: {
                    Text("Active Mints")
                }
                
                // Add mint button
                Section {
                    Button(action: { showAddMint = true }) {
                        Label("Add Mint", systemImage: "plus.circle")
                    }
                    
                    Button(action: discoverMints) {
                        if isDiscovering {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Discovering...")
                            }
                        } else {
                            Label("Discover Mints", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(isDiscovering)
                }
            }
            .navigationTitle("Mints")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddMint) {
                AddMintView(targetWallet: selectedWallet, walletManager: walletManager)
            }
        }
    }
    
    private func discoverMints() {
        isDiscovering = true
        
        Task {
            do {
                let discovered = try await walletManager.discoverMints()
                
                await MainActor.run {
                    isDiscovering = false
                    
                    if !discovered.isEmpty {
                        // TODO: Show discovered mints sheet
                        logger.info("Discovered \(discovered.count) mints")
                    }
                }
            } catch {
                await MainActor.run {
                    isDiscovering = false
                    logger.error("Failed to discover mints: \(error)")
                }
            }
        }
    }
}

struct MintRow: View {
    let mint: Mint
    
    var balanceForMint: Int {
        mint.tokens.filter { $0.state == .unspent }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.displayName)
                        .font(.headline)
                    
                    Text(mint.url.host ?? mint.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(balanceForMint)")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    
                    Text("sats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let motd = mint.motd {
                Text(motd)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MintDetailView: View {
    let mint: Mint
    @EnvironmentObject private var walletManager: WalletManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showInfo = false
    @State private var isSyncing = false
    @State private var showRemoveAlert = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            Section {
                LabeledContent("URL", value: mint.url.absoluteString)
                    .textSelection(.enabled)
                
                if let pubkey = mint.pubkey {
                    LabeledContent("Public Key") {
                        Text(pubkey)
                            .font(.caption)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                
                LabeledContent("Units") {
                    Text(mint.units.joined(separator: ", "))
                }
                
                if let lastSync = mint.lastSync {
                    LabeledContent("Last Sync") {
                        Text(lastSync.formatted(.relative(presentation: .abbreviated)))
                    }
                }
            } header: {
                Text("Mint Information")
            }
            
            if let contactInfo = mint.contactInfo, !contactInfo.isEmpty {
                Section {
                    ForEach(contactInfo, id: \.self) { contact in
                        Text(contact)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Contact")
                }
            }
            
            Section {
                Button(action: { showInfo = true }) {
                    Label("View Mint Info", systemImage: "info.circle")
                }
                
                Button(action: syncMint) {
                    Label("Sync Keyset", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncing)
                
                Button(role: .destructive, action: removeMint) {
                    Label("Remove Mint", systemImage: "trash")
                        .foregroundColor(.red)
                }
            } header: {
                Text("Actions")
            }
        }
        .navigationTitle(mint.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInfo) {
            MintInfoView(mint: mint)
                .presentationDetents([.medium, .large])
        }
        .alert("Remove Mint?", isPresented: $showRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                performRemoveMint()
            }
        } message: {
            Text("This will remove the mint from your wallet. Any tokens from this mint will no longer be usable.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func syncMint() {
        isSyncing = true
        
        Task {
            do {
                try await walletManager.activeWallet?.refreshMintKeysets(url: mint.url)
                
                await MainActor.run {
                    mint.lastSync = Date()
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to save mint sync date: \(error)")
                    }
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to sync mint: \(error.localizedDescription)"
                    showError = true
                    isSyncing = false
                }
            }
        }
    }
    
    private func removeMint() {
        showRemoveAlert = true
    }
    
    private func performRemoveMint() {
        Task {
            do {
                try await walletManager.removeMint(url: mint.url)
                
                await MainActor.run {
                    // Remove from local database
                    modelContext.delete(mint)
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        errorMessage = "Failed to remove mint: \(error.localizedDescription)"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove mint: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Mint Info View
struct MintInfoView: View {
    let mint: Mint
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if let name = mint.name {
                    LabeledContent("Name", value: name)
                }
                
                if let description = mint.description {
                    Section("Description") {
                        Text(description)
                            .font(.callout)
                    }
                }
                
                Section("Technical Details") {
                    LabeledContent("URL") {
                        Text(mint.url.absoluteString)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    
                    if let pubkey = mint.pubkey {
                        LabeledContent("Public Key") {
                            Text(pubkey)
                                .font(.caption)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                    
                    LabeledContent("Units") {
                        Text(mint.units.joined(separator: ", "))
                    }
                }
                
                if let motd = mint.motd {
                    Section("Message of the Day") {
                        Text(motd)
                            .font(.callout)
                    }
                }
                
                if let contactInfo = mint.contactInfo, !contactInfo.isEmpty {
                    Section("Contact Information") {
                        ForEach(contactInfo, id: \.self) { contact in
                            Text(contact)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Mint Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Discovered Mints View  
struct DiscoveredMintsView: View {
    let mints: [MintDiscovery.DiscoveredMint]
    let walletManager: WalletManager
    let targetWallet: CashuWallet?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            List(mints) { mint in
                VStack(alignment: .leading, spacing: 12) {
                    // Mint name and description
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mint.announcement.name ?? mint.announcement.mintURL.host ?? "Unknown Mint")
                            .font(.headline)
                        
                        if let description = mint.announcement.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    // Mint URL
                    Label(mint.announcement.mintURL.absoluteString, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    
                    // Contact info
                    if let contact = mint.announcement.contact?.first?.first {
                        Label(contact, systemImage: "envelope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Add button
                    Button(action: { addMint(mint) }) {
                        Label("Add to Wallet", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isAdding)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Discovered Mints")
            .navigationBarTitleDisplayMode(.inline)
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
    
    private func addMint(_ mintInfo: MintDiscovery.DiscoveredMint) {
        isAdding = true
        
        Task {
            do {
                // Add mint through wallet manager
                try await walletManager.addMint(url: mintInfo.announcement.mintURL)
                
                // Create local mint record
                let mint = Mint(url: mintInfo.announcement.mintURL)
                mint.name = mintInfo.announcement.name
                mint.description = mintInfo.announcement.description
                mint.pubkey = mintInfo.announcement.pubkey
                mint.contactInfo = mintInfo.announcement.contact
                mint.motd = mintInfo.announcement.motd
                
                if let wallet = targetWallet {
                    mint.wallet = wallet
                    wallet.mints.append(mint)
                }
                
                await MainActor.run {
                    modelContext.insert(mint)
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        errorMessage = "Failed to save mint: \(error.localizedDescription)"
                        showError = true
                    }
                    isAdding = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add mint: \(error.localizedDescription)"
                    showError = true
                    isAdding = false
                }
            }
        }
    }
}

struct AddMintView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let targetWallet: CashuWallet?
    let walletManager: WalletManager
    
    @State private var mintURL = ""
    @State private var isAdding = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedWallet: CashuWallet?
    
    @Query private var wallets: [CashuWallet]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mint URL", text: $mintURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Mint URL")
                } footer: {
                    Text("Enter the URL of a Cashu mint")
                }
                
                if targetWallet == nil && !wallets.isEmpty {
                    Section {
                        Picker("Add to Wallet", selection: $selectedWallet) {
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as CashuWallet?)
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: addMint) {
                        if isAdding {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Add Mint")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(mintURL.isEmpty || isAdding)
                }
            }
            .navigationTitle("Add Mint")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear {
                if targetWallet == nil {
                    selectedWallet = wallets.first
                }
            }
        }
    }
    
    private func addMint() {
        guard let url = URL(string: mintURL) else {
            errorMessage = "Invalid URL"
            showError = true
            return
        }
        
        let wallet = targetWallet ?? selectedWallet
        guard let wallet = wallet else {
            errorMessage = "No wallet selected"
            showError = true
            return
        }
        
        isAdding = true
        
        Task {
            do {
                // Add mint through wallet manager
                try await walletManager.addMint(url: url)
                
                // Get mint info
                let mintInfo = try? await walletManager.activeWallet?.getMintInfo(url: url)
                
                // Create local mint record
                let mint = Mint(url: url)
                mint.name = mintInfo?.name ?? url.host
                mint.description = mintInfo?.description
                mint.pubkey = mintInfo?.pubkey
                mint.contactInfo = mintInfo?.contact
                mint.motd = mintInfo?.motd
                mint.wallet = wallet
                
                await MainActor.run {
                    wallet.mints.append(mint)
                    modelContext.insert(mint)
                    
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        errorMessage = "Failed to save mint: \(error.localizedDescription)"
                        showError = true
                    }
                    
                    isAdding = false
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