import SwiftUI
import SwiftData
import NDKSwift

struct ImportAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var nsecInput = ""
    @State private var displayName = ""
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
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                } header: {
                    Text("Account Name")
                } footer: {
                    Text("You can change this later")
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
                    .disabled(nsecInput.isEmpty || displayName.isEmpty || isImporting)
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
        guard !displayName.isEmpty else {
            errorMessage = "Please enter a display name"
            showError = true
            return
        }
        
        isImporting = true
        
        Task {
            do {
                // Create account using NDKAuth system
                let session = try await nostrManager.createAccountFromNsec(
                    nsecInput,
                    displayName: displayName
                )
                
                await MainActor.run {
                    // Account created successfully, dismiss
                    dismiss()
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