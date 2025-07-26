import SwiftUI
import NDKSwift
import CoreImage.CIFilterBuiltins

struct SendView: View {
    @ObservedObject var walletManager: OlasWalletManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) var dismiss
    
    @State private var sendMode: SendMode = .lightning
    @State private var invoice = ""
    @State private var amount = ""
    @State private var comment = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false
    @State private var showingScanner = false
    @State private var ecashToken: String?
    @State private var showingShareSheet = false
    @State private var selectedPresetAmount: Int64?
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isInvoiceFocused: Bool
    
    enum SendMode {
        case lightning
        case ecash
    }
    
    let presetAmounts: [Int64] = [100, 500, 1000, 5000, 10000, 50000]
    
    var body: some View {
        NavigationView {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Mode selector
                        modeSelectorView
                            .padding(.top, OlasDesign.Spacing.md)
                        
                        // Balance display
                        balanceView
                        
                        switch sendMode {
                        case .lightning:
                            lightningView
                        case .ecash:
                            ecashView
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                }
                
                // Loading overlay
                if isSending {
                    loadingOverlay
                }
            }
            .navigationTitle("Send")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(OlasDesign.Colors.text)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task {
                            await sendPayment()
                        }
                    }
                    .disabled(!canSend || isSending)
                    .font(OlasDesign.Typography.bodyBold)
                }
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Payment sent successfully!")
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView { result in
                    handleScannedQR(result)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let token = ecashToken {
                    ShareSheet(items: [token])
                }
            }
        }
    }
    
    // MARK: - Views
    
    private var modeSelectorView: some View {
        HStack(spacing: 0) {
            ForEach([SendMode.lightning, SendMode.ecash], id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        sendMode = mode
                    }
                    OlasDesign.Haptic.selection()
                } label: {
                    VStack(spacing: OlasDesign.Spacing.xs) {
                        Image(systemName: mode == .lightning ? "bolt.fill" : "banknote")
                            .font(.title2)
                            .foregroundStyle(sendMode == mode ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary)
                        
                        Text(mode == .lightning ? "Lightning" : "Ecash")
                            .font(OlasDesign.Typography.bodyMedium)
                            .foregroundStyle(sendMode == mode ? OlasDesign.Colors.text : OlasDesign.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OlasDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                            .fill(sendMode == mode ? OlasDesign.Colors.primary.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var balanceView: some View {
        VStack(spacing: OlasDesign.Spacing.xs) {
            Text("Available Balance")
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatSats(walletManager.currentBalance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(OlasDesign.Colors.text)
                    .contentTransition(.numericText())
                
                Text("sats")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var lightningView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Invoice input
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                Label("Lightning Invoice", systemImage: "doc.text")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                HStack {
                    TextField("Paste invoice or scan QR", text: $invoice)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isInvoiceFocused)
                    
                    Button {
                        showingScanner = true
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                            .foregroundStyle(OlasDesign.Colors.primary)
                    }
                }
                .padding(OlasDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .stroke(
                                    isInvoiceFocused ? OlasDesign.Colors.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
            }
            
            // Comment input
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                Label("Note (optional)", systemImage: "text.bubble")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                TextField("Add a note", text: $comment)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                    .padding(OlasDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                            .fill(OlasDesign.Colors.surface)
                    )
            }
            
            if let error = errorMessage {
                errorView(error)
            }
        }
    }
    
    private var ecashView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Amount input
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                Label("Amount", systemImage: "bitcoinsign.circle")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                HStack {
                    TextField("0", text: $amount)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(OlasDesign.Colors.text)
                        .keyboardType(.numberPad)
                        .focused($isAmountFocused)
                        .onChange(of: amount) { _ in
                            selectedPresetAmount = nil
                        }
                    
                    Text("sats")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                }
                .padding(OlasDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                        .fill(OlasDesign.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .stroke(
                                    isAmountFocused ? OlasDesign.Colors.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
                
                // Preset amounts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OlasDesign.Spacing.sm) {
                        ForEach(presetAmounts, id: \.self) { preset in
                            PresetAmountButton(
                                amount: preset,
                                isSelected: selectedPresetAmount == preset
                            ) {
                                selectedPresetAmount = preset
                                amount = String(preset)
                                isAmountFocused = false
                                OlasDesign.Haptic.selection()
                            }
                        }
                    }
                }
            }
            
            // Comment input
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                Label("Note (optional)", systemImage: "text.bubble")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(OlasDesign.Colors.textSecondary)
                
                TextField("Add a note", text: $comment)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                    .padding(OlasDesign.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                            .fill(OlasDesign.Colors.surface)
                    )
            }
            
            if let token = ecashToken {
                // Show generated token
                VStack(spacing: OlasDesign.Spacing.md) {
                    Text("Ecash token generated!")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(OlasDesign.Colors.success)
                    
                    Text(token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(OlasDesign.Colors.textSecondary)
                        .lineLimit(3)
                        .padding(OlasDesign.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                .fill(OlasDesign.Colors.surface)
                        )
                    
                    Button {
                        showingShareSheet = true
                        OlasDesign.Haptic.selection()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Token")
                        }
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, OlasDesign.Spacing.xl)
                        .padding(.vertical, OlasDesign.Spacing.md)
                        .background(
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full))
                    }
                }
            }
            
            if let error = errorMessage {
                errorView(error)
            }
        }
    }
    
    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(OlasDesign.Colors.error)
            Text(error)
                .font(OlasDesign.Typography.caption)
                .foregroundStyle(OlasDesign.Colors.error)
        }
        .padding(OlasDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.error.opacity(0.1))
        )
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: OlasDesign.Spacing.md) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text(sendMode == .lightning ? "Processing payment..." : "Creating ecash token...")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(.white)
            }
            .padding(OlasDesign.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                    .fill(OlasDesign.Colors.surface)
            )
            .shadow(radius: 20)
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSend: Bool {
        switch sendMode {
        case .lightning:
            return !invoice.isEmpty
        case .ecash:
            return !amount.isEmpty && Int64(amount) != nil
        }
    }
    
    // MARK: - Methods
    
    private func sendPayment() async {
        isSending = true
        errorMessage = nil
        ecashToken = nil
        
        do {
            switch sendMode {
            case .lightning:
                try await walletManager.payInvoice(invoice, comment: comment.isEmpty ? nil : comment)
                OlasDesign.Haptic.success()
                showingSuccess = true
                
            case .ecash:
                guard let amountSats = Int64(amount) else {
                    errorMessage = "Invalid amount"
                    isSending = false
                    return
                }
                
                let token = try await walletManager.sendEcash(
                    amount: amountSats,
                    comment: comment.isEmpty ? nil : comment
                )
                
                ecashToken = token
                OlasDesign.Haptic.success()
            }
        } catch {
            errorMessage = error.localizedDescription
            OlasDesign.Haptic.error()
        }
        
        isSending = false
    }
    
    private func handleScannedQR(_ result: String) {
        if result.lowercased().starts(with: "lightning:") {
            invoice = result.replacingOccurrences(of: "lightning:", with: "")
        } else if result.lowercased().starts(with: "lnbc") {
            invoice = result
        } else {
            errorMessage = "Invalid QR code"
        }
    }
    
    private func formatSats(_ sats: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "0"
    }
    
    private func formatAmount(_ sats: Int64) -> String {
        if sats >= 1000 {
            return "\(sats / 1000)k"
        }
        return "\(sats)"
    }
}

// MARK: - Supporting Views

struct PresetAmountButton: View {
    let amount: Int64
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(formatAmount(amount))
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundStyle(isSelected ? .white : OlasDesign.Colors.text)
                
                Text("sats")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : OlasDesign.Colors.textSecondary)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .fill(
                        isSelected ?
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [OlasDesign.Colors.surface, OlasDesign.Colors.surface],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                    .stroke(
                        isSelected ? Color.clear : OlasDesign.Colors.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatAmount(_ amount: Int64) -> String {
        if amount >= 1000 {
            return "\(amount / 1000)k"
        }
        return "\(amount)"
    }
}