import SwiftUI

// MARK: - Pulsing Icon
struct PulsingIcon: View {
    let systemName: String
    let size: CGFloat
    let colors: [Color]
    @State private var pulseAnimation = false
    @State private var rotationAnimation = false
    
    var body: some View {
        ZStack {
            // Glow effect
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 20)
                .opacity(0.5)
                .scaleEffect(pulseAnimation ? 1.2 : 0.8)
            
            // Main icon
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: colors.first?.opacity(0.3) ?? Color.clear, radius: 10, x: 0, y: 5)
                .rotationEffect(.degrees(rotationAnimation ? 5 : -5))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulseAnimation.toggle()
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                rotationAnimation.toggle()
            }
        }
    }
}

// MARK: - Mint Distribution Preview
struct MintDistributionPreview: View {
    @ObservedObject var walletManager: OlasWalletManager
    
    private let mintColors: [Color] = [
        Color(hex: "FF6B6B"),
        Color(hex: "4ECDC4"),
        Color(hex: "45B7D1"),
        Color(hex: "F9CA24"),
        Color(hex: "6C5CE7")
    ]
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            ForEach(Array(walletManager.mintURLs.prefix(4).enumerated()), id: \.offset) { index, mintURL in
                Circle()
                    .fill(mintColors[index % mintColors.count])
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            
            if walletManager.mintURLs.count > 4 {
                Text("+\(walletManager.mintURLs.count - 4)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OlasDesign.Colors.textTertiary)
            }
            
            Spacer()
                .frame(width: OlasDesign.Spacing.xs)
            
            Text("\(walletManager.mintURLs.count) mints active")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
        .padding(.vertical, OlasDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Share Sheet
#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet: View {
    let items: [Any]
    
    var body: some View {
        VStack {
            Text("Share")
                .font(.headline)
            
            if let text = items.first as? String {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Button("Copy to Clipboard") {
                if let text = items.first as? String {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    #endif
                }
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}
#endif


// MARK: - Modern Transaction Row
struct ModernTransactionRow: View {
    let transaction: OlasWalletManager.WalletTransaction
    @ObservedObject var walletManager: OlasWalletManager
    @State private var showDetail = false
    @State private var animateIn = false
    
    private var transactionIcon: String {
        switch transaction.type {
        case .sent: return "arrow.up.circle.fill"
        case .received: return "arrow.down.circle.fill"
        case .zapped: return "bolt.circle.fill"
        case .minted: return "plus.circle.fill"
        case .melted: return "minus.circle.fill"
        case .swapped: return "arrow.2.circlepath.circle.fill"
        }
    }
    
    private var transactionColor: Color {
        switch transaction.type {
        case .sent, .melted: return Color(hex: "F56565")
        case .received, .minted: return Color(hex: "48BB78")
        case .zapped: return Color(hex: "805AD5")
        case .swapped: return Color(hex: "4299E1")
        }
    }
    
    var body: some View {
        Button {
            showDetail = true
            OlasDesign.Haptic.impact(.light)
        } label: {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Animated Icon
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
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: transactionIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(transactionColor)
                        .scaleEffect(animateIn ? 1 : 0)
                        .rotationEffect(.degrees(animateIn ? 0 : -90))
                }
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(formatRelativeTime(transaction.timestamp))
                            .font(.system(size: 12))
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                        
                        if let mint = transaction.mint {
                            Text("•")
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                            
                            Text(formatMintName(mint))
                                .font(.system(size: 12))
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        
                        if transaction.status == .pending {
                            Text("•")
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                            
                            HStack(spacing: 2) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                
                                Text("Pending")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.orange)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Amount with animation
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(transaction.type == .received || transaction.type == .minted ? "+" : "-")\(formatAmount(transaction.amount))")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(transactionColor)
                        .opacity(animateIn ? 1 : 0)
                        .offset(x: animateIn ? 0 : 20)
                    
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
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