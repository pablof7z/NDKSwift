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
    @Binding var showScanner: Bool
    
    @State private var navigationDestination: WalletDestination?
    @State private var scannedInvoice: String?
    @State private var showInvoicePreview = false
    @State private var showWalletSettings = false
    @State private var showSettings = false
    
    enum WalletDestination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt
        case nutzap
        case swap
        case relayHealth
        case contacts
        
        var id: String {
            switch self {
            case .mint: return "mint"
            case .send: return "send"
            case .receive(let url): return "receive_\(url ?? "nil")"
            case .melt: return "melt"
            case .nutzap: return "nutzap"
            case .swap: return "swap"
            case .relayHealth: return "relayHealth"
            case .contacts: return "contacts"
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
                            // Balance card with expandable pie chart
                            BalanceCard()
                                .padding(.horizontal)
                                .zIndex(1) // Ensure it stays on top during expansion
                            
                            // Recent transactions
                            RecentTransactionsView()
                                .padding(.horizontal)
                        }
                        .padding(.top)
                    }
                    .scrollIndicators(.hidden)
                    
                    Spacer()
                    
                    // Action buttons
                    ActionButtonsView(navigationDestination: $navigationDestination, showScanner: $showScanner)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                    }
                }
                
                if walletManager.activeWallet != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showWalletSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
                case .contacts:
                    ContactsView()
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
        .tint(.orange)
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

// Premium button style with subtle press effect
struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Action Buttons
struct ActionButtonsView: View {
    @Binding var navigationDestination: WalletView.WalletDestination?
    @Binding var showScanner: Bool
    @State private var showReceiveMenu = false
    @State private var showSendMenu = false
    @State private var scanButtonPressed = false
    
    var body: some View {
        ZStack {
            // Base layer - receive and send buttons touching
            HStack(spacing: 0) {
                // Receive button
                Button(action: { navigationDestination = .mint }) {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 22, weight: .medium))
                        Text("Receive")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                }
                .buttonStyle(PremiumButtonStyle())
                
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
                    
                    Button(action: { navigationDestination = .contacts }) {
                        Label("Contacts", systemImage: "person.2")
                    }
                    
                    Button(action: { navigationDestination = .swap }) {
                        Label("Transfer Between Mints", systemImage: "arrow.triangle.swap")
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .medium))
                        Text("Send")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(white: 0.18),
                                Color(white: 0.12)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            
            // Floating scan button on top
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scanButtonPressed = true
                }
                showScanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scanButtonPressed = false
                }
            }) {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.orange.opacity(0.85)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: Color.orange.opacity(0.4), radius: 12, x: 0, y: 6)
                    .overlay(
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(scanButtonPressed ? 0.92 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(height: 84) // Match the taller scan button
    }
}


// MARK: - Helper Views
