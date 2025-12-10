// SendView.swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

struct SendView: View {
    let ndk: NDK
    @ObservedObject var walletViewModel: WalletViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var sendMode: SendMode = .lightning
    @State private var invoice: String = ""
    @State private var amount: String = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var showScanner = false
    @State private var error: Error?
    @State private var paymentResult: (preimage: String, feePaid: Int64?)?
    @State private var generatedToken: String?

    enum SendMode: String, CaseIterable {
        case lightning = "Lightning"
        case ecash = "Ecash"
    }

    var body: some View {
        NavigationStack {
            Group {
                if showSuccess {
                    successView
                } else {
                    sendForm
                }
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                NDKUIQRScanner(
                    onScan: { result in
                        handleScannedCode(result)
                        showScanner = false
                    },
                    onDismiss: {
                        showScanner = false
                    }
                )
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
            }
        }
    }

    // MARK: - Send Form

    private var sendForm: some View {
        VStack(spacing: 24) {
            // Mode picker
            Picker("Send Mode", selection: $sendMode) {
                ForEach(SendMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Balance display
            HStack {
                Text("Available:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(walletViewModel.balance) sats")
                    .font(.subheadline.weight(.medium))
            }

            if sendMode == .lightning {
                lightningForm
            } else {
                ecashForm
            }

            Spacer()

            // Send button
            Button {
                Task { await performSend() }
            } label: {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text(sendMode == .lightning ? "Pay Invoice" : "Generate Token")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OlasTheme.Colors.zapGold)
            .disabled(!isValidInput || isSending)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding(.top)
    }

    // MARK: - Lightning Form

    private var lightningForm: some View {
        VStack(spacing: 16) {
            // Invoice input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Lightning Invoice")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.body)
                    }

                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            invoice = clipboard
                            parseInvoiceAmount()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body)
                    }
                }

                TextEditor(text: $invoice)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: invoice) { _, _ in
                        parseInvoiceAmount()
                    }
            }
            .padding(.horizontal)

            // Amount (auto-detected from invoice)
            if let parsedAmount = parsedInvoiceAmount {
                HStack {
                    Text("Amount:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(parsedAmount) sats")
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Ecash Form

    private var ecashForm: some View {
        VStack(spacing: 16) {
            // Amount input
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("0", text: $amount)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)

                    Text("sats")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            // Suggested amounts
            HStack(spacing: 12) {
                ForEach([100, 500, 1000], id: \.self) { suggestedAmount in
                    Button {
                        amount = "\(suggestedAmount)"
                    } label: {
                        Text("\(suggestedAmount)")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Button {
                    amount = "\(walletViewModel.balance)"
                } label: {
                    Text("Max")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            if sendMode == .lightning {
                Text("Payment Sent!")
                    .font(.title2.bold())

                if let result = paymentResult {
                    VStack(spacing: 8) {
                        if let fee = result.feePaid, fee > 0 {
                            Text("Fee: \(fee) sats")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Token Generated!")
                    .font(.title2.bold())

                if let token = generatedToken {
                    VStack(spacing: 12) {
                        Text("Share this token:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(truncatedToken(token))
                            .font(.caption.monospaced())
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            UIPasteboard.general.string = token
                        } label: {
                            Label("Copy Token", systemImage: "doc.on.doc")
                        }
                    }
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(OlasTheme.Colors.deepTeal)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func performSend() async {
        isSending = true
        defer { isSending = false }

        do {
            if sendMode == .lightning {
                guard let amountValue = parsedInvoiceAmount else {
                    throw SendError.invalidAmount
                }

                let result = try await walletViewModel.payLightningInvoice(
                    invoice.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: Int64(amountValue)
                )
                paymentResult = result
            } else {
                guard let amountValue = Int64(amount),
                      let mintURL = walletViewModel.configuredMints.first.flatMap({ URL(string: $0) }) else {
                    throw SendError.invalidAmount
                }

                let token = try await walletViewModel.createToken(
                    amount: amountValue,
                    mint: mintURL
                )
                generatedToken = token
            }

            showSuccess = true

        } catch {
            self.error = error
        }
    }

    private func handleScannedCode(_ code: String) {
        // Handle lightning: prefix
        var cleanedCode = code
        if cleanedCode.lowercased().hasPrefix("lightning:") {
            cleanedCode = String(cleanedCode.dropFirst(10))
        }
        invoice = cleanedCode
        parseInvoiceAmount()
    }

    // MARK: - Helpers

    private var isValidInput: Bool {
        if sendMode == .lightning {
            return !invoice.isEmpty && (parsedInvoiceAmount ?? 0) > 0
        } else {
            guard let value = Int64(amount) else { return false }
            return value > 0 && value <= walletViewModel.balance
        }
    }

    @State private var parsedInvoiceAmount: Int?

    private func parseInvoiceAmount() {
        // Simple bolt11 amount parsing
        // Format: lnbc<amount><multiplier>...
        let cleanInvoice = invoice.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanInvoice.hasPrefix("lnbc") || cleanInvoice.hasPrefix("lntb") else {
            parsedInvoiceAmount = nil
            return
        }

        // Extract amount part (after lnbc/lntb prefix)
        let prefix = cleanInvoice.hasPrefix("lnbc") ? "lnbc" : "lntb"
        let afterPrefix = String(cleanInvoice.dropFirst(prefix.count))

        // Find where the amount ends (at first non-digit after optional digits)
        var amountStr = ""
        var multiplier: Character?

        for char in afterPrefix {
            if char.isNumber {
                amountStr += String(char)
            } else if "munp".contains(char) {
                multiplier = char
                break
            } else {
                break
            }
        }

        guard let baseAmount = Int(amountStr) else {
            parsedInvoiceAmount = nil
            return
        }

        // Apply multiplier (convert to sats)
        let msatsMultiplier: Int
        switch multiplier {
        case "m": msatsMultiplier = 100_000_000 // milli-bitcoin = 100k sats
        case "u": msatsMultiplier = 100_000     // micro-bitcoin = 100 sats
        case "n": msatsMultiplier = 100         // nano-bitcoin = 0.1 sats (we'll round)
        case "p": msatsMultiplier = 1           // pico-bitcoin = 0.0001 sats
        default: msatsMultiplier = 100_000_000_000 // No multiplier = full bitcoin
        }

        let msats = baseAmount * msatsMultiplier / 1000
        parsedInvoiceAmount = max(1, msats)
    }

    private func truncatedToken(_ token: String) -> String {
        guard token.count > 50 else { return token }
        let prefix = String(token.prefix(25))
        let suffix = String(token.suffix(25))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Errors

enum SendError: LocalizedError {
    case invalidAmount
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Invalid amount"
        case .insufficientFunds:
            return "Insufficient funds"
        }
    }
}
