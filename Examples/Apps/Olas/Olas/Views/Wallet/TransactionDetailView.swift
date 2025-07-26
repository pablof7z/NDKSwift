import SwiftUI

struct TransactionDetailView: View {
    let transaction: OlasWalletManager.WalletTransaction
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var copiedToClipboard = false
    @State private var animateContent = false
    @State private var showingQRCode = false
    @State private var particleSystem = ParticleSystem()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Transaction Icon with particle effects
                        ZStack {
                            ParticleEffectView(particleSystem: particleSystem)
                                .allowsHitTesting(false)
                            
                            transactionIcon
                                .padding(.top, OlasDesign.Spacing.xl)
                                .scaleEffect(animateContent ? 1 : 0.8)
                                .opacity(animateContent ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: animateContent)
                        }
                        
                        // Amount with counter animation
                        amountSection
                            .offset(y: animateContent ? 0 : 50)
                            .opacity(animateContent ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: animateContent)
                        
                        // Status with pulse animation
                        statusSection
                            .offset(y: animateContent ? 0 : 50)
                            .opacity(animateContent ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: animateContent)
                        
                        // Details with glass morphism
                        detailsSection
                            .offset(y: animateContent ? 0 : 50)
                            .opacity(animateContent ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: animateContent)
                        
                        // Actions with ripple effects
                        if transaction.invoice != nil || transaction.status == .pending {
                            actionsSection
                                .offset(y: animateContent ? 0 : 50)
                                .opacity(animateContent ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: animateContent)
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                }
                .onAppear {
                    withAnimation {
                        animateContent = true
                    }
                    
                    // Trigger particle effect based on transaction type
                    if transaction.status == .completed {
                        #if os(iOS)
                        particleSystem.emit(count: 20, from: CGPoint(x: UIScreen.main.bounds.width / 2, y: 200))
                        #else
                        particleSystem.emit(count: 20, from: CGPoint(x: 400, y: 200))
                        #endif
                    }
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
            .sheet(isPresented: $showingQRCode) {
                TransactionQRCodeView(content: transaction.invoice ?? transaction.id.uuidString)
            }
        }
    }
    
    private var transactionIcon: some View {
        ZStack {
            // Animated background circles with gradient
            ForEach(0..<4) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: iconBackground.colors.map { $0.opacity(0.3 - Double(index) * 0.08) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: CGFloat(100 + index * 25), height: CGFloat(100 + index * 25))
                    .scaleEffect(transaction.status == .pending ? 1.1 : 1.0)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .animation(
                        transaction.status == .pending ?
                        .linear(duration: 10 + Double(index) * 2)
                        .repeatForever(autoreverses: false) :
                        .default,
                        value: transaction.status
                    )
            }
            
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [iconBackground.colors[0].opacity(0.5), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .blur(radius: 20)
            
            // Main icon with 3D effect
            Circle()
                .fill(iconBackground)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                        .rotationEffect(transaction.type == .sent ? .degrees(-45) : .degrees(0))
                )
                .shadow(color: iconBackground.colors[0].opacity(0.6), radius: 20, x: 0, y: 10)
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
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Description with glass effect
            DetailRow(
                icon: "text.quote",
                label: "Description",
                value: transaction.description
            )
            .padding(.horizontal, OlasDesign.Spacing.sm)
            
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
            ZStack {
                // Glass morphism background
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
                
                // Border gradient
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 8)
    }
    
    private var actionsSection: some View {
        VStack(spacing: OlasDesign.Spacing.sm) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                if let invoice = transaction.invoice {
                    // Share invoice with ripple effect
                    RippleButton(
                        icon: "square.and.arrow.up",
                        title: "Share",
                        gradient: OlasDesign.Colors.primaryGradient
                    ) {
                        showingShareSheet = true
                    }
                    
                    // Show QR Code
                    RippleButton(
                        icon: "qrcode",
                        title: "QR",
                        gradient: [Color(hex: "4ECDC4"), Color(hex: "44A08D")]
                    ) {
                        showingQRCode = true
                    }
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

// MARK: - Particle System

class ParticleSystem: ObservableObject {
    @Published var particles: [Particle] = []
    
    func emit(count: Int, from origin: CGPoint) {
        for _ in 0..<count {
            let particle = Particle(
                position: origin,
                velocity: CGPoint(
                    x: CGFloat.random(in: -150...150),
                    y: CGFloat.random(in: -300...-100)
                ),
                color: Color(hex: ["FFA726", "FFD54F", "4ECDC4", "667EEA"].randomElement()!),
                size: CGFloat.random(in: 4...8)
            )
            particles.append(particle)
        }
        
        // Remove particles after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.particles.removeAll()
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double = 1
}

struct ParticleEffectView: View {
    @ObservedObject var particleSystem: ParticleSystem
    @State private var animationTrigger = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particleSystem.particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.opacity)
                        .modifier(ParticleModifier(particle: particle))
                }
            }
        }
        .onChange(of: particleSystem.particles.count) { _, _ in
            animationTrigger.toggle()
        }
    }
}

struct ParticleModifier: ViewModifier {
    let particle: Particle
    @State private var offset = CGSize.zero
    @State private var opacity: Double = 1
    
    func body(content: Content) -> some View {
        content
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 2)) {
                    offset = CGSize(
                        width: particle.velocity.x,
                        height: particle.velocity.y
                    )
                    opacity = 0
                }
            }
    }
}

// MARK: - Ripple Button

struct RippleButton: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let action: () -> Void
    
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    
    var body: some View {
        Button(action: {
            // Trigger ripple
            withAnimation(.easeOut(duration: 0.6)) {
                rippleScale = 3
                rippleOpacity = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                rippleScale = 0
                rippleOpacity = 0.4
            }
            
            OlasDesign.Haptic.selection()
            action()
        }) {
            ZStack {
                // Ripple effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(rippleOpacity), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .scaleEffect(rippleScale)
                
                HStack {
                    Image(systemName: icon)
                    Text(title)
                }
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, OlasDesign.Spacing.lg)
                .padding(.vertical, OlasDesign.Spacing.md)
            }
            .background(
                LinearGradient(
                    colors: gradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
            .shadow(color: gradient[0].opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - QR Code View

struct TransactionQRCodeView: View {
    let content: String
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var qrImage: UIImage?
    #else
    @State private var qrImage: NSImage?
    #endif
    @State private var showCopied = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: OlasDesign.Spacing.xl) {
                    if let qrImage = qrImage {
                        #if os(iOS)
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 280)
                            .padding(OlasDesign.Spacing.lg)
                            .background(Color.white)
                            .cornerRadius(OlasDesign.CornerRadius.lg)
                            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                            .scaleEffect(showCopied ? 0.95 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showCopied)
                        #else
                        Image(nsImage: qrImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 280)
                            .padding(OlasDesign.Spacing.lg)
                            .background(Color.white)
                            .cornerRadius(OlasDesign.CornerRadius.lg)
                            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                            .scaleEffect(showCopied ? 0.95 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showCopied)
                        #endif
                    } else {
                        ProgressView()
                            .frame(width: 280, height: 280)
                    }
                    
                    Text("Scan to view details")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                    
                    // Copy button
                    Button {
                        copyContent()
                    } label: {
                        HStack {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            Text(showCopied ? "Copied!" : "Copy")
                        }
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(showCopied ? OlasDesign.Colors.success : OlasDesign.Colors.primary)
                        .padding(.horizontal, OlasDesign.Spacing.xl)
                        .padding(.vertical, OlasDesign.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                                .stroke(showCopied ? OlasDesign.Colors.success : OlasDesign.Colors.primary, lineWidth: 2)
                        )
                    }
                    .disabled(showCopied)
                }
                .padding()
            }
            .navigationTitle("QR Code")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .automatic) {
                #endif
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generateQRCode()
            }
        }
    }
    
    private func generateQRCode() {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                #if os(iOS)
                qrImage = UIImage(cgImage: cgImage)
                #else
                qrImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                #endif
            }
        }
    }
    
    private func copyContent() {
        #if os(iOS)
        UIPasteboard.general.string = content
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif
        
        OlasDesign.Haptic.success()
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

}
