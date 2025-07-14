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
    
    @Binding var urlState: URLState?
    
    @State private var showConfigureMints = false
    @State private var navigationDestination: WalletDestination?
    @State private var currentBalance: Int64 = 0
    
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
    
    var body: some View {
        NavigationStack {
            VStack {
                if walletManager.activeWallet == nil {
                    EmptyWalletView(showConfigureMints: $showConfigureMints)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Balance card
                            BalanceCard(balance: Int(currentBalance))
                                .padding(.horizontal)
                            
                            // Mint allocation pie chart
                            MintAllocationChart()
                                .padding(.horizontal)
                            
                            // Recent transactions
                            RecentTransactionsView()
                                .padding(.horizontal)
                        }
                        .padding(.top)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    ActionButtonsView(navigationDestination: $navigationDestination)
                        .padding()
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
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if walletManager.activeWallet != nil {
                        Button(action: { showConfigureMints = true }) {
                            Image(systemName: "building.columns")
                        }
                    }
                }
            }
            .sheet(isPresented: $showConfigureMints) {
                ConfigureMintsView()
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .mint:
                    MintView()
                case .send:
                    SendView()
                case .receive(let urlString):
                    ReceiveView(tokenString: urlString)
                case .melt:
                    MeltView()
                case .nutzap:
                    NutzapView()
                case .swap:
                    SwapView()
                }
            }
            .onAppear {
                updateBalance()
            }
            .onChange(of: navigationDestination) { oldValue, newValue in
                // Update balance when returning from send/receive/melt/mint operations
                if oldValue != nil && newValue == nil {
                    updateBalance()
                }
            }
            .onChange(of: urlState) { oldValue, newValue in
                if let newValue {
                    navigationDestination = .receive(urlString: newValue.url)
                    urlState = nil
                }
            }
        }
    }
    
    private func updateBalance() {
        Task {
            guard let wallet = walletManager.activeWallet else { return }
            do {
                let balance = try await wallet.getBalance()
                await MainActor.run {
                    currentBalance = balance
                }
            } catch {
                print("Failed to update balance: \(error)")
            }
        }
    }
}

// MARK: - Empty Wallet View
struct EmptyWalletView: View {
    @Binding var showConfigureMints: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "wallet.pass")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("Wallet Not Configured")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Configure mints to start using lightning-fast payments")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            
            Button(action: { showConfigureMints = true }) {
                Label("Configure Mints", systemImage: "building.columns.fill")
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