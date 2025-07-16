import SwiftUI
import SwiftData
import NDKSwift
// import Popovers - Removed for build compatibility

struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    
    @Binding var urlState: URLState?
    
    @State private var navigationDestination: WalletDestination?
    @State private var showScanner = false
    @State private var scannedInvoice: String?
    @State private var showInvoicePreview = false
    @State private var showWalletSettings = false
    
    enum WalletDestination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt
        case nutzap
        case swap
        case relayHealth
        
        var id: String {
            switch self {
            case .mint: return "mint"
            case .send: return "send"
            case .receive(let url): return "receive_\(url ?? "nil")"
            case .melt: return "melt"
            case .nutzap: return "nutzap"
            case .swap: return "swap"
            case .relayHealth: return "relayHealth"
            }
        }
    }
    
    
    var body: some View {
        NavigationStack {
            VStack {
                if walletManager.activeWallet == nil {
                    EmptyWalletView()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Balance card
                            BalanceCard(balance: Int(walletManager.currentBalance))
                                .padding(.horizontal)
                            
                            // Relay status indicator
                            RelayStatusIndicator()
                                .padding(.horizontal)
                                .onTapGesture {
                                    navigationDestination = .relayHealth
                                }
                            
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
                if walletManager.activeWallet != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showWalletSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedValue in
                    handleScannedValue(scannedValue)
                }
            }
            .sheet(isPresented: $showInvoicePreview) {
                if let invoice = scannedInvoice {
                    LightningInvoicePreviewView(invoice: invoice)
                }
            }
            .sheet(isPresented: $showWalletSettings) {
                WalletSettingsView()
                    .environment(nostrManager)
                    .environment(walletManager)
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
                case .relayHealth:
                    RelayHealthView()
                }
            }
            .onAppear {
                print("WalletView - onAppear called")
                print("WalletView - activeWallet: \(walletManager.activeWallet != nil)")
                loadWalletIfNeeded()
            }
            .onChange(of: urlState) { oldValue, newValue in
                if let newValue {
                    navigationDestination = .receive(urlString: newValue.url)
                    urlState = nil
                }
            }
            .onChange(of: nostrManager.isAuthenticated) { oldValue, newValue in
                if newValue && walletManager.activeWallet == nil {
                    loadWalletIfNeeded()
                }
            }
            .task {
                // Monitor for signer availability when authenticated
                while nostrManager.isAuthenticated && walletManager.activeWallet == nil {
                    if nostrManager.ndk?.signer != nil {
                        loadWalletIfNeeded()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        }
    }
    
    private func loadWalletIfNeeded() {
        guard nostrManager.isAuthenticated else { return }
        guard walletManager.activeWallet == nil else { return }
        
        Task {
            do {
                try await walletManager.loadWalletForCurrentUser()
            } catch WalletError.signerNotAvailable {
                // Signer not ready yet, retry after a short delay
                print("Signer not available yet, retrying...")
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Retry once more
                do {
                    try await walletManager.loadWalletForCurrentUser()
                } catch {
                    print("Failed to load wallet after retry: \(error)")
                }
            } catch {
                print("Failed to load wallet: \(error)")
            }
        }
    }
    
    private func handleScannedValue(_ scannedValue: String) {
        showScanner = false
        
        // Check if it's a lightning invoice
        if isLightningInvoice(scannedValue) {
            scannedInvoice = scannedValue
            showInvoicePreview = true
        } else if scannedValue.lowercased().starts(with: "cashu") {
            // Handle cashu token directly
            navigationDestination = .receive(urlString: scannedValue)
        } else {
            // Handle other QR codes
            urlState = URLState(url: scannedValue, timestamp: Date())
        }
    }
    
    private func isLightningInvoice(_ text: String) -> Bool {
        let cleanText = text.lowercased().replacingOccurrences(of: "lightning:", with: "")
        return cleanText.starts(with: "lnbc") || cleanText.starts(with: "lntb") || cleanText.starts(with: "lnbcrt")
    }
}

// MARK: - Empty Wallet View
struct EmptyWalletView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var showWalletSettings = false
    
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
            
            Button(action: { showWalletSettings = true }) {
                Label("Configure Wallet", systemImage: "gearshape.fill")
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .sheet(isPresented: $showWalletSettings) {
                WalletSettingsView()
            }
            
            // Test button to verify NDK publishing works
            Button(action: testPublishEvent) {
                Text("Test Publish Simple Event")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    private func testPublishEvent() {
        Task {
            guard let ndk = nostrManager.ndk,
                  let signer = ndk.signer else {
                print("Test: NDK or signer not available")
                return
            }
            
            do {
                print("Test: Creating test event")
                let testEvent = try await NDKEventBuilder()
                    .content("Test event from Nutsack wallet - " + UUID().uuidString)
                    .kind(1) // Regular text note
                    .build(signer: signer)
                
                print("Test: Publishing test event...")
                let relays = try await ndk.publish(testEvent)
                print("Test: Published to \(relays.count) relays: \(relays.map { $0.url })")
            } catch {
                print("Test: Failed to publish test event: \(error)")
            }
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