import SwiftUI

struct OlasBalanceCard: View {
    @ObservedObject var walletManager: OlasWalletManager
    @State private var isExpanded = false
    @State private var pulseAnimation = false
    @State private var balanceAnimation = false
    
    private let mintColors: [Color] = [
        Color(red: 0.98, green: 0.54, blue: 0.13), // Orange
        Color(red: 0.13, green: 0.59, blue: 0.95), // Blue  
        Color(red: 0.96, green: 0.26, blue: 0.21), // Red
        Color(red: 0.30, green: 0.69, blue: 0.31), // Green
        Color(red: 0.61, green: 0.35, blue: 0.71), // Purple
        Color(red: 0.95, green: 0.77, blue: 0.06), // Yellow
    ]
    
    private var mintDistribution: [(mint: String, balance: Int64, percentage: Double)] {
        let total = Double(walletManager.currentBalance)
        guard total > 0 else { return [] }
        
        return walletManager.mintBalances.compactMap { (mintURL, balance) in
            guard balance > 0 else { return nil }
            let percentage = (Double(balance) / total) * 100
            let mintName = mintURL.replacingOccurrences(of: "https://", with: "")
            return (mint: mintName, balance: balance, percentage: percentage)
        }.sorted { $0.balance > $1.balance }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main balance section
            VStack(spacing: OlasDesign.Spacing.md) {
                // Lightning bolt with gradient
                ZStack {
                    // Glow effect
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 20)
                        .opacity(0.5)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                        .animation(
                            Animation.easeInOut(duration: 3)
                                .repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                    
                    // Main icon
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .scaleEffect(balanceAnimation ? 1 : 0.8)
                .opacity(balanceAnimation ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: balanceAnimation)
                
                // Balance amount
                VStack(spacing: OlasDesign.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(walletManager.currentBalance))
                            .font(.system(size: isExpanded ? 42 : 48, weight: .bold, design: .rounded))
                            .foregroundColor(OlasDesign.Colors.text)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: walletManager.currentBalance)
                        
                        Text("sats")
                            .font(.system(size: isExpanded ? 18 : 20, weight: .medium, design: .rounded))
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                    }
                    
                    // USD equivalent - TODO: Add BTC price fetch
                    /*
                    if let usdPrice = walletManager.btcPrice {
                        let usdValue = Double(walletManager.currentBalance) * usdPrice / 100_000_000
                        Text("≈ $\(String(format: "%.2f", usdValue)) USD")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut, value: usdValue)
                    }
                    */
                    
                    // Mint distribution indicator
                    if !mintDistribution.isEmpty && !isExpanded {
                        HStack(spacing: OlasDesign.Spacing.sm) {
                            ForEach(0..<min(mintDistribution.count, 4), id: \.self) { index in
                                Circle()
                                    .fill(mintColors[index % mintColors.count])
                                    .frame(width: 8, height: 8)
                            }
                            
                            if mintDistribution.count > 4 {
                                Text("+\(mintDistribution.count - 4)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(OlasDesign.Colors.textTertiary)
                            }
                            
                            Spacer()
                                .frame(width: OlasDesign.Spacing.xs)
                            
                            Text("\(mintDistribution.count) mint\(mintDistribution.count == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        }
                        .padding(.top, OlasDesign.Spacing.xs)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OlasDesign.Spacing.xl)
            .padding(.horizontal, OlasDesign.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? OlasDesign.CornerRadius.xl : OlasDesign.CornerRadius.lg)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: isExpanded ? OlasDesign.CornerRadius.xl : OlasDesign.CornerRadius.lg)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(0.3),
                                        Color.yellow.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                    OlasDesign.Haptic.selection()
                }
            }
            
            // Expanded mint distribution
            if isExpanded && !mintDistribution.isEmpty {
                VStack(spacing: OlasDesign.Spacing.md) {
                    // Pie chart
                    ZStack {
                        ForEach(Array(mintDistribution.enumerated()), id: \.offset) { index, item in
                            PieSlice(
                                startAngle: startAngle(for: index),
                                endAngle: endAngle(for: index),
                                color: mintColors[index % mintColors.count]
                            )
                        }
                    }
                    .frame(width: 160, height: 160)
                    .padding(.top, OlasDesign.Spacing.lg)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                        ForEach(Array(mintDistribution.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: OlasDesign.Spacing.sm) {
                                Circle()
                                    .fill(mintColors[index % mintColors.count])
                                    .frame(width: 12, height: 12)
                                
                                Text(item.mint)
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundColor(OlasDesign.Colors.text)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.balance) sats")
                                        .font(OlasDesign.Typography.caption)
                                        .foregroundColor(OlasDesign.Colors.text)
                                    
                                    Text("\(String(format: "%.1f", item.percentage))%")
                                        .font(.system(size: 10))
                                        .foregroundColor(OlasDesign.Colors.textTertiary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                }
                .padding(.bottom, OlasDesign.Spacing.lg)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isExpanded)
        .onAppear {
            pulseAnimation = true
            withAnimation(.easeOut(duration: 0.6)) {
                balanceAnimation = true
            }
        }
    }
    
    private func formatBalance(_ balance: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
    
    private func startAngle(for index: Int) -> Angle {
        let total = Double(walletManager.currentBalance)
        guard total > 0 else { return .zero }
        
        var angle: Double = -90 // Start from top
        for i in 0..<index {
            angle += (Double(mintDistribution[i].balance) / total) * 360
        }
        return .degrees(angle)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let total = Double(walletManager.currentBalance)
        guard total > 0 else { return .zero }
        
        var angle: Double = -90 // Start from top
        for i in 0...index {
            angle += (Double(mintDistribution[i].balance) / total) * 360
        }
        return .degrees(angle)
    }
}

// MARK: - Pie Slice Shape
struct PieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = min(geometry.size.width, geometry.size.height) / 2
                
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(color)
            .overlay(
                Path { path in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let radius = min(geometry.size.width, geometry.size.height) / 2
                    
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false
                    )
                    path.closeSubpath()
                }
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}