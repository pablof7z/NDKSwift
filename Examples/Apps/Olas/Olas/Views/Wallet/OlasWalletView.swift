import SwiftUI
import NDKSwift

struct OlasWalletView: View {
    @ObservedObject var walletManager: OlasWalletManager
    let nostrManager: NostrManager
    @State private var selectedTab = 0
    @State private var showReceive = false
    @State private var showSend = false
    @State private var showAddMint = false
    @State private var showScanner = false
    @State private var showMintManagement = false
    @State private var refreshRotation: Double = 0
    @State private var isRefreshing = false
    @State private var showNutZap = false
    @State private var nutZapRecipient: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                RadialGradient(
                    gradient: Gradient(colors: [
                        OlasDesign.Colors.background,
                        OlasDesign.Colors.surface.opacity(0.3)
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                if !walletManager.isWalletConfigured {
                    // Empty wallet state
                    emptyWalletView
                } else {
                    ScrollView {
                        VStack(spacing: OlasDesign.Spacing.lg) {
                            // Enhanced Balance Card with glassmorphism
                            OlasEnhancedBalanceCard(walletManager: walletManager)
                                .padding(.horizontal, OlasDesign.Spacing.md)
                                .padding(.top, OlasDesign.Spacing.sm)
                        
                        // Quick Stats with glassmorphism
                        quickStats
                            .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        // Contacts for quick sending
                        WalletContactsScrollView(
                            showNutZap: $showNutZap,
                            nutZapRecipient: $nutZapRecipient
                        )
                        .padding(.top, OlasDesign.Spacing.sm)
                        
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
            }
            .navigationTitle("Lightning Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(OlasDesign.Colors.textSecondary)
                            .font(.title3)
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
                        
                        Button {
                            showNutZap = true
                        } label: {
                            Label("NutZap Someone", systemImage: "bolt.heart")
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
            .sheet(isPresented: $showNutZap) {
                NutZapView(walletManager: walletManager, nostrManager: nostrManager, recipientPubkey: nutZapRecipient)
            }
            .task {
                if walletManager.activeWallet == nil {
                    do {
                        try await walletManager.loadWallet()
                    } catch {
                        print("Failed to load wallet: \(error)")
                    }
                }
            }
        }
    }
    
    private var emptyWalletView: some View {
        VStack(spacing: OlasDesign.Spacing.xl) {
            Spacer()
            
            // Lightning bolt icon
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            OlasDesign.Colors.primary,
                            OlasDesign.Colors.primary.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: OlasDesign.Colors.primary.opacity(0.3), radius: 20, x: 0, y: 10)
            
            VStack(spacing: OlasDesign.Spacing.sm) {
                Text("Set Up Your Wallet")
                    .font(OlasDesign.Typography.title2)
                    .foregroundStyle(OlasDesign.Colors.text)
                
                Text("Add a mint to start using Lightning")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showAddMint = true
                OlasDesign.Haptic.selection()
            } label: {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Your First Mint")
                }
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundColor(.white)
                .padding(.horizontal, OlasDesign.Spacing.lg)
                .padding(.vertical, OlasDesign.Spacing.md)
                .background(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(OlasDesign.CornerRadius.full)
                .shadow(color: OlasDesign.Colors.primary.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
    }
    
    private var quickStats: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            // Total Mints
            ModernStatCard(
                icon: "server.rack",
                value: "\(walletManager.mintURLs.count)",
                label: "Mints",
                gradient: [Color(hex: "3B82F6"), Color(hex: "1E40AF")]
            )
            
            // Active Balance
            ModernStatCard(
                icon: "bitcoinsign.circle.fill",
                value: formatCompactBalance(walletManager.currentBalance),
                label: "Balance",
                gradient: [Color(hex: "F97316"), Color(hex: "EA580C")]
            )
            
            // Today's Activity
            ModernStatCard(
                icon: "arrow.up.arrow.down",
                value: "\(walletManager.recentTransactions.filter { Calendar.current.isDateInToday($0.timestamp) }.count)",
                label: "Today",
                gradient: [Color(hex: "10B981"), Color(hex: "059669")]
            )
        }
    }
    
    private func formatCompactBalance(_ sats: Int64) -> String {
        if sats >= 1_000_000 {
            return String(format: "%.1fM", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1fk", Double(sats) / 1_000)
        } else {
            return "\(sats)"
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
                HStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OlasDesign.Colors.primary)
                    
                    Text("Recent Activity")
                        .font(OlasDesign.Typography.title3)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
                
                Spacer()
                
                if !walletManager.recentTransactions.isEmpty {
                    NavigationLink(destination: Text("Transaction History")) {
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(OlasDesign.Typography.caption)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(OlasDesign.Colors.primary)
                    }
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            
            if walletManager.recentTransactions.isEmpty {
                EmptyActivityView()
                    .padding(.horizontal, OlasDesign.Spacing.md)
            } else {
                // Show last 5 transactions with modern design
                VStack(spacing: OlasDesign.Spacing.xs) {
                    ForEach(walletManager.recentTransactions.prefix(5)) { transaction in
                        ModernTransactionRow(transaction: transaction, walletManager: walletManager)
                            .transition(.asymmetric(
                                insertion: .push(from: .bottom).combined(with: .opacity),
                                removal: .push(from: .top).combined(with: .opacity)
                            ))
                    }
                }
                .padding(OlasDesign.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .fill(OlasDesign.Colors.surface.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.1),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
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
        case .sent, .melted: return "arrow.up.circle.fill"
        case .received, .minted: return "arrow.down.circle.fill"
        case .zapped, .nutzapped: return "bolt.heart.fill"
        case .swapped: return "arrow.triangle.swap"
        }
    }
    
    private var transactionColor: Color {
        switch transaction.type {
        case .sent, .melted: return Color.orange
        case .received, .minted: return Color.green
        case .zapped, .nutzapped: return Color.purple
        case .swapped: return Color.blue
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
                    let isIncoming = transaction.direction == .incoming || 
                        transaction.type == .received || 
                        transaction.type == .minted
                    Text("\(isIncoming ? "+" : "-")\(formatAmount(transaction.amount))")
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
    
    private func formatAmount(_ amount: Int64) -> String {
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