import SwiftUI
import NDKSwift
import CashuSwift

struct OlasWalletView: View {
    let nostrManager: NostrManager
    @StateObject private var walletManager = OlasWalletViewModel()
    @State private var selectedTab = 0
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showAddMint = false
    @State private var showScanner = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Balance Card
                        balanceCard
                        
                        // Action Buttons
                        actionButtons
                        
                        // Mints Section
                        mintsSection
                        
                        // Transaction History
                        transactionHistory
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                    .padding(.vertical, OlasDesign.Spacing.sm)
                }
            }
            .navigationTitle("Lightning Wallet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddMint = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(OlasDesign.Colors.primary)
                    }
                }
            }
            .sheet(isPresented: $showReceive) {
                ReceiveView(walletManager: walletManager)
            }
            .sheet(isPresented: $showSend) {
                SendView(walletManager: walletManager, nostrManager: nostrManager)
            }
            .sheet(isPresented: $showAddMint) {
                AddMintView(walletManager: walletManager)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { result in
                    handleScannedCode(result)
                }
            }
            .task {
                await walletManager.initialize()
                await walletManager.refreshBalance()
            }
        }
    }
    
    private var balanceCard: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Lightning Icon
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Balance
            VStack(spacing: OlasDesign.Spacing.xs) {
                Text("Balance")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(walletManager.totalBalance)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("sats")
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                // USD Equivalent
                if let usdPrice = walletManager.btcPrice {
                    let usdValue = Double(walletManager.totalBalance) * usdPrice / 100_000_000
                    Text("≈ $\(String(format: "%.2f", usdValue)) USD")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                .fill(OlasDesign.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.5), Color.yellow.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Receive Button
            Button {
                showReceive = true
                OlasDesign.Haptic.selection()
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.green)
                    
                    Text("Receive")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OlasDesign.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                )
            }
            
            // Send Button
            Button {
                showSend = true
                OlasDesign.Haptic.selection()
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.orange)
                    
                    Text("Send")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OlasDesign.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                )
            }
            
            // Scan Button
            Button {
                showScanner = true
                OlasDesign.Haptic.selection()
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 32))
                        .foregroundStyle(OlasDesign.Colors.primary)
                    
                    Text("Scan")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OlasDesign.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                )
            }
        }
    }
    
    private var mintsSection: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            HStack {
                Text("Connected Mints")
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Spacer()
                
                Button {
                    showAddMint = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(OlasDesign.Colors.primary)
                }
            }
            
            if walletManager.mints.isEmpty {
                Text("No mints connected yet")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, OlasDesign.Spacing.lg)
            } else {
                ForEach(walletManager.mints) { mint in
                    MintRow(mint: mint)
                }
            }
        }
    }
    
    private var transactionHistory: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            Text("Recent Transactions")
                .font(OlasDesign.Typography.bodyBold)
                .foregroundColor(OlasDesign.Colors.text)
            
            if walletManager.transactions.isEmpty {
                Text("No transactions yet")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, OlasDesign.Spacing.lg)
            } else {
                ForEach(walletManager.transactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
    
    private func handleScannedCode(_ code: String) {
        showScanner = false
        
        // Handle different QR code types
        if code.lowercased().starts(with: "lightning:") || code.lowercased().starts(with: "lnurl") {
            // Lightning invoice or LNURL
            showSend = true
            // Pass the code to SendView
        } else if code.lowercased().starts(with: "cashu:") {
            // Cashu token
            Task {
                await walletManager.redeemToken(code)
            }
        } else if code.lowercased().starts(with: "https://") {
            // Might be a mint URL
            showAddMint = true
        }
    }
}

// MARK: - Mint Row
struct MintRow: View {
    let mint: WalletMint
    
    var body: some View {
        HStack {
            Circle()
                .fill(mint.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text(mint.url)
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(mint.balance) sats")
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .padding(OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                .fill(OlasDesign.Colors.surface)
        )
    }
}

// MARK: - Transaction Row
struct TransactionRow: View {
    let transaction: WalletTransaction
    
    var body: some View {
        NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
            HStack {
                Image(systemName: transaction.type == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(transaction.type == .received ? Color.green : Color.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.description)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    Text(RelativeTimeFormatter.format(transaction.timestamp))
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                }
                
                Spacer()
                
                Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount) sats")
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(transaction.type == .received ? Color.green : OlasDesign.Colors.text)
            }
            .padding(.vertical, OlasDesign.Spacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Wallet View Model
@MainActor
class OlasWalletViewModel: ObservableObject {
    @Published var totalBalance: Int = 0
    @Published var mints: [WalletMint] = []
    @Published var transactions: [WalletTransaction] = []
    @Published var btcPrice: Double?
    
    private var wallet: CashuWallet?
    
    func initialize() async {
        // Initialize Cashu wallet
        // Load saved mints and tokens
        await refreshBalance()
    }
    
    func refreshBalance() async {
        // Calculate total balance across all mints
        totalBalance = mints.reduce(0) { $0 + $1.balance }
        
        // Fetch BTC price
        await fetchBTCPrice()
    }
    
    func redeemToken(_ token: String) async {
        // Redeem Cashu token
    }
    
    private func fetchBTCPrice() async {
        // Fetch current BTC price in USD
        btcPrice = 98000 // Placeholder
    }
}

// MARK: - Models
struct WalletMint: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let balance: Int
    let isActive: Bool
}

struct WalletTransaction: Identifiable {
    let id = UUID()
    let type: TransactionType
    let amount: Int
    let description: String
    let timestamp: Date
    let mint: String?
    let invoice: String?
    
    enum TransactionType {
        case sent
        case received
    }
}