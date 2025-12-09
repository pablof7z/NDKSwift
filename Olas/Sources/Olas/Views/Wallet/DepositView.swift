// DepositView.swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

struct DepositView: View {
    let ndk: NDK
    @ObservedObject var walletViewModel: WalletViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var amount: String = ""
    @State private var selectedMint: String?
    @State private var quote: CashuMintQuote?
    @State private var depositStatus: DepositStatus?
    @State private var isGeneratingInvoice = false
    @State private var isMonitoring = false
    @State private var error: Error?

    private let suggestedAmounts = [1000, 5000, 10000, 21000]

    var body: some View {
        NavigationStack {
            Group {
                if let quote = quote {
                    invoiceView(quote: quote)
                } else {
                    amountInputView
                }
            }
            .navigationTitle("Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
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

    // MARK: - Amount Input View

    private var amountInputView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Amount display
            VStack(spacing: 8) {
                Text("Enter Amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: $amount)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 200)

                    Text("sats")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Suggested amounts
            HStack(spacing: 12) {
                ForEach(suggestedAmounts, id: \.self) { suggestedAmount in
                    Button {
                        amount = "\(suggestedAmount)"
                    } label: {
                        Text(formatAmount(suggestedAmount))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(amount == "\(suggestedAmount)"
                                          ? OlasTheme.Colors.deepTeal
                                          : Color.secondary.opacity(0.1))
                            )
                            .foregroundStyle(amount == "\(suggestedAmount)" ? .white : .primary)
                    }
                }
            }

            // Mint selector
            if walletViewModel.configuredMints.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deposit to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Mint", selection: $selectedMint) {
                        ForEach(walletViewModel.configuredMints, id: \.self) { mint in
                            Text(mintDisplayName(mint))
                                .tag(mint as String?)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            // Generate invoice button
            Button {
                Task { await generateInvoice() }
            } label: {
                if isGeneratingInvoice {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text("Generate Invoice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OlasTheme.Colors.deepTeal)
            .disabled(!isValidAmount || isGeneratingInvoice)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            // Select first mint by default
            if selectedMint == nil {
                selectedMint = walletViewModel.configuredMints.first
            }
        }
    }

    // MARK: - Invoice View

    private func invoiceView(quote: CashuMintQuote) -> some View {
        VStack(spacing: 24) {
            // Status
            VStack(spacing: 8) {
                if case .minted = depositStatus {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Deposit Complete!")
                        .font(.title2.bold())

                    Text("\(quote.amount) sats added to your wallet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Pay this invoice")
                        .font(.headline)

                    Text("\(quote.amount) sats")
                        .font(.title.bold())
                }
            }

            if case .minted = depositStatus {
                // Success view
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
            } else {
                // QR Code
                NDKUIQRCodeView(
                    content: "lightning:\(quote.invoice)",
                    size: 250
                )

                // Invoice text
                VStack(spacing: 8) {
                    Text(truncatedInvoice(quote.invoice))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Button {
                        UIPasteboard.general.string = quote.invoice
                    } label: {
                        Label("Copy Invoice", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)

                // Status indicator
                if isMonitoring {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)

                        Text("Waiting for payment...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Cancel button
                Button {
                    self.quote = nil
                    self.depositStatus = nil
                    self.isMonitoring = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                }
                .padding(.bottom, 32)
            }
        }
        .padding()
        .task {
            await monitorDeposit(quote: quote)
        }
    }

    // MARK: - Actions

    private func generateInvoice() async {
        guard let amountValue = Int64(amount),
              let mintURL = selectedMint else { return }

        isGeneratingInvoice = true
        defer { isGeneratingInvoice = false }

        do {
            let newQuote = try await walletViewModel.requestDeposit(
                amount: amountValue,
                mintURL: mintURL
            )
            self.quote = newQuote
        } catch {
            self.error = error
        }
    }

    private func monitorDeposit(quote: CashuMintQuote) async {
        isMonitoring = true
        defer { isMonitoring = false }

        do {
            for try await status in await walletViewModel.monitorDeposit(quote: quote) {
                self.depositStatus = status

                if case .minted = status {
                    // Success - refresh wallet
                    await walletViewModel.refreshBalance()
                    await walletViewModel.refreshTransactions()
                    break
                }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Helpers

    private var isValidAmount: Bool {
        guard let value = Int(amount) else { return false }
        return value > 0
    }

    private func formatAmount(_ amount: Int) -> String {
        if amount >= 1000 {
            return "\(amount / 1000)k"
        }
        return "\(amount)"
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsedURL = URL(string: url) else { return url }
        return parsedURL.host ?? url
    }

    private func truncatedInvoice(_ invoice: String) -> String {
        guard invoice.count > 40 else { return invoice }
        let prefix = String(invoice.prefix(20))
        let suffix = String(invoice.suffix(20))
        return "\(prefix)...\(suffix)"
    }
}
