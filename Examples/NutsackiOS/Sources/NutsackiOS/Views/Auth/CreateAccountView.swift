import SwiftUI
import SwiftData
import NDKSwift

struct CreateAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var displayName = ""
    @State private var about = ""
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedPrivateKey: String?
    @State private var showBackupView = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                    
                    TextField("About (optional)", text: $about, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Profile Information")
                } footer: {
                    Text("This information will be public on Nostr")
                }
                
                Section {
                    Button(action: createAccount) {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(displayName.isEmpty || isCreating)
                }
            }
            .navigationTitle("Create Account")
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
            .navigationDestination(isPresented: $showBackupView) {
                if let privateKey = generatedPrivateKey {
                    BackupKeyView(privateKey: privateKey, displayName: displayName)
                }
            }
        }
    }
    
    private func createAccount() {
        isCreating = true
        
        Task {
            do {
                // Create account on Nostr
                let privateKey = try await nostrManager.createNewAccount(
                    displayName: displayName,
                    about: about.isEmpty ? nil : about
                )
                
                // Save to local database
                guard let publicKey = nostrManager.currentUser?.publicKey else {
                    throw NostrError.notLoggedIn
                }
                
                let account = NostrAccount(
                    publicKey: publicKey,
                    privateKey: privateKey,
                    displayName: displayName
                )
                account.about = about.isEmpty ? nil : about
                
                await MainActor.run {
                    modelContext.insert(account)
                    do {
                        try modelContext.save()
                        appState.activeAccountID = account.accountID.uuidString
                        AppState.showOnboarding = false
                        
                        // Show backup view
                        generatedPrivateKey = privateKey
                        showBackupView = true
                    } catch {
                        errorMessage = "Failed to save account: \(error.localizedDescription)"
                        showError = true
                    }
                    
                    isCreating = false
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

// MARK: - Backup Key View
struct BackupKeyView: View {
    @Environment(\.dismiss) private var dismiss
    let privateKey: String
    let displayName: String
    
    @State private var copiedPrivateKey = false
    @State private var savedKey = false
    
    var nsec: String {
        NostrIdentifier.nsec(fromHex: privateKey) ?? privateKey
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Warning header
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
                
                Text("Save Your Private Key")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("This is the only way to access your account. Save it somewhere safe!")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            
            Spacer()
            
            // Key display
            VStack(spacing: 16) {
                Text("Your private key (nsec):")
                    .font(.headline)
                
                VStack {
                    Text(nsec)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                    
                    Button(action: copyKey) {
                        Label(
                            copiedPrivateKey ? "Copied!" : "Copy to Clipboard",
                            systemImage: copiedPrivateKey ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(copiedPrivateKey ? .green : .orange)
                }
            }
            
            Spacer()
            
            // Confirmation
            Toggle(isOn: $savedKey) {
                Text("I have saved my private key")
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.horizontal)
            
            Button(action: { dismiss() }) {
                Text("Continue to Wallet")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(savedKey ? Color.orange : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!savedKey)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .navigationTitle("Backup Key")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    private func copyKey() {
        UIPasteboard.general.string = nsec
        withAnimation {
            copiedPrivateKey = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedPrivateKey = false
            }
        }
    }
}

// Checkbox toggle style from macademia
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 5.0)
                .stroke(lineWidth: 2)
                .frame(width: 22, height: 22)
                .cornerRadius(5.0)
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .bold()
                    }
                }
            configuration.label
        }
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}