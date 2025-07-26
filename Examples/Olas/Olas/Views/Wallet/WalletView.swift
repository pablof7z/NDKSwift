import SwiftUI
import NDKSwift

struct OlasWalletView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var walletManager: OlasWalletManager
    @State private var showingReceive = false
    @State private var showingSend = false
    @State private var selectedTab = 0
    @State private var pulseAnimation = false
    
    init(nostrManager: NostrManager) {
        self._walletManager = StateObject(wrappedValue: OlasWalletManager(nostrManager: nostrManager))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background
                TimeBasedGradient()
                    .opacity(0.3)
                    .ignoresSafeArea()
                
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Balance Card
                        balanceCard
                            .padding(.top, OlasDesign.Spacing.md)
                        
                        // Quick Actions
                        quickActions
                        
                        // Tab Selection
                        tabSelector
                        
                        // Content based on selected tab
                        switch selectedTab {
                        case 0:
                            transactionsView
                        case 1:
                            mintsView
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Wallet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .automatic) {
                #endif
                    Button {
                        OlasDesign.Haptic.selection()
                        // TODO: Navigate to wallet settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(OlasDesign.Colors.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showingReceive) {
                ReceiveView(walletManager: walletManager)
            }
            .sheet(isPresented: $showingSend) {
                SendView(walletManager: walletManager)
            }
            .task {
                await loadWallet()
            }
        }
    
    // MARK: - Components
    
    private var balanceCard: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Lightning icon with pulse animation
            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FFA726"), Color(hex: "FFD54F")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                    value: pulseAnimation
                )
                .onAppear { pulseAnimation = true }
            
            // Balance
            VStack(spacing: OlasDesign.Spacing.xs) {
                Text("Balance")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatSats(walletManager.currentBalance))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(OlasDesign.Colors.text)
                        .contentTransition(.numericText())
                    
                    Text("sats")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
                
                // USD equivalent (mock)
                Text("≈ $\(String(format: "%.2f", Double(walletManager.currentBalance) * 0.0003))")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textTertiary)
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
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    private var quickActions: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Send button
            Button {
                OlasDesign.Haptic.selection()
                showingSend = true
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(-45))
                        )
                    
                    Text("Send")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Receive button
            Button {
                OlasDesign.Haptic.selection()
                showingReceive = true
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "4ECDC4"), Color(hex: "44A08D")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.title2)
                                .foregroundColor(.white)
                        )
                    
                    Text("Receive")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Scan button
            Button {
                OlasDesign.Haptic.selection()
                // TODO: Implement QR scanner
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "camera.viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)
                        )
                    
                    Text("Scan")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }
    
    private var tabSelector: some View {
        let tabs: [(Int, String)] = [(0, "Transactions"), (1, "Mints")]
        return HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { item in
                let index = item.0
                let title = item.1
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = index
                    }
                    OlasDesign.Haptic.selection()
                } label: {
                    VStack(spacing: OlasDesign.Spacing.xs) {
                        Text(title)
                            .font(OlasDesign.Typography.bodyMedium)
                            .foregroundStyle(selectedTab == index ? OlasDesign.Colors.text : OlasDesign.Colors.textSecondary)
                        
                        Rectangle()
                            .fill(selectedTab == index ? OlasDesign.accentGradient : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, OlasDesign.Spacing.md)
    }
    
    private var transactionsView: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            if walletManager.recentTransactions.isEmpty {
                // Empty state
                VStack(spacing: OlasDesign.Spacing.md) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                    
                    Text("No transactions yet")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                    
                    Text("Send or receive sats to see them here")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OlasDesign.Spacing.xxl)
            } else {
                ForEach(walletManager.recentTransactions, id: \.id) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
    
    private var mintsView: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            ForEach(walletManager.mintURLs, id: \.self) { mintURL in
                MintRow(mintURL: mintURL)
            }
            
            // Add mint button
            Button {
                OlasDesign.Haptic.selection()
                // TODO: Add mint functionality
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OlasDesign.accentGradient)
                    
                    Text("Add Mint")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(OlasDesign.Colors.text)
                    
                    Spacer()
                }
                .padding(OlasDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                )
            }
        }
    }
    
    // MARK: - Methods
    
    private func loadWallet() async {
        do {
            try await walletManager.loadWallet()
        } catch {
            print("Failed to load wallet: \(error)")
        }
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }
}

// MARK: - Supporting Views

struct TransactionRow: View {
    let transaction: (id: String, type: OlasWalletManager.TransactionType, amount: Int64, description: String, timestamp: Date)
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Icon
            Circle()
                .fill(iconBackground)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                )
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
                
                Text(RelativeTimeFormatter.format(transaction.timestamp))
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
            
            Spacer()
            
            // Amount
            HStack(spacing: 4) {
                Text(transaction.type == .received ? "+" : "-")
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(amountColor)
                
                Text(formatSats(transaction.amount))
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(amountColor)
                
                Text("sats")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var iconName: String {
        switch transaction.type {
        case .sent:
            return "paperplane.fill"
        case .received:
            return "arrow.down.circle.fill"
        case .zapped:
            return "bolt.fill"
        }
    }
    
    private var iconBackground: LinearGradient {
        switch transaction.type {
        case .sent:
            return LinearGradient(
                colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .received:
            return LinearGradient(
                colors: [Color(hex: "4ECDC4"), Color(hex: "44A08D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .zapped:
            return LinearGradient(
                colors: [Color(hex: "FFA726"), Color(hex: "FFD54F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .received:
            return OlasDesign.Colors.success
        case .sent, .zapped:
            return OlasDesign.Colors.text
        }
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }
}

struct MintRow: View {
    let mintURL: String
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Mint icon
            Circle()
                .fill(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Text("₿")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                )
            
            // Mint details
            VStack(alignment: .leading, spacing: 4) {
                Text(mintURL.replacingOccurrences(of: "https://", with: ""))
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Connected")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Balance at this mint (mock)
            VStack(alignment: .trailing, spacing: 4) {
                Text("100,000")
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(OlasDesign.Colors.text)
                
                Text("sats")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
    }
}

// MARK: - Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}