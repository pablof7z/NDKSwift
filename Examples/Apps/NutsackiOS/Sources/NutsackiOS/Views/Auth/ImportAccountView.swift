import SwiftUI
import SwiftData
import NDKSwift

struct ImportAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    
    @State private var nsecInput = ""
    @State private var isLoggingIn = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showScanner = false
    @State private var profileTask: Task<Void, Never>?
    
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
                        
                        Text("Enter your private key (nsec) to log in to your account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Your private key will be stored securely on this device")
                }
                
                Section {
                    Button(action: loginWithAccount) {
                        if isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(nsecInput.isEmpty || isLoggingIn)
                }
            }
            .navigationTitle("Log In")
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
            .onDisappear {
                profileTask?.cancel()
            }
        }
    }
    
    private func loginWithAccount() {
        print("🔑 [ImportAccountView] loginWithAccount() called")
        isLoggingIn = true
        
        Task {
            do {
                print("🔑 [ImportAccountView] Logging in with nsec...")
                // Create signer to get pubkey and fetch profile
                let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                let pubkey = try await signer.pubkey
                
                // Observe the user's profile (kind 0) to get their display name
                print("🔑 [ImportAccountView] Observing profile for pubkey: \(pubkey)")
                var displayName = "Nostr User"
                
                if let ndk = nostrManager.ndk {
                    // Use declarative data source for profile
                    let profileDataSource = ndk.observe(
                        filter: NDKFilter(
                            authors: [pubkey],
                            kinds: [0]
                        ),
                        maxAge: 3600,
                        cachePolicy: .cacheWithNetwork
                    )
                    
                    for await event in profileDataSource.events {
                        if let profileData = event.content.data(using: .utf8),
                           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
                            displayName = profile.displayName ?? profile.name ?? "Nostr User"
                            print("🔑 [ImportAccountView] Using display name: \(displayName)")
                            break // We only need the first profile for login
                        }
                    }
                }
                
                // Create session using NDKAuth system
                print("🔑 [ImportAccountView] Creating session...")
                let session = try await nostrManager.createAccountFromNsec(
                    nsecInput,
                    displayName: displayName
                )
                print("🔑 [ImportAccountView] Session created successfully: \(session.id)")
                
                await MainActor.run {
                    print("🔑 [ImportAccountView] Login successful, waiting for auth state to stabilize...")
                    isLoggingIn = false
                    // Ensure the auth state is fully propagated before dismissing
                    // This prevents the "Welcome Back" screen from briefly appearing
                    Task {
                        // Wait a moment for the auth state to stabilize
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        print("🔑 [ImportAccountView] Dismissing view")
                        dismiss()
                    }
                }
            } catch {
                print("🔑 [ImportAccountView] Login error: \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoggingIn = false
                }
            }
        }
    }
}