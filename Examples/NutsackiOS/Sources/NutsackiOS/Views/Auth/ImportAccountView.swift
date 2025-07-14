import SwiftUI
import SwiftData
import NDKSwift

struct ImportAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var nsecInput = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showScanner = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("nsec1...", text: $nsecInput)
                                .textContentType(.password)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .font(.system(.body, design: .monospaced))
                            
                            Button(action: { showScanner = true }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                            }
                        }
                        
                        Text("Enter your private key (nsec) to import your account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Your private key will be stored securely on this device")
                }
                
                Section {
                    Button(action: importAccount) {
                        Text("Import Account")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(nsecInput.isEmpty)
                }
            }
            .navigationTitle("Import Account")
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
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedValue in
                    nsecInput = scannedValue
                    showScanner = false
                }
            }
        }
    }
    
    private func importAccount() {
        // Convert nsec to hex if needed
        let privateKey: String
        do {
            if nsecInput.starts(with: "nsec1") {
                guard let hex = NostrIdentifier.hex(fromNsec: nsecInput) else {
                    throw NostrError.invalidPrivateKey
                }
                privateKey = hex
            } else {
                privateKey = nsecInput
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return
        }
        
        // Create account immediately with minimal info
        let publicKey: String
        do {
            publicKey = try Crypto.getPublicKey(from: privateKey)
        } catch {
            errorMessage = "Invalid private key: \(error.localizedDescription)"
            showError = true
            return
        }
        
        let account = NostrAccount(
            publicKey: publicKey,
            privateKey: privateKey,
            displayName: "Nostr User"
        )
        
        // Save and navigate immediately
        modelContext.insert(account)
        do {
            try modelContext.save()
            appState.activeAccountID = account.accountID.uuidString
            AppState.showOnboarding = false
            
            // Start login process in background
            Task {
                do {
                    // Login will happen in background
                    try await nostrManager.login(with: privateKey)
                    
                    // Fetch profile in background
                    if let user = nostrManager.currentUser,
                       let ndk = nostrManager.ndk {
                        let metadataFilter = NDKFilter(
                            authors: [user.pubkey],
                            kinds: [0],
                            limit: 1
                        )
                        
                        // Subscribe to profile updates instead of blocking fetch
                        let subscription = ndk.subscribe(filters: [metadataFilter])
                        
                        Task {
                            for try await event in subscription {
                                if let contentData = event.content.data(using: .utf8),
                                   let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                                    // Update account with profile info
                                    await MainActor.run {
                                        account.displayName = profile.displayName ?? profile.name ?? "Nostr User"
                                        account.about = profile.about
                                        account.picture = profile.picture
                                        account.nip05 = profile.nip05
                                        try? modelContext.save()
                                    }
                                    break // Only need first profile event
                                }
                            }
                        }
                    }
                } catch {
                    print("Background login error: \(error)")
                    // User is already in the app, just log the error
                }
            }
            
            dismiss()
        } catch {
            errorMessage = "Failed to save account: \(error.localizedDescription)"
            showError = true
            modelContext.delete(account)
        }
    }
}