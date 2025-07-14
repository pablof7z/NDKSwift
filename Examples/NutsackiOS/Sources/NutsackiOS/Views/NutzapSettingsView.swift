import SwiftUI
import NDKSwift

struct NutzapSettingsView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var p2pkPubkey: String = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var copiedToClipboard = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("P2PK Public Key", systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(p2pkPubkey.isEmpty ? "Loading..." : p2pkPubkey)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        
                        Spacer()
                        
                        #if os(iOS)
                        Button(action: copyPubkey) {
                            Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                Text("Your Nutzap Receiving Key")
            } footer: {
                Text("This is your wallet's P2PK public key. Others need this to send you nutzaps.")
            }
            
            Section {
                AsyncContentView(
                    operation: { 
                        if let wallet = walletManager.activeWallet {
                            return await wallet.getMints()
                        }
                        return []
                    }
                ) { mints in
                    ForEach(Array(mints.enumerated()), id: \.offset) { _, mint in
                        HStack {
                            Image(systemName: "building.columns")
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading) {
                                Text(mint.url.host ?? mint.url.absoluteString)
                                    .font(.subheadline)
                                Text(mint.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Accepted Mints")
            } footer: {
                Text("People can only send you nutzaps using these mints")
            }
            
            Section {
                Button(action: publishPreferences) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Publish Nutzap Preferences")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isLoading || p2pkPubkey.isEmpty)
            } footer: {
                Text("Publishes your wallet configuration so others can send you nutzaps. This needs to be done at least once.")
            }
        }
        .navigationTitle("Nutzap Settings")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") { }
        } message: {
            Text(successMessage)
        }
        .task {
            await loadP2PKPubkey()
        }
    }
    
    private func loadP2PKPubkey() async {
        do {
            let pubkey = try await walletManager.getP2PKPubkey()
            await MainActor.run {
                p2pkPubkey = pubkey
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load P2PK public key: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func publishPreferences() {
        isLoading = true
        
        Task {
            do {
                try await walletManager.publishNutzapPreferences()
                
                await MainActor.run {
                    isLoading = false
                    successMessage = "Successfully published nutzap preferences! Others can now send nutzaps to your wallet."
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to publish preferences: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    #if os(iOS)
    private func copyPubkey() {
        UIPasteboard.general.string = p2pkPubkey
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedToClipboard = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }
    #endif
}

#Preview {
    NavigationStack {
        NutzapSettingsView()
    }
}