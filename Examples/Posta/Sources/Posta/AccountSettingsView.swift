import SwiftUI
import NDKSwift

struct AccountSettingsView: View {
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var authManager: AuthManager
    @State private var showingAddAccount = false
    @State private var showingDeleteConfirmation = false
    @State private var accountToDelete: Account?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            // Current Accounts
            Section("My Accounts") {
                ForEach(accountManager.accounts) { account in
                    AccountRow(
                        account: account,
                        isActive: account.id == accountManager.activeAccount?.id,
                        onTap: {
                            switchAccount(to: account)
                        },
                        onDelete: {
                            accountToDelete = account
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            
            // Add Account
            Section {
                Button(action: { showingAddAccount = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Account")
                    }
                }
            }
            
            // Sign Out
            if accountManager.activeAccount != nil {
                Section {
                    Button(action: signOut) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.red)
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView(accountManager: accountManager, authManager: authManager)
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let account = accountToDelete {
                    deleteAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this account? This action cannot be undone.")
        }
    }
    
    private func switchAccount(to account: Account) {
        Task {
            accountManager.setActiveAccount(account)
            try? await authManager.login(privateKey: account.privateKey)
            dismiss()
        }
    }
    
    private func deleteAccount(_ account: Account) {
        accountManager.removeAccount(account)
        
        // If no accounts left, sign out
        if accountManager.accounts.isEmpty {
            authManager.logout()
        }
    }
    
    private func signOut() {
        authManager.logout()
        dismiss()
    }
}

struct AccountRow: View {
    let account: Account
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Profile Picture
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(account.name?.first ?? "?"))
                            .font(.headline)
                    )
                
                // Account Info
                VStack(alignment: .leading) {
                    Text(account.name ?? "Anonymous")
                        .font(.headline)
                    Text(String(account.pubkey.prefix(16)) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Active Indicator
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct AddAccountView: View {
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var privateKey = ""
    @State private var showingScanner = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Add Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Import an existing account or create a new one")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Private Key Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key")
                        .font(.headline)
                    
                    HStack {
                        SecureField("nsec1... or hex key", text: $privateKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: importAccount) {
                        Text("Import Account")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(privateKey.isEmpty || isLoading)
                    
                    Button(action: createNewAccount) {
                        Text("Create New Account")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
    }
    
    private func importAccount() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let account = try await accountManager.addAccount(privateKey: privateKey)
                try await authManager.login(privateKey: account.privateKey)
                dismiss()
            } catch {
                errorMessage = "Invalid private key"
            }
            
            isLoading = false
        }
    }
    
    private func createNewAccount() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                let privateKey = Crypto.generatePrivateKey()
                let account = try await accountManager.addAccount(privateKey: privateKey)
                try await authManager.login(privateKey: account.privateKey)
                dismiss()
            } catch {
                errorMessage = "Failed to create account"
            }
            
            isLoading = false
        }
    }
}