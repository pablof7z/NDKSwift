import SwiftUI
import SwiftData
import NDKSwift
import Popovers

struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    
    @Query private var accounts: [NostrAccount]
    @Query private var wallets: [CashuWallet]
    
    @Binding var urlState: URLState?
    
    @State private var selectedWallet: CashuWallet?
    @State private var showCreateWallet = false
    @State private var navigationDestination: WalletDestination?
    
    enum WalletDestination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt
        case nutzap
        
        var id: String {
            switch self {
            case .mint: return "mint"
            case .send: return "send"
            case .receive(let url): return "receive_\(url ?? "nil")"
            case .melt: return "melt"
            case .nutzap: return "nutzap"
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
                                BalanceCard(balance: wallet.balance)
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
        }
    }
    
    private func loadWallets() {
        Task {
            do {
                // Load NIP-60 wallets from Nostr
                let walletEvents = try await nostrManager.fetchNIP60Wallets()
                
                // Sync with local database
                for event in walletEvents {
                    // Parse wallet data and update local state
                    logger.info("Found NIP-60 wallet: \(event.id)")
                }
            } catch {
                logger.error("Failed to load NIP-60 wallets: \(error)")
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
    
    var body: some View {
        HStack(spacing: 16) {
            // Receive button with menu
            Templates.Menu(
                configuration: {
                    $0.popoverAnchor = .bottom
                    $0.originAnchor = .top
                    $0.backgroundColor = Color.black.opacity(0.5)
                }
            ) {
                Templates.MenuItem {
                    navigationDestination = .receive(urlString: nil)
                } label: { fade in
                    MenuButtonLabel(
                        title: "Redeem",
                        subtitle: "Claim Ecash from Token",
                        imageSystemName: "qrcode",
                        fade: fade
                    )
                }
                
                Templates.MenuItem {
                    navigationDestination = .mint
                } label: { fade in
                    MenuButtonLabel(
                        title: "Mint",
                        subtitle: "Create Lightning Invoice",
                        imageSystemName: "bolt.fill",
                        fade: fade
                    )
                }
            } label: { fade in
                ActionButtonLabel(
                    imageName: "arrow.down",
                    text: "Receive",
                    fade: fade
                )
            }
            
            // Send button with menu
            Templates.Menu(
                configuration: {
                    $0.popoverAnchor = .bottom
                    $0.originAnchor = .top
                    $0.backgroundColor = Color.black.opacity(0.5)
                }
            ) {
                Templates.MenuItem {
                    navigationDestination = .send
                } label: { fade in
                    MenuButtonLabel(
                        title: "Send",
                        subtitle: "Create Token to Share",
                        imageSystemName: "banknote",
                        fade: fade
                    )
                }
                
                Templates.MenuItem {
                    navigationDestination = .melt
                } label: { fade in
                    MenuButtonLabel(
                        title: "Melt",
                        subtitle: "Pay Lightning Invoice",
                        imageSystemName: "bolt.fill",
                        fade: fade
                    )
                }
                
                Templates.MenuItem {
                    navigationDestination = .nutzap
                } label: { fade in
                    MenuButtonLabel(
                        title: "Nutzap",
                        subtitle: "Zap with Ecash",
                        imageSystemName: "bolt.heart.fill",
                        fade: fade
                    )
                }
            } label: { fade in
                ActionButtonLabel(
                    imageName: "arrow.up",
                    text: "Send",
                    fade: fade
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

struct MenuButtonLabel: View {
    let title: String
    let subtitle: String
    let imageSystemName: String
    let fade: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.title3)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Spacer()
            Image(systemName: imageSystemName)
        }
        .opacity(fade ? 0.5 : 1)
        .padding()
    }
}