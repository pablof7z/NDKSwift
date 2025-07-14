import SwiftUI
import Foundation

struct MintAllocationPieChart: View {
    @EnvironmentObject private var walletManager: WalletManager
    @State private var mintBalances: [(mint: String, balance: Int64, percentage: Double)] = []
    @State private var selectedSlice: String?
    @State private var animationProgress: Double = 0
    @State private var isLoading = true
    
    private let chartSize: CGFloat = 240
    private let innerRadius: CGFloat = 60
    
    // Beautiful color palette for the pie chart
    private let mintColors: [Color] = [
        Color(red: 0.98, green: 0.54, blue: 0.13), // Orange
        Color(red: 0.13, green: 0.59, blue: 0.95), // Blue
        Color(red: 0.96, green: 0.26, blue: 0.21), // Red
        Color(red: 0.30, green: 0.69, blue: 0.31), // Green
        Color(red: 0.61, green: 0.15, blue: 0.69), // Purple
        Color(red: 1.00, green: 0.92, blue: 0.23), // Yellow
        Color(red: 0.00, green: 0.74, blue: 0.83), // Cyan
        Color(red: 1.00, green: 0.60, blue: 0.00)  // Deep Orange
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            titleView
            
            if mintBalances.isEmpty && !isLoading {
                emptyStateView
            } else {
                chartAndLegendView
            }
        }
        .padding(20)
        .background(backgroundView)
        .onAppear {
            Task {
                await loadMintBalances()
                withAnimation(.easeOut(duration: 0.8)) {
                    animationProgress = 1.0
                }
            }
        }
    }
    
    private var titleView: some View {
        HStack {
            Text("Mint Allocation")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No funds distributed yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: chartSize)
    }
    
    private var chartAndLegendView: some View {
        HStack(spacing: 30) {
            chartView
            legendView
        }
    }
    
    private var chartView: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: chartSize, height: chartSize)
            
            // Pie slices
            ForEach(Array(mintBalances.enumerated()), id: \.element.mint) { index, item in
                PieSlice(
                    startAngle: startAngle(for: index),
                    endAngle: endAngle(for: index),
                    innerRadius: innerRadius,
                    outerRadius: chartSize / 2,
                    color: mintColors[index % mintColors.count],
                    isSelected: selectedSlice == item.mint,
                    animationProgress: animationProgress
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedSlice = selectedSlice == item.mint ? nil : item.mint
                    }
                }
            }
            
            // Center hole with total
            centerTotalView
        }
        .frame(width: chartSize, height: chartSize)
    }
    
    private var centerTotalView: some View {
        VStack(spacing: 4) {
            Text("Total")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(formatSats(mintBalances.reduce(0) { $0 + $1.balance }))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("sats")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var legendView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(mintBalances.enumerated()), id: \.element.mint) { index, item in
                legendItem(for: item, at: index)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func legendItem(for item: (mint: String, balance: Int64, percentage: Double), at index: Int) -> some View {
        HStack(spacing: 8) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(mintColors[index % mintColors.count])
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selectedSlice == item.mint ? Color.white : Color.clear, lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(formatMintName(item.mint))
                    .font(.caption)
                    .fontWeight(selectedSlice == item.mint ? .semibold : .regular)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text("\(formatSats(item.balance)) sats")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("(\(Int(item.percentage))%)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            
            Spacer()
        }
        .opacity(selectedSlice == nil || selectedSlice == item.mint ? 1.0 : 0.5)
        .scaleEffect(selectedSlice == item.mint ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: selectedSlice)
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
    
    private func loadMintBalances() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let wallet = walletManager.activeWallet else { return }
        
        let mints = await wallet.getMints()
        var balances: [(mint: String, balance: Int64, percentage: Double)] = []
        var totalBalance: Int64 = 0
        
        // Get balance for each mint
        for mint in mints {
            let balance = await wallet.getBalance(mint: mint.url)
            if balance > 0 {
                balances.append((mint: mint.url.absoluteString, balance: balance, percentage: 0))
                totalBalance += balance
            }
        }
        
        // Calculate percentages
        if totalBalance > 0 {
            balances = balances.map { item in
                let percentage = (Double(item.balance) / Double(totalBalance)) * 100
                return (mint: item.mint, balance: item.balance, percentage: percentage)
            }
        }
        
        // Sort by balance (largest first)
        balances.sort { $0.balance > $1.balance }
        
        await MainActor.run {
            self.mintBalances = balances
        }
    }
    
    private func startAngle(for index: Int) -> Angle {
        guard index > 0 else { return .degrees(-90) }
        
        let previousAngles = mintBalances[0..<index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0 * 360.0)
        }
        
        return .degrees(previousAngles - 90)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let cumulativeAngle = mintBalances[0...index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0 * 360.0)
        }
        
        return .degrees(cumulativeAngle - 90)
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? String(sats)
    }
    
    private func formatMintName(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        
        // Remove common prefixes
        let cleanHost = host
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "mint.", with: "")
        
        // Truncate if too long
        if cleanHost.count > 20 {
            return String(cleanHost.prefix(17)) + "..."
        }
        
        return cleanHost
    }
}

// Custom pie slice shape
struct PieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let color: Color
    let isSelected: Bool
    let animationProgress: Double
    
    var body: some View {
        ZStack {
            // Shadow for selected slice
            if isSelected {
                PieSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius + 5
                )
                .fill(color.opacity(0.3))
                .blur(radius: 8)
            }
            
            // Main slice
            PieSliceShape(
                startAngle: startAngle,
                endAngle: startAngle + (endAngle - startAngle) * animationProgress,
                innerRadius: innerRadius,
                outerRadius: isSelected ? outerRadius + 5 : outerRadius
            )
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color,
                        color.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Highlight edge
            PieSliceShape(
                startAngle: startAngle,
                endAngle: startAngle + (endAngle - startAngle) * animationProgress,
                innerRadius: innerRadius,
                outerRadius: isSelected ? outerRadius + 5 : outerRadius
            )
            .stroke(color.opacity(0.8), lineWidth: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct PieSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // Outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        
        // Line to inner arc
        let innerEndPoint = CGPoint(
            x: center.x + innerRadius * Foundation.cos(endAngle.radians),
            y: center.y + innerRadius * Foundation.sin(endAngle.radians)
        )
        path.addLine(to: innerEndPoint)
        
        // Inner arc (reversed)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        
        // Close the path
        path.closeSubpath()
        
        return path
    }
}