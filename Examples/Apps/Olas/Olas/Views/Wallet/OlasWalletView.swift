import SwiftUI
import NDKSwift

struct OlasWalletView: View {
    @ObservedObject var walletManager: OlasWalletManager
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
                // Enhanced gradient background with animated mesh
                TimeBasedGradient()
                    .ignoresSafeArea()
                    .opacity(0.3)
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.lg) {
                        // Enhanced Balance Card with glassmorphism
                        GlassmorphicCard {
                            VStack(spacing: OlasDesign.Spacing.lg) {
                                // Lightning icon with pulse
                                PulsingIcon(
                                    systemName: "bolt.circle.fill",
                                    size: 80,
                                    colors: [Color.orange, Color.yellow]
                                )
                                
                                // Animated balance display
                                AnimatedBalanceDisplay(
                                    balance: walletManager.currentBalance,
                                    btcPrice: nil
                                )
                                
                                // Mint distribution preview
                                if walletManager.mintURLs.count > 1 {
                                    MintDistributionPreview(walletManager: walletManager)
                                        .padding(.top, OlasDesign.Spacing.sm)
                                }
                            }
                            .padding(.vertical, OlasDesign.Spacing.xl)
                            .padding(.horizontal, OlasDesign.Spacing.lg)
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.top, OlasDesign.Spacing.sm)
                        
                        // Quick Stats with glassmorphism
                        quickStats
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Modern Action Buttons
                        modernActionButtons
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Recent Activity with enhanced UI
                        recentActivity
                    }
                    .padding(.bottom, 100)
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
                SendView(walletManager: walletManager)
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
                do {
                    try await walletManager.loadWallet()
                } catch {
                    print("Failed to load wallet: \(error)")
                }
            }
        }
    }
    
    private var quickStats: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            // Total Mints
            GlassmorphicCard {
                StatCard(
                    icon: "server.rack",
                    value: "\(walletManager.mintURLs.count)",
                    label: "Mints",
                    color: .blue
                )
            }
            
            // Active Tokens
            GlassmorphicCard {
                StatCard(
                    icon: "ticket.fill",
                    value: "\(walletManager.activeTokens.count)",
                    label: "Tokens",
                    color: .green
                )
            }
            
            // Today's Activity
            GlassmorphicCard {
                StatCard(
                    icon: "arrow.up.arrow.down",
                    value: "\(walletManager.recentTransactions.filter { Calendar.current.isDateInToday($0.timestamp) }.count)",
                    label: "Today",
                    color: .orange
                )
            }
        }
    }
    
    private var todaysTransactionCount: Int {
        return 0 // Handled inline now
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
                
                NavigationLink(destination: Text("Transaction History")) {
                    Text("See All")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.primary)
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            
            if walletManager.recentTransactions.isEmpty {
                EmptyActivityView()
                    .padding(.horizontal, OlasDesign.Spacing.md)
            } else {
                // Show last 5 transactions
                VStack(spacing: 0) {
                    ForEach(walletManager.recentTransactions.prefix(5)) { transaction in
                        TransactionRow(transaction: transaction, walletManager: walletManager)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        if transaction.id != walletManager.recentTransactions.prefix(5).last?.id {
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
        do {
            try await walletManager.loadWallet()
            OlasDesign.Haptic.selection()
        } catch {
            print("Failed to refresh wallet: \(error)")
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
                do {
                    try await walletManager.receiveEcash(code)
                } catch {
                    print("Failed to redeem token: \(error)")
                }
            }
        } else if code.lowercased().starts(with: "https://") {
            // Might be a mint URL
            showAddMint = true
        }
    }
}

// MARK: - Mint Row
struct MintRow: View {
    let mintURL: String
    let balance: Int64
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mintURL.replacingOccurrences(of: "https://", with: ""))
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(OlasDesign.Colors.text)
                    .lineLimit(1)
                
                Text("Active mint")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(balance) sats")
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
    let transaction: OlasWalletManager.WalletTransaction
    let walletManager: OlasWalletManager
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
            TransactionDetailView(transaction: transaction, walletManager: walletManager)
        }
    }
    
    private var modernActionButtons: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            FloatingActionButton(
                icon: "arrow.down.circle.fill",
                title: "Receive",
                gradient: [Color(hex: "4ECDC4"), Color(hex: "44A08D")],
                action: { showReceive = true }
            )
            
            FloatingActionButton(
                icon: "arrow.up.circle.fill",
                title: "Send",
                gradient: [Color(hex: "F56565"), Color(hex: "D53F8C")],
                action: { showSend = true }
            )
            
            FloatingActionButton(
                icon: "qrcode.viewfinder",
                title: "Scan",
                gradient: [Color(hex: "805AD5"), Color(hex: "6B46C1")],
                action: { showScanner = true }
            )
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

// MARK: - Supporting Types
struct CashuToken: Identifiable {
    let id: String
    let amount: Int
    let mint: String
}

enum TransactionType {
    case sent
    case received
}