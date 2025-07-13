import SwiftUI
import SwiftData
import NDKSwift

struct ConfigureMintsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @Query private var accounts: [NostrAccount]
    
    @State private var selectedMints: Set<String> = []
    @State private var isConfiguring = false
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
                    Text("You can add or remove mints later")
                }
                
                Section {
                    Button(action: configureMints) {
                        if isConfiguring {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Configure Mints")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedMints.isEmpty || isConfiguring)
                }
            }
            .navigationTitle("Configure Mints")
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
            .onAppear {
                // Pre-select default mint
                selectedMints.insert("https://testnut.cashu.space")
            }
        }
    }
    
    private func configureMints() {
        guard let account = activeAccount else {
            errorMessage = "No active account found"
            showError = true
            return
        }
        
        isConfiguring = true
        
        Task {
            do {
                // Add selected mints to the wallet
                for mintURL in selectedMints {
                    if let url = URL(string: mintURL) {
                        try await walletManager.addMint(url: url)
                    }
                }
                
                // Save wallet configuration
                if let wallet = walletManager.activeWallet {
                    try await wallet.save()
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isConfiguring = false
                }
            }
        }
    }
}

// MARK: - Helper Views
struct MintSelectionRow: View {
    let mint: ConfigureMintsView.MintSuggestion
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