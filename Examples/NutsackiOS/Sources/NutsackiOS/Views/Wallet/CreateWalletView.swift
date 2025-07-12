import SwiftUI
import SwiftData
import NDKSwift

struct CreateWalletView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @Query private var accounts: [NostrAccount]
    
    @State private var walletName = ""
    @State private var walletDescription = ""
    @State private var selectedMints: Set<String> = []
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Default mints to suggest
    let suggestedMints = [
        MintSuggestion(url: "https://testnut.cashu.space", name: "Testnut", description: "Test mint for development"),
        MintSuggestion(url: "https://mint.minibits.cash/Bitcoin", name: "Minibits", description: "Popular Cashu mint"),
        MintSuggestion(url: "https://legend.lnbits.com/cashu/api/v1/4gr9Xcmz3XEkUNwiBiQGoC", name: "LNbits Legend", description: "Reliable mint service")
    ]
    
    struct MintSuggestion: Identifiable {
        let id = UUID()
        let url: String
        let name: String
        let description: String
    }
    
    var activeAccount: NostrAccount? {
        accounts.first { $0.accountID.uuidString == appState.activeAccountID }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wallet Name", text: $walletName)
                        .textContentType(.name)
                    
                    TextField("Description (optional)", text: $walletDescription, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Wallet Information")
                } footer: {
                    Text("This wallet will be backed up to Nostr using NIP-60")
                }
                
                Section {
                    ForEach(suggestedMints) { mint in
                        MintSelectionRow(
                            mint: mint,
                            isSelected: selectedMints.contains(mint.url)
                        ) {
                            if selectedMints.contains(mint.url) {
                                selectedMints.remove(mint.url)
                            } else {
                                selectedMints.insert(mint.url)
                            }
                        }
                    }
                } header: {
                    Text("Select Mints")
                } footer: {
                    Text("You can add more mints later")
                }
                
                Section {
                    Button(action: createWallet) {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Wallet")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(walletName.isEmpty || selectedMints.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Wallet")
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
    
    private func createWallet() {
        guard let account = activeAccount else {
            errorMessage = "No active account found"
            showError = true
            return
        }
        
        isCreating = true
        
        Task {
            do {
                // Create NIP-60 wallet through WalletManager
                let wallet = try await walletManager.createWallet(
                    name: walletName,
                    description: walletDescription.isEmpty ? nil : walletDescription,
                    account: account
                )
                
                // Add additional mints if selected
                for mintURL in selectedMints {
                    if let url = URL(string: mintURL),
                       mintURL != "https://testnut.cashu.space" { // Skip default mint
                        try await walletManager.addMint(url: url)
                        
                        // Update local model
                        if let mint = Mint(url: url) as Mint? {
                            mint.wallet = wallet
                            wallet.mints.append(mint)
                        }
                    }
                }
                
                // Save local changes
                await MainActor.run {
                    do {
                        try modelContext.save()
                    } catch {
                        logger.error("Failed to save local wallet changes: \(error)")
                    }
                }
                
                // Load the wallet to activate it
                try await walletManager.loadWallet(for: account)
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCreating = false
                }
            }
        }
    }
    
}

// MARK: - Helper Views
struct MintSelectionRow: View {
    let mint: CreateWalletView.MintSuggestion
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(mint.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(mint.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}