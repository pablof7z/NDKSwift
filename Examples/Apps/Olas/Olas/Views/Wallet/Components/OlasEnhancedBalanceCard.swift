import SwiftUI
import Charts

struct OlasEnhancedBalanceCard: View {
    @ObservedObject var walletManager: OlasWalletManager
    @State private var isExpanded = false
    @State private var showingBreakdown = false
    @State private var selectedMint: String?
    @State private var rotationAngle: Double = 0
    @State private var pulseAnimation = false
    
    private var totalBalance: Int64 {
        walletManager.currentBalance
    }
    
    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: totalBalance)) ?? "0"
    }
    
    private var mintData: [(mint: String, balance: Int64, percentage: Double)] {
        let total = Double(totalBalance)
        return walletManager.mintBalances.map { mint, balance in
            let percentage = total > 0 ? (Double(balance) / total) * 100 : 0
            return (mint: mint, balance: balance, percentage: percentage)
        }.sorted { $0.balance > $1.balance }
    }
    
    private var mintColors: [Color] {
        [
            Color(hex: "4ECDC4"),
            Color(hex: "F56565"),
            Color(hex: "805AD5"),
            Color(hex: "48BB78"),
            Color(hex: "ED8936"),
            Color(hex: "38B2AC")
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main balance card
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                    showingBreakdown.toggle()
                }
                OlasDesign.Haptic.selection()
            } label: {
                VStack(spacing: OlasDesign.Spacing.md) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Balance")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                            
                            HStack(spacing: 6) {
                                Text(formattedBalance)
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(OlasDesign.Colors.text)
                                    .contentTransition(.numericText())
                                
                                Text("sats")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(OlasDesign.Colors.textTertiary)
                                    .offset(y: 8)
                            }
                        }
                        
                        Spacer()
                        
                        // Visual balance indicator
                        ZStack {
                            // Background circle
                            Circle()
                                .stroke(OlasDesign.Colors.surface, lineWidth: 8)
                                .frame(width: 70, height: 70)
                            
                            // Progress circles for each mint
                            ForEach(Array(mintData.enumerated()), id: \.element.mint) { index, data in
                                Circle()
                                    .trim(
                                        from: startAngle(for: index),
                                        to: endAngle(for: index)
                                    )
                                    .stroke(
                                        mintColors[index % mintColors.count],
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                    )
                                    .frame(width: 70, height: 70)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.spring(), value: data.percentage)
                            }
                            
                            // Center icon
                            Image(systemName: "bitcoinsign.circle.fill")
                                .font(.system(size: 30))
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
                                .rotationEffect(.degrees(rotationAngle))
                                .animation(
                                    .linear(duration: 20)
                                    .repeatForever(autoreverses: false),
                                    value: rotationAngle
                                )
                        }
                    }
                    
                    // Expand indicator
                    HStack {
                        Text(isExpanded ? "Hide Details" : "Show Details")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(OlasDesign.Colors.primary)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(OlasDesign.Colors.primary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(OlasDesign.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            OlasDesign.Colors.primary.opacity(0.05),
                                            OlasDesign.Colors.primary.opacity(0.02)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(
                    color: OlasDesign.Colors.primary.opacity(0.1),
                    radius: isExpanded ? 20 : 10,
                    x: 0,
                    y: isExpanded ? 10 : 5
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded breakdown
            if showingBreakdown {
                VStack(spacing: OlasDesign.Spacing.sm) {
                    ForEach(Array(mintData.enumerated()), id: \.element.mint) { index, data in
                        MintBreakdownRow(
                            mint: data.mint,
                            balance: data.balance,
                            percentage: data.percentage,
                            color: mintColors[index % mintColors.count],
                            isSelected: selectedMint == data.mint
                        )
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedMint = selectedMint == data.mint ? nil : data.mint
                            }
                            OlasDesign.Haptic.selection()
                        }
                    }
                    
                    if mintData.isEmpty {
                        Text("No mints configured")
                            .font(OlasDesign.Typography.body)
                            .foregroundStyle(OlasDesign.Colors.textTertiary)
                            .padding(.vertical, OlasDesign.Spacing.md)
                    }
                }
                .padding(OlasDesign.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                        .fill(OlasDesign.Colors.surface.opacity(0.5))
                )
                .padding(.top, -OlasDesign.Spacing.sm)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .top).combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            rotationAngle = 360
        }
    }
    
    private func startAngle(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        
        let previousPercentages = mintData.prefix(index).map { $0.percentage }.reduce(0, +)
        return previousPercentages / 100
    }
    
    private func endAngle(for index: Int) -> CGFloat {
        let currentAndPreviousPercentages = mintData.prefix(index + 1).map { $0.percentage }.reduce(0, +)
        return currentAndPreviousPercentages / 100
    }
}

struct MintBreakdownRow: View {
    let mint: String
    let balance: Int64
    let percentage: Double
    let color: Color
    let isSelected: Bool
    
    private var formattedMint: String {
        if let url = URL(string: mint),
           let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
                .replacingOccurrences(of: ".com", with: "")
                .replacingOccurrences(of: ".cash", with: "")
                .replacingOccurrences(of: ".space", with: "")
        }
        return mint
    }
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            // Color indicator
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: isSelected ? 4 : 0)
                        .animation(.spring(), value: isSelected)
                )
            
            // Mint name
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedMint)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
                
                Text("\(String(format: "%.1f", percentage))% of total")
                    .font(.system(size: 11))
                    .foregroundStyle(OlasDesign.Colors.textTertiary)
            }
            
            Spacer()
            
            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(balance)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(OlasDesign.Colors.text)
                    .contentTransition(.numericText())
                
                Text("sats")
                    .font(.system(size: 11))
                    .foregroundStyle(OlasDesign.Colors.textTertiary)
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.sm)
        .padding(.vertical, OlasDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                .fill(isSelected ? color.opacity(0.1) : Color.clear)
                .animation(.spring(), value: isSelected)
        )
    }
}