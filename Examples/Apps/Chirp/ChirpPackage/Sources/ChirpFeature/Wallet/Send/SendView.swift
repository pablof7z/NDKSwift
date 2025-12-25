import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu
import UIKit

/// Send payment view
struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var walletState: WalletState

    @State private var invoice = ""
    @State private var isPaying = false
    @State private var errorMessage: String?
    @State private var paymentSuccess = false
    @State private var paidAmount: Int64?

    var body: some View {
        VStack(spacing: 24) {
            if paymentSuccess {
                successView
            } else {
                inputView
            }
        }
        .padding()
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Input View

    @ViewBuilder
    private var inputView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Balance indicator
            HStack {
                Text("Available:")
                Text("\(walletState.balance) sats")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Invoice input
            VStack(alignment: .leading, spacing: 8) {
                Text("Lightning Invoice")
                    .font(.headline)

                TextEditor(text: $invoice)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Paste button
                HStack {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.subheadline)
                    }

                    Spacer()

                    if let parsed = parseInvoice() {
                        Text("\(parsed) sats")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Pay button
            if isPaying {
                ProgressView("Paying...")
            } else {
                Button {
                    Task { await pay() }
                } label: {
                    Text("Pay")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(invoice.isEmpty ? Color.secondary.opacity(0.3) : .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(invoice.isEmpty)
            }
        }
    }

    // MARK: - Success View

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Payment Sent!")
                .font(.largeTitle.bold())

            if let amount = paidAmount {
                Text("\(amount) sats")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Helpers

    private func pasteFromClipboard() {
        if let pasteboardString = UIPasteboard.general.string {
            invoice = pasteboardString
        }
    }

    private func parseInvoice() -> Int64? {
        let cleanedInvoice = invoice
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "lightning:", with: "")

        guard cleanedInvoice.hasPrefix("lnbc") else { return nil }

        // Parse amount from BOLT11 invoice
        // Format: lnbc<amount><multiplier>...
        let afterPrefix = String(cleanedInvoice.dropFirst(4))

        var amountString = ""
        var multiplierChar: Character?

        for char in afterPrefix {
            if char.isNumber {
                amountString += String(char)
            } else {
                multiplierChar = char
                break
            }
        }

        guard let amount = Int64(amountString), let mult = multiplierChar else {
            return nil
        }

        // Convert to satoshis based on multiplier
        switch mult {
        case "m": // milli-BTC (0.001 BTC = 100,000 sats)
            return amount * 100_000
        case "u": // micro-BTC (0.000001 BTC = 100 sats)
            return amount * 100
        case "n": // nano-BTC (0.000000001 BTC = 0.1 sats)
            return amount / 10
        case "p": // pico-BTC (0.000000000001 BTC = 0.0001 sats)
            return amount / 10000
        default:
            return nil
        }
    }

    private func pay() async {
        let cleanedInvoice = invoice
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "lightning:", with: "")
            .replacingOccurrences(of: "LIGHTNING:", with: "")

        guard !cleanedInvoice.isEmpty else {
            errorMessage = "Please enter an invoice"
            return
        }

        guard cleanedInvoice.lowercased().hasPrefix("lnbc") else {
            errorMessage = "Invalid Lightning invoice"
            return
        }

        isPaying = true
        defer { isPaying = false }

        do {
            switch walletState.walletType {
            case .cashu:
                let amount = parseInvoice() ?? 0
                let (_, _) = try await walletState.payLightning(invoice: cleanedInvoice, amount: amount)
                paidAmount = amount
                paymentSuccess = true

            case .nwc:
                let response = try await walletState.payInvoiceNWC(invoice: cleanedInvoice)
                paidAmount = parseInvoice()
                paymentSuccess = true

                if let feePaid = response.feesPaid, feePaid > 0 {
                    // Could show fee info
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SendView(walletState: WalletState(ndk: NDK(relayURLs: [])))
    }
}
