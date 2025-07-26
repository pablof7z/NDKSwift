import SwiftUI

struct TransactionDetailView: View {
    let transaction: OlasWalletManager.WalletTransaction
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var copiedToClipboard = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Transaction Icon
                        transactionIcon
                            .padding(.top, OlasDesign.Spacing.xl)
                        
                        // Amount
                        amountSection
                        
                        // Status
                        statusSection
                        
                        // Details
                        detailsSection
                        
                        // Actions
                        if transaction.invoice != nil || transaction.status == .pending {
                            actionsSection
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                }
            }
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let invoice = transaction.invoice {
                    ShareSheet(items: [invoice])
                }
            }
        }
    }
    
    private var transactionIcon: some View {
        ZStack {
            // Animated background circles
            ForEach(0..<3) { index in
                Circle()
                    .fill(iconBackground.opacity(0.1))
                    .frame(width: CGFloat(100 + index * 30), height: CGFloat(100 + index * 30))
                    .scaleEffect(transaction.status == .pending ? 1.1 : 1.0)
                    .animation(
                        transaction.status == .pending ?
                        .easeInOut(duration: 2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.3) :
                        .default,
                        value: transaction.status
                    )
            }
            
            // Main icon
            Circle()
                .fill(iconBackground)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                )
                .shadow(color: iconBackground.opacity(0.5), radius: 20)
        }
    }
    
    private var amountSection: some View {
        VStack(spacing: OlasDesign.Spacing.sm) {
            // Amount
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(transaction.type == .received || transaction.type == .minted ? "+" : "-")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(amountColor)
                
                Text(formatSats(transaction.amount))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(amountColor)
                
                Text("sats")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
            
            // USD equivalent
            Text("≈ $\(String(format: "%.2f", Double(transaction.amount) * 0.0003))")
                .font(OlasDesign.Typography.body)
                .foregroundStyle(OlasDesign.Colors.textTertiary)
            
            // Fee if applicable
            if let fee = transaction.fee, fee > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                    Text("\(fee) sats fee")
                }
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.textTertiary)
            }
        }
    }
    
    private var statusSection: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            // Status badge
            HStack(spacing: 6) {
                if transaction.status == .pending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: statusIcon)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                
                Text(statusText)
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.1))
            )
            
            // Timestamp
            Text(transaction.timestamp.formatted())
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.textSecondary)
        }
    }
    
    private var detailsSection: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Description
            DetailRow(
                icon: "text.alignleft",
                label: "Description",
                value: transaction.description
            )
            
            // Type
            DetailRow(
                icon: "arrow.triangle.2.circlepath",
                label: "Type",
                value: typeText
            )
            
            // Mint if available
            if let mint = transaction.mint {
                DetailRow(
                    icon: "building.2",
                    label: "Mint",
                    value: mint.replacingOccurrences(of: "https://", with: "")
                )
            }
            
            // Transaction ID
            DetailRow(
                icon: "number",
                label: "Transaction ID",
                value: transaction.id.uuidString.lowercased()
            ) {
                copyToClipboard(transaction.id.uuidString.lowercased())
            }
            
            // Invoice if available
            if let invoice = transaction.invoice {
                DetailRow(
                    icon: "doc.text",
                    label: "Invoice",
                    value: String(invoice.prefix(20)) + "..."
                ) {
                    copyToClipboard(invoice)
                }
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var actionsSection: some View {
        VStack(spacing: OlasDesign.Spacing.sm) {
            if let invoice = transaction.invoice {
                // Share invoice
                Button {
                    showingShareSheet = true
                    OlasDesign.Haptic.selection()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Invoice")
                    }
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(OlasDesign.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
                }
            }
            
            if transaction.status == .pending {
                // Cancel transaction (if applicable)
                Button {
                    // TODO: Implement cancel
                    OlasDesign.Haptic.warning()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Cancel Transaction")
                    }
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(OlasDesign.Colors.error)
                    .frame(maxWidth: .infinity)
                    .padding(OlasDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                            .stroke(OlasDesign.Colors.error, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
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
    
    private var statusIcon: String {
        switch transaction.status {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .pending:
            return "clock.fill"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .completed:
            return OlasDesign.Colors.success
        case .failed:
            return OlasDesign.Colors.error
        case .pending:
            return OlasDesign.Colors.warning
        }
    }
    
    private var statusText: String {
        switch transaction.status {
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .pending:
            return "Pending"
        }
    }
    
    private var typeText: String {
        switch transaction.type {
        case .sent:
            return "Sent Payment"
        case .received:
            return "Received Payment"
        case .zapped:
            return "Zap"
        case .minted:
            return "Minted Tokens"
        case .melted:
            return "Melted Tokens"
        case .swapped:
            return "Token Swap"
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        OlasDesign.Haptic.success()
        
        withAnimation {
            copiedToClipboard = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }
}

// MARK: - Supporting Views

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(OlasDesign.Colors.textSecondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                Text(value)
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if action != nil {
                Button {
                    action?()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(OlasDesign.Colors.primary)
                }
            }
        }
        .padding(.vertical, OlasDesign.Spacing.xs)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}