import SwiftUI
import SwiftData
import NDKSwift
// import Popovers - Removed for build compatibility

struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @Query private var accounts: [NostrAccount]
    @Query private var wallets: [CashuWallet]
    
    @Binding var urlState: URLState?
    
    @State private var selectedWallet: CashuWallet?
    @State private var showCreateWallet = false
    @State private var navigationDestination: WalletDestination?
    @State private var currentBalance: Int64 = 0
    @State private var isLoadingWallet = false
    
    enum WalletDestination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt
        case nutzap
        case swap
        
        var id: String {
            switch self {
            case .mint: return "mint"
            case .send: return "send"
            case .receive(let url): return "receive_\(url ?? "nil")"
            case .melt: return "melt"
            case .nutzap: return "nutzap"
            case .swap: return "swap"
            }
        }
    }
    
    var activeAccount: NostrAccount? {
        accounts.first { $0.accountID.uuidString == appState.activeAccountID }
    }
    
    var activeWallets: [CashuWallet] {
        activeAccount?.wallets ?? []
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if activeWallets.isEmpty {
                    EmptyWalletView(showCreateWallet: $showCreateWallet)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Wallet selector
                            if activeWallets.count > 1 {
                                WalletSelector(
                                    wallets: activeWallets,
                                    selectedWallet: $selectedWallet
                                )
                                .padding(.horizontal)
                            }
                            
                            // Balance card
                            if let wallet = selectedWallet ?? activeWallets.first {
                                BalanceCard(balance: Int(currentBalance))
                                    .padding(.horizontal)
                                
                                // Recent transactions
                                RecentTransactionsView(wallet: wallet)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top)
                    }
                    
                    // Action buttons
                    if selectedWallet != nil || !activeWallets.isEmpty {
                        ActionButtonsView(navigationDestination: $navigationDestination)
                            .padding()
                    }
                }
            }
            .background(
                RadialGradient(
                    gradient: Gradient(colors: [Color(white: 0.12), Color.black]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 400
                )
            )
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCreateWallet = true }) {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreateWallet) {
                CreateWalletView()
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .mint:
                    MintView(wallet: selectedWallet ?? activeWallets.first!)
                case .send:
                    SendView(wallet: selectedWallet ?? activeWallets.first!)
                case .receive(let urlString):
                    ReceiveView(wallet: selectedWallet ?? activeWallets.first!, tokenString: urlString)
                case .melt:
                    MeltView(wallet: selectedWallet ?? activeWallets.first!)
                case .nutzap:
                    NutzapView(wallet: selectedWallet ?? activeWallets.first!)
                case .swap:
                    SwapView(wallet: selectedWallet ?? activeWallets.first!)
                }
            }
            .onAppear {
                if selectedWallet == nil {
                    selectedWallet = activeWallets.first
                }
                loadWallets()
            }
            .onChange(of: urlState) { oldValue, newValue in
                if let newValue {
                    navigationDestination = .receive(urlString: newValue.url)
                    urlState = nil
                }
            }
            .onChange(of: selectedWallet) { _, _ in
                updateBalance()
            }
        }
    }
    
    private func loadWallets() {
        guard let account = activeAccount else { return }
        
        isLoadingWallet = true
        
        Task {
            do {
                // Load the wallet from NIP-60 events
                try await walletManager.loadWallet(for: account)
                
                // Update balance
                let balance = try await walletManager.getBalance()
                
                await MainActor.run {
                    currentBalance = balance
                    isLoadingWallet = false
                }
            } catch {
                logger.error("Failed to load NIP-60 wallet: \(error)")
                await MainActor.run {
                    isLoadingWallet = false
                }
            }
        }
    }
    
    private func updateBalance() {
        Task {
            do {
                let balance = try await walletManager.getBalance()
                await MainActor.run {
                    currentBalance = balance
                }
            } catch {
                logger.error("Failed to update balance: \(error)")
            }
        }
    }
}

// MARK: - Empty Wallet View
struct EmptyWalletView: View {
    @Binding var showCreateWallet: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "wallet.pass")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("No Wallets Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first Cashu wallet to start using lightning-fast payments")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            
            Button(action: { showCreateWallet = true }) {
                Label("Create Wallet", systemImage: "plus.circle.fill")
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Spacer()
        }
    }
}

// MARK: - Action Buttons
struct ActionButtonsView: View {
    @Binding var navigationDestination: WalletView.WalletDestination?
    @State private var showReceiveMenu = false
    @State private var showSendMenu = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Receive button with menu
            Menu {
                Button(action: { navigationDestination = .receive(urlString: nil) }) {
                    Label("Redeem", systemImage: "qrcode")
                }
                
                Button(action: { navigationDestination = .mint }) {
                    Label("Mint", systemImage: "bolt.fill")
                }
            } label: {
                ActionButtonLabel(
                    imageName: "arrow.down",
                    text: "Receive",
                    fade: false
                )
            }
            
            // Send button with menu
            Menu {
                Button(action: { navigationDestination = .send }) {
                    Label("Send", systemImage: "banknote")
                }
                
                Button(action: { navigationDestination = .melt }) {
                    Label("Melt", systemImage: "bolt.fill")
                }
                
                Button(action: { navigationDestination = .nutzap }) {
                    Label("Nutzap", systemImage: "bolt.heart.fill")
                }
                
                Divider()
                
                Button(action: { navigationDestination = .swap }) {
                    Label("Transfer Between Mints", systemImage: "arrow.triangle.swap")
                }
            } label: {
                ActionButtonLabel(
                    imageName: "arrow.up",
                    text: "Send",
                    fade: false
                )
            }
        }
    }
}

// MARK: - Helper Views
struct ActionButtonLabel: View {
    let imageName: String
    let text: String
    let fade: Bool
    
    var body: some View {
        Text("\(Image(systemName: imageName))  \(text)")
            .opacity(fade ? 0.5 : 1)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.3))
            .cornerRadius(10)
    }
}