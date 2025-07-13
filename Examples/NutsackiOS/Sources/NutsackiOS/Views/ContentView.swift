import SwiftUI
import SwiftData
import NDKSwift
// import Popovers - Removed for build compatibility

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @Query private var accounts: [NostrAccount]
    
    @State private var showOnboarding = false
    @State private var showAuthView = false
    @State private var selectedTab: Tab = .wallet
    @State private var urlState: URLState?
    
    enum Tab {
        case wallet
        case contacts
        case mints
        case settings
    }
    
    var activeAccount: NostrAccount? {
        accounts.first { $0.accountID.uuidString == appState.activeAccountID }
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if activeAccount != nil && nostrManager.currentUser != nil {
                // Main app interface
                TabView(selection: $selectedTab) {
                    WalletView(urlState: $urlState)
                        .tabItem {
                            Label("Wallet", systemImage: "bitcoinsign.circle")
                        }
                        .tag(Tab.wallet)
                    
                    ContactsView()
                        .tabItem {
                            Label("Contacts", systemImage: "person.2")
                        }
                        .tag(Tab.contacts)
                    
                    MintsView()
                        .tabItem {
                            Label("Mints", systemImage: "building.columns")
                        }
                        .tag(Tab.mints)
                    
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(Tab.settings)
                }
                .tint(.orange)
                .background(Color.black)
            } else {
                // Show auth/onboarding
                AuthenticationView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            checkAuthState()
        }
        .onOpenURL { url in
            handleUrl(url)
        }
    }
    
    private func checkAuthState() {
        // Check if we have an active account
        if let activeAccount = activeAccount,
           let privateKey = activeAccount.privateKey {
            // Try to login with stored credentials
            Task {
                do {
                    try await nostrManager.login(with: privateKey)
                    
                    // Load wallet from NIP-60 events
                    // This will automatically create the wallet event if it doesn't exist
                    try await walletManager.loadWallet(for: activeAccount)
                    
                } catch {
                    logger.error("Failed to auto-login: \(error)")
                    // Clear invalid account
                    appState.activeAccountID = nil
                }
            }
        } else if accounts.isEmpty && AppState.showOnboarding {
            showOnboarding = true
        }
    }
    
    private func handleUrl(_ url: URL) {
        logger.info("URL passed to application: \(url.absoluteString)")
        
        if url.scheme == "cashu" || url.scheme == "nostr" {
            selectedTab = .wallet
            urlState = URLState(url: url.absoluteString, timestamp: Date())
        }
    }
}

struct URLState: Equatable {
    let url: String
    let timestamp: Date
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    
    @State private var showCreateAccount = false
    @State private var showImportAccount = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and Title
                VStack(spacing: 20) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange.gradient)
                    
                    Text("Nutsack")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Lightning-fast payments with Nostr")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Auth buttons
                VStack(spacing: 16) {
                    Button(action: { showCreateAccount = true }) {
                        Label("Create Account", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.gradient)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: { showImportAccount = true }) {
                        Label("Import with nsec", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .background(
                RadialGradient(
                    gradient: Gradient(colors: [Color(white: 0.1), .black]),
                    center: .top,
                    startRadius: 100,
                    endRadius: 600
                )
            )
            .navigationDestination(isPresented: $showCreateAccount) {
                CreateAccountView()
            }
            .navigationDestination(isPresented: $showImportAccount) {
                ImportAccountView()
            }
        }
    }
}