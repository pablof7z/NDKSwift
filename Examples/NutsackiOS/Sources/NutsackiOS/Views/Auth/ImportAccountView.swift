import SwiftUI
import SwiftData
import NDKSwift

struct ImportAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var nsecInput = ""
    @State private var isImporting = false
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
                                .textInputAutocapitalization(.never)
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
                        if isImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Import Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(nsecInput.isEmpty || isImporting)
                }
            }
            .navigationTitle("Import Account")
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
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedValue in
                    nsecInput = scannedValue
                    showScanner = false
                }
            }
        }
    }
    
    private func importAccount() {
        isImporting = true
        
        Task {
            do {
                // Convert nsec to hex if needed
                let privateKey: String
                if nsecInput.starts(with: "nsec1") {
                    guard let hex = NostrIdentifier.hex(fromNsec: nsecInput) else {
                        throw NostrError.invalidPrivateKey
                    }
                    privateKey = hex
                } else {
                    privateKey = nsecInput
                }
                
                // Login with the private key
                try await nostrManager.login(with: privateKey)
                
                guard let user = nostrManager.currentUser else {
                    throw NostrError.notLoggedIn
                }
                
                // Fetch profile
                if let ndk = nostrManager.ndk {
                    let metadataFilter = NDKFilter(
                        authors: [user.npub],
                        kinds: [0],
                        limit: 1
                    )
                    if let event = try? await ndk.fetchEvent(metadataFilter),
                       let contentData = event.content.data(using: .utf8),
                       let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                        await user.setProfile(metadata)
                    }
                }
                
                // Save to local database
                let profile = await user.profile
                let account = NostrAccount(
                    publicKey: user.npub,
                    privateKey: privateKey,
                    displayName: profile?.displayName ?? profile?.name ?? "Nostr User"
                )
                
                account.about = profile?.about
                account.picture = profile?.picture
                account.nip05 = profile?.nip05
                
                await MainActor.run {
                    modelContext.insert(account)
                    do {
                        try modelContext.save()
                        appState.activeAccountID = account.accountID.uuidString
                        AppState.showOnboarding = false
                        dismiss()
                    } catch {
                        errorMessage = "Failed to save account: \(error.localizedDescription)"
                        showError = true
                    }
                    
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isImporting = false
                }
            }
        }
    }
}