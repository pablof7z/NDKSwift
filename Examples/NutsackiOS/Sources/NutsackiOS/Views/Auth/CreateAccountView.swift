import SwiftUI
import SwiftData
import NDKSwift

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    
    @State private var displayName = ""
    @State private var about = ""
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var createdSession: NDKSession?
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
            .fullScreenCover(isPresented: $showBackupView) {
                if let session = createdSession {
                    NavigationStack {
                        BackupKeyView(session: session, onComplete: {
                            // Dismiss both the backup view and this create account view
                            showBackupView = false
                            dismiss()
                        })
                    }
                }
            }
        }
    }
    
    private func createAccount() {
        
        guard !displayName.isEmpty else {
            return
        }
        
        isCreating = true
        
        Task {
            do {
                // Create account using NDKAuth system
                let session = try await nostrManager.createNewAccount(
                    displayName: displayName,
                    about: about.isEmpty ? nil : about
                )
                
                await MainActor.run {
                    // Show backup view with session
                    createdSession = session
                    showBackupView = true
                    isCreating = false
                    // Don't set accountCreated here - let BackupKeyView handle it
                }
            } catch {
                
                await MainActor.run {
                    // Add more context to error message
                    if let nostrError = error as? NostrError {
                        errorMessage = "Nostr Error: \(nostrError)"
                    } else {
                        errorMessage = "Failed to create account: \(error.localizedDescription)"
                    }
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
    @Environment(NostrManager.self) private var nostrManager
    let session: NDKSession
    var onComplete: (() -> Void)? = nil
    
    @State private var copiedPrivateKey = false
    @State private var savedKey = false
    @State private var privateKey: String?
    @State private var nsec: String?
    
    var displayName: String {
        session.profileName ?? session.shortIdentifier
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
                    if let nsec = nsec {
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
                    } else {
                        ProgressView("Loading private key...")
                            .padding()
                    }
                }
            }
            
            Spacer()
            
            // Confirmation
            Toggle(isOn: $savedKey) {
                Text("I have saved my private key")
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding(.horizontal)
            
            Button(action: continueToWallet) {
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
        .platformNavigationBarTitleDisplayMode(inline: true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadPrivateKey()
        }
    }
    
    private func loadPrivateKey() {
        Task {
            do {
                if let signer = nostrManager.authManager.activeSigner as? NDKPrivateKeySigner {
                    let privateKeyHex = signer.privateKeyValue
                    let nsecString = try signer.nsec
                    
                    await MainActor.run {
                        privateKey = privateKeyHex
                        nsec = nsecString
                    }
                }
            } catch {
                print("Failed to load private key: \(error)")
            }
        }
    }
    
    private func copyKey() {
        guard let nsec = nsec else { return }
        
        nsec.copyToPasteboard()
        withAnimation {
            copiedPrivateKey = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedPrivateKey = false
            }
        }
    }
    
    private func continueToWallet() {
        // Since the user is now authenticated via NDKAuthManager,
        // ensure state is stable before dismissing to prevent "Welcome Back" screen
        Task {
            // Brief delay to ensure auth state propagation
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                if let onComplete = onComplete {
                    onComplete()
                } else {
                    dismiss()
                }
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