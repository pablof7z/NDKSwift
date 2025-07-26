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
    @State private var showMintManagement = false
    @State private var refreshRotation: Double = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        OlasDesign.Colors.background,
                        OlasDesign.Colors.surface.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.lg) {
                        // Enhanced Balance Card
                        OlasBalanceCard(walletManager: walletManager)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.top, OlasDesign.Spacing.sm)
                        
                        // Quick Stats
                        quickStats
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Action Buttons
                        actionButtons
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Recent Activity
                        recentActivity
                    }
                    .padding(.bottom, 100) // Space for floating buttons
                }
                .refreshable {
                    await refreshWallet()
                }
            }
            .navigationTitle("⚡ Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 1)) {
                            refreshRotation += 360
                        }
                        Task {
                            await refreshWallet()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(OlasDesign.Colors.primary)
                            .rotationEffect(.degrees(refreshRotation))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showMintManagement = true
                        } label: {
                            Label("Manage Mints", systemImage: "server.rack")
                        }
                        
                        Button {
                            showAddMint = true
                        } label: {
                            Label("Add Mint", systemImage: "plus.circle")
                        }
                        
                        Divider()
                        
                        Button {
                            // Export wallet backup
                        } label: {
                            Label("Backup Wallet", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
            .sheet(isPresented: $showMintManagement) {
                MintManagementView(walletManager: walletManager)
            }
            .task {
                await walletManager.initialize()
                await walletManager.refreshBalance()
            }
        }
    }
    
    private var quickStats: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            // Total Mints
            StatCard(
                icon: "server.rack",
                value: "\(walletManager.mints.count)",
                label: "Mints",
                color: .blue
            )
            
            // Active Tokens
            StatCard(
                icon: "ticket.fill",
                value: "\(walletManager.activeTokens.count)",
                label: "Tokens",
                color: .green
            )
            
            // Today's Activity
            StatCard(
                icon: "arrow.up.arrow.down",
                value: "\(todaysTransactionCount)",
                label: "Today",
                color: .orange
            )
        }
    }
    
    private var todaysTransactionCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return walletManager.transactions.filter { transaction in
            calendar.startOfDay(for: transaction.timestamp) == today
        }.count
    }
    
    private var actionButtons: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            // Receive Button
            ActionButton(
                icon: "arrow.down.circle.fill",
                title: "Receive",
                gradient: [Color.green, Color.green.opacity(0.8)]
            ) {
                showReceive = true
            }
            
            // Send Button
            ActionButton(
                icon: "arrow.up.circle.fill",
                title: "Send",
                gradient: [Color.orange, Color.orange.opacity(0.8)]
            ) {
                showSend = true
            }
            
            // Scan Button
            ActionButton(
                icon: "qrcode.viewfinder",
                title: "Scan",
                gradient: [OlasDesign.Colors.primary, OlasDesign.Colors.primary.opacity(0.8)]
            ) {
                showScanner = true
            }
        }
    }
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
            // Section header
            HStack {
                Text("Recent Activity")
                    .font(OlasDesign.Typography.title3)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Spacer()
                
                NavigationLink(destination: TransactionHistoryView(walletManager: walletManager)) {
                    Text("See All")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.primary)
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            
            if walletManager.transactions.isEmpty {
                EmptyActivityView()
                    .padding(.horizontal, OlasDesign.Spacing.md)
            } else {
                // Show last 5 transactions
                VStack(spacing: 0) {
                    ForEach(walletManager.transactions.prefix(5)) { transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        if transaction.id != walletManager.transactions.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .fill(OlasDesign.Colors.surface)
                )
                .padding(.horizontal, OlasDesign.Spacing.md)
            }
        }
    }
    
    private func refreshWallet() async {
        await walletManager.refreshBalance()
        // Animate refresh
        OlasDesign.Haptic.selection()
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
    @State private var showDetail = false
    
    private var transactionIcon: String {
        switch transaction.type {
        case .sent: return "arrow.up.circle.fill"
        case .received: return "arrow.down.circle.fill"
        }
    }
    
    private var transactionColor: Color {
        switch transaction.type {
        case .sent: return Color.orange
        case .received: return Color.green
        }
    }
    
    var body: some View {
        Button {
            showDetail = true
            OlasDesign.Haptic.selection()
        } label: {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    transactionColor.opacity(0.2),
                                    transactionColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: transactionIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(transactionColor)
                }
                
                // Transaction details
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.description)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(formatRelativeTime(transaction.timestamp))
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                        
                        if let mint = transaction.mint {
                            Text("•")
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                            
                            Text(formatMintName(mint))
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(transaction.type == .received ? "+" : "-")\(formatAmount(transaction.amount))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(transactionColor)
                    
                    Text("sats")
                        .font(.system(size: 11))
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                }
            }
            .padding(.vertical, OlasDesign.Spacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            TransactionDetailView(transaction: transaction)
        }
    }
    
    private func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatMintName(_ mint: String) -> String {
        if let url = URL(string: mint),
           let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return mint
    }
}

// MARK: - Wallet View Model
@MainActor
class OlasWalletViewModel: ObservableObject {
    @Published var totalBalance: Int = 0
    @Published var mints: [WalletMint] = []
    @Published var transactions: [WalletTransaction] = []
    @Published var activeTokens: [CashuToken] = []
    @Published var btcPrice: Double?
    @Published var isLoading = false
    
    private var wallet: CashuWallet?
    
    func initialize() async {
        isLoading = true
        defer { isLoading = false }
        
        // Initialize with sample data for now
        mints = [
            WalletMint(name: "Cashu Mint", url: "https://mint.cashu.space", balance: 50000, isActive: true),
            WalletMint(name: "Bitcoin Mint", url: "https://mint.bitcoin.space", balance: 25000, isActive: true),
            WalletMint(name: "Lightning Mint", url: "https://mint.ln.space", balance: 10000, isActive: false)
        ]
        
        // Sample transactions
        transactions = [
            WalletTransaction(
                type: .received,
                amount: 10000,
                description: "Zap from nostr:alice",
                timestamp: Date().addingTimeInterval(-3600),
                mint: "https://mint.cashu.space",
                invoice: nil
            ),
            WalletTransaction(
                type: .sent,
                amount: 5000,
                description: "Coffee payment",
                timestamp: Date().addingTimeInterval(-7200),
                mint: "https://mint.bitcoin.space",
                invoice: nil
            ),
            WalletTransaction(
                type: .received,
                amount: 25000,
                description: "Invoice payment",
                timestamp: Date().addingTimeInterval(-86400),
                mint: "https://mint.cashu.space",
                invoice: "lnbc..."
            )
        ]
        
        // Sample tokens
        activeTokens = [
            CashuToken(id: "token1", amount: 1000, mint: "https://mint.cashu.space"),
            CashuToken(id: "token2", amount: 5000, mint: "https://mint.bitcoin.space"),
            CashuToken(id: "token3", amount: 10000, mint: "https://mint.cashu.space")
        ]
        
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
        // This would integrate with the actual Cashu protocol
    }
    
    private func fetchBTCPrice() async {
        // In production, fetch from a price API
        // For now, use a realistic placeholder
        btcPrice = 98543.21
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

struct CashuToken: Identifiable {
    let id: String
    let amount: Int
    let mint: String
}