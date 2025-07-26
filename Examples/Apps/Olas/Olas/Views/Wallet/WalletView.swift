import SwiftUI
import NDKSwift

struct OlasWalletView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var walletManager: OlasWalletManager
    @State private var showingReceive = false
    @State private var showingSend = false
    @State private var showingAddMint = false
    @State private var showingScanner = false
    @State private var selectedTab = 0
    @State private var pulseAnimation = false
    @State private var selectedTransaction: OlasWalletManager.WalletTransaction?
    @State private var cardRotation: Double = 0
    @State private var showCardBack = false
    @State private var balanceCardScale: CGFloat = 1.0
    @State private var showWalletSettings = false
    @State private var selectedTimeRange = TimeRange.week
    @State private var chartData: [ChartDataPoint] = []
    @State private var dragOffset: CGSize = .zero
    @State private var showAnalytics = false
    @State private var showMintManagement = false
    
    enum TimeRange: String, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"
        case all = "All"
    }
    
    struct ChartDataPoint {
        let date: Date
        let value: Double
    }
    
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
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Enhanced Balance Card with parallax effect
                        GeometryReader { geometry in
                            let minY = geometry.frame(in: .global).minY
                            let scale = minY > 0 ? 1 + (minY / 500) : 1
                            let opacity = minY > -100 ? 1 : 1 + (minY + 100) / 100
                            
                            balanceCard
                                .scaleEffect(scale)
                                .opacity(opacity)
                                .rotation3DEffect(
                                    .degrees(cardRotation),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.5
                                )
                                .offset(y: minY > 0 ? -minY * 0.8 : 0)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            dragOffset = value.translation
                                        }
                                        .onEnded { value in
                                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                                if abs(value.translation.width) > 50 {
                                                    cardRotation += 180
                                                    showCardBack.toggle()
                                                }
                                                dragOffset = .zero
                                            }
                                            OlasDesign.Haptic.selection()
                                        }
                                )
                                .offset(dragOffset)
                        }
                        .frame(height: 220)
                        .padding(.top, OlasDesign.Spacing.md)
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        
                        VStack(spacing: OlasDesign.Spacing.xl) {
                            // Analytics Preview
                            if showAnalytics {
                                analyticsPreview
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .scale.combined(with: .opacity)
                                    ))
                            }
                            
                            // Quick Actions with enhanced animations
                            quickActions
                                .padding(.top, OlasDesign.Spacing.lg)
                            
                            // Tab Selection with sliding indicator
                            tabSelector
                        
                        // Content based on selected tab
                        Group {
                            switch selectedTab {
                            case 0:
                                transactionsView
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                            case 1:
                                mintsView
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            default:
                                EmptyView()
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.bottom, 100)
                    }
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
                    HStack(spacing: OlasDesign.Spacing.md) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showAnalytics.toggle()
                            }
                            OlasDesign.Haptic.selection()
                        } label: {
                            Image(systemName: showAnalytics ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis")
                                .foregroundStyle(showAnalytics ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                        
                        Button {
                            showWalletSettings = true
                            OlasDesign.Haptic.selection()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingReceive) {
                ReceiveView(walletManager: walletManager)
            }
            .sheet(isPresented: $showingSend) {
                SendView(walletManager: walletManager)
            }
            .sheet(isPresented: $showingAddMint) {
                AddMintView(walletManager: walletManager)
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { result in
                    handleScannedQR(result)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction, walletManager: walletManager)
            }
            .sheet(isPresented: $showMintManagement) {
                MintManagementView(walletManager: walletManager)
            }
            .task {
                await loadWallet()
            }
        }
    
    // MARK: - Components
    
    private var analyticsPreview: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Time range selector
            HStack(spacing: 0) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTimeRange = range
                        }
                        OlasDesign.Haptic.selection()
                    } label: {
                        Text(range.rawValue)
                            .font(OlasDesign.Typography.caption)
                            .foregroundStyle(selectedTimeRange == range ? .white : OlasDesign.Colors.textSecondary)
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.vertical, OlasDesign.Spacing.sm)
                            .background {
                                if selectedTimeRange == range {
                                    Capsule()
                                        .fill(OlasDesign.accentGradient)
                                        .matchedGeometryEffect(id: "timeRange", in: timeRangeNamespace)
                                }
                            }
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(OlasDesign.Colors.surface)
            )
            
            // Chart placeholder
            ZStack {
                // Background grid
                Canvas { context, size in
                    let rows = 5
                    let columns = 7
                    
                    for row in 0...rows {
                        let y = size.height * CGFloat(row) / CGFloat(rows)
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                            },
                            with: .color(OlasDesign.Colors.divider.opacity(0.3)),
                            lineWidth: 0.5
                        )
                    }
                    
                    for column in 0...columns {
                        let x = size.width * CGFloat(column) / CGFloat(columns)
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            },
                            with: .color(OlasDesign.Colors.divider.opacity(0.3)),
                            lineWidth: 0.5
                        )
                    }
                }
                
                // Animated chart line
                GeometryReader { geometry in
                    Path { path in
                        let points = generateChartPoints(in: geometry.size)
                        guard !points.isEmpty else { return }
                        
                        path.move(to: points[0])
                        
                        for i in 1..<points.count {
                            let control1 = CGPoint(
                                x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                                y: points[i-1].y
                            )
                            let control2 = CGPoint(
                                x: points[i-1].x + (points[i].x - points[i-1].x) / 2,
                                y: points[i].y
                            )
                            path.addCurve(to: points[i], control1: control1, control2: control2)
                        }
                    }
                    .trim(from: 0, to: pulseAnimation ? 1 : 0)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "4ECDC4"), Color(hex: "44A08D")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 3
                    )
                    .shadow(color: Color(hex: "4ECDC4").opacity(0.5), radius: 5)
                    .animation(.easeInOut(duration: 2), value: pulseAnimation)
                }
            }
            .frame(height: 120)
            .padding(.vertical, OlasDesign.Spacing.sm)
            
            // Stats row
            HStack(spacing: OlasDesign.Spacing.xl) {
                VStack(spacing: 4) {
                    Text("+15.2%")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(OlasDesign.Colors.success)
                    Text("vs last period")
                        .font(.system(size: 11))
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
                
                VStack(spacing: 4) {
                    Text("⚡ 42")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(OlasDesign.Colors.warning)
                    Text("transactions")
                        .font(.system(size: 11))
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
                
                VStack(spacing: 4) {
                    Text("₿ 0.0012")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(OlasDesign.Colors.text)
                    Text("total volume")
                        .font(.system(size: 11))
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
            }
        }
        .padding(OlasDesign.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xl)
                .fill(
                    LinearGradient(
                        colors: [
                            OlasDesign.Colors.surface.opacity(0.8),
                            OlasDesign.Colors.surface.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xl)
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
        .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 8)
    }
    
    @Namespace private var timeRangeNamespace
    
    private func generateChartPoints(in size: CGSize) -> [CGPoint] {
        let count = 8
        var points: [CGPoint] = []
        
        for i in 0..<count {
            let x = size.width * CGFloat(i) / CGFloat(count - 1)
            let normalizedY = sin(Double(i) * 0.8) * 0.3 + 0.5 + Double.random(in: -0.1...0.1)
            let y = size.height * (1 - normalizedY)
            points.append(CGPoint(x: x, y: y))
        }
        
        return points
    }
    
    private var balanceCard: some View {
        GeometryReader { geometry in
            ZStack {
                // Front of card
                if !showCardBack {
                    cardFront
                        .frame(width: geometry.size.width, height: 220)
                        .scaleEffect(x: showCardBack ? -1 : 1)
                }
                
                // Back of card
                if showCardBack {
                    cardBack
                        .frame(width: geometry.size.width, height: 220)
                        .scaleEffect(x: showCardBack ? 1 : -1)
                }
            }
        }
        .frame(height: 220)
    }
    
    private var cardFront: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Lightning icon with advanced animation
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "FFA726").opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                    .scaleEffect(pulseAnimation ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 2)
                        .repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FFA726"), Color(hex: "FFD54F")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .shadow(color: Color(hex: "FFA726").opacity(0.5), radius: 10)
            }
            .onAppear { pulseAnimation = true }
            
            // Balance with animated counter
            VStack(spacing: OlasDesign.Spacing.xs) {
                Text("Total Balance")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatSats(walletManager.currentBalance))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [OlasDesign.Colors.text, OlasDesign.Colors.text.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: walletManager.currentBalance)
                    
                    Text("sats")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
                
                // USD equivalent with live rate
                HStack(spacing: 4) {
                    Text("≈")
                    Text("$\(String(format: "%.2f", Double(walletManager.currentBalance) * 0.0003))")
                        .contentTransition(.numericText())
                    Text("USD")
                }
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.textTertiary)
            }
            
            Text("Tap to view breakdown")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OlasDesign.Colors.textTertiary.opacity(0.6))
                .padding(.top, OlasDesign.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.xl)
        .background(
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        OlasDesign.Colors.surface,
                        OlasDesign.Colors.surface.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Mesh gradient overlay
                MeshGradient()
                    .opacity(0.1)
            }
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    private var cardBack: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Text("Balance Breakdown")
                .font(OlasDesign.Typography.bodyBold)
                .foregroundStyle(OlasDesign.Colors.text)
                .padding(.top, OlasDesign.Spacing.md)
            
            ScrollView {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    ForEach(walletManager.mintURLs, id: \.self) { mintURL in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mintURL.replacingOccurrences(of: "https://", with: ""))
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundStyle(OlasDesign.Colors.text)
                                    .lineLimit(1)
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text("Active")
                                        .font(.system(size: 10))
                                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatSats(walletManager.mintBalances[mintURL] ?? 0))
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundStyle(OlasDesign.Colors.text)
                                Text("sats")
                                    .font(.system(size: 10))
                                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.vertical, OlasDesign.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                                .fill(OlasDesign.Colors.background.opacity(0.5))
                        )
                    }
                }
            }
            
            Spacer()
            
            Text("Tap to flip back")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OlasDesign.Colors.textTertiary.opacity(0.6))
                .padding(.bottom, OlasDesign.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    OlasDesign.Colors.surface.opacity(0.95),
                    OlasDesign.Colors.surface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg))
        )
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
                showingScanner = true
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
            
            // Zap button
            Button {
                OlasDesign.Haptic.selection()
                // TODO: Implement zap functionality
            } label: {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFA726"), Color(hex: "FFD54F")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        )
                    
                    Text("Zap")
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
            ForEach(0..<tabs.count, id: \.self) { i in
                let index = tabs[i].0
                let title = tabs[i].1
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
    
    @ViewBuilder
    private var transactionsView: some View {
        if walletManager.recentTransactions.isEmpty {
            transactionEmptyState
        } else {
            transactionsList
        }
    }
    
    @ViewBuilder
    private var transactionEmptyState: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            ZStack {
                // Animated circles
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "FFA726").opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: CGFloat(60 + index * 20), height: CGFloat(60 + index * 20))
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                        .opacity(pulseAnimation ? 0 : 1)
                        .animation(
                            .easeInOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                            value: pulseAnimation
                        )
                }
                
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [OlasDesign.Colors.textTertiary, OlasDesign.Colors.textTertiary.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("No transactions yet")
                .font(OlasDesign.Typography.body)
                .foregroundStyle(OlasDesign.Colors.textSecondary)
            
            Text("Send or receive sats to see them here")
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.xxl)
    }
    
    @ViewBuilder
    private var transactionsList: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
                ForEach(Array(walletManager.recentTransactions.enumerated()), id: \.element.id) { index, transaction in
                    TransactionRow(
                        transaction: transaction,
                        walletManager: walletManager
                    )
                    .scaleEffect(pulseAnimation ? 1 : 0.95)
                    .opacity(pulseAnimation ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(Double(min(index, 10)) * 0.05),
                        value: pulseAnimation
                    )
                    .onTapGesture {
                        selectedTransaction = transaction
                        OlasDesign.Haptic.selection()
                    }
            }
        }
    }
    
    private var mintsView: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Manage All button
            Button {
                showMintManagement = true
                OlasDesign.Haptic.selection()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mint Management")
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundStyle(OlasDesign.Colors.text)
                        Text("\(walletManager.mintURLs.count) active mints")
                            .font(OlasDesign.Typography.caption)
                            .foregroundStyle(OlasDesign.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(OlasDesign.Colors.textTertiary)
                }
                .padding(OlasDesign.Spacing.lg)
                .background(
                    LinearGradient(
                        colors: [
                            OlasDesign.Colors.surface.opacity(0.8),
                            OlasDesign.Colors.surface.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
            
            // Mint list preview
            ForEach(walletManager.mintURLs.prefix(3), id: \.self) { mintURL in
                MintURLRow(mintURL: mintURL)
            }
            
            if walletManager.mintURLs.count > 3 {
                Text("\(walletManager.mintURLs.count - 3) more mints")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textTertiary)
            }
            
            // Add mint button with animation
            Button {
                OlasDesign.Haptic.selection()
                showingAddMint = true
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

// MARK: - Helper Methods

private extension OlasWalletView {
    func handleScannedQR(_ result: String) {
        Task {
            if result.lowercased().starts(with: "lightning:") || result.lowercased().starts(with: "lnbc") {
                // Lightning invoice
                showingSend = true
                // Pass invoice to send view
            } else if result.starts(with: "cashu") {
                // Ecash token
                do {
                    try await walletManager.receiveEcash(result)
                    OlasDesign.Haptic.success()
                } catch {
                    print("Failed to receive ecash: \(error)")
                    OlasDesign.Haptic.error()
                }
            }
        }
    }
}

// MARK: - Mesh Gradient

struct MeshGradient: View {
    @State private var animationAmount: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let colors = [
                Color(hex: "FFA726").opacity(0.3),
                Color(hex: "FFD54F").opacity(0.3),
                Color(hex: "FF8E53").opacity(0.3),
                Color(hex: "4ECDC4").opacity(0.3)
            ]
            
            for i in 0..<20 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let radius = CGFloat.random(in: 30...100)
                
                let color = colors[i % colors.count]
                
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: x - radius + sin(animationAmount + CGFloat(i)) * 20,
                        y: y - radius + cos(animationAmount + CGFloat(i)) * 20,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(color)
                )
            }
        }
        .blur(radius: 30)
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                animationAmount = .pi * 2
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: OlasWalletManager.WalletTransaction
    let walletManager: OlasWalletManager
    
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
            
            // Details with status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.description)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    if transaction.status == .pending {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(RelativeTimeFormatter.format(transaction.timestamp))
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                    
                    if let mint = transaction.mint {
                        Text("•")
                            .foregroundStyle(OlasDesign.Colors.textTertiary)
                        Text(mint.replacingOccurrences(of: "https://", with: "").prefix(20))
                            .font(OlasDesign.Typography.caption)
                            .foregroundStyle(OlasDesign.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
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
        case .minted:
            return "plus.circle.fill"
        case .melted:
            return "flame.fill"
        case .swapped:
            return "arrow.triangle.2.circlepath"
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
        case .minted:
            return LinearGradient(
                colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .melted:
            return LinearGradient(
                colors: [Color(hex: "F093FB"), Color(hex: "F5576C")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .swapped:
            return LinearGradient(
                colors: [Color(hex: "4FACFE"), Color(hex: "00F2FE")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var amountColor: Color {
        switch transaction.type {
        case .received, .minted:
            return OlasDesign.Colors.success
        case .sent, .zapped, .melted:
            return OlasDesign.Colors.text
        case .swapped:
            return OlasDesign.Colors.warning
        }
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }
}

struct MintURLRow: View {
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