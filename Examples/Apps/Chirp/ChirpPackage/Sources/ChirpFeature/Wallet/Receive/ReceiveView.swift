import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu
import CoreImage.CIFilterBuiltins
import UIKit

/// Receive/Deposit view
struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var walletState: WalletState

    @State private var amount = ""
    @State private var selectedMint: String?
    @State private var invoice: String?
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            if let invoice = invoice {
                invoiceView(invoice)
            } else {
                amountInputView
            }
        }
        .padding()
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    walletState.stopMonitoringDeposit()
                    dismiss()
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: walletState.depositStatus) { _, newStatus in
            if case .minted = newStatus {
                // Auto-dismiss after success
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    dismiss()
                }
            }
        }
        .onDisappear {
            walletState.stopMonitoringDeposit()
        }
    }

    // MARK: - Amount Input

    @ViewBuilder
    private var amountInputView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Amount display
            VStack(spacing: 4) {
                Text(amount.isEmpty ? "0" : amount)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("sats")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Mint selector (Cashu only)
            if walletState.walletType == .cashu && !walletState.configuredMints.isEmpty {
                mintSelector
            }

            Spacer()

            // Number pad
            numberPad

            // Create button
            if isCreating {
                ProgressView("Creating invoice...")
            } else {
                Button {
                    Task { await createInvoice() }
                } label: {
                    Text("Create Invoice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValidAmount ? .blue : .secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!isValidAmount)
            }
        }
    }

    @ViewBuilder
    private var mintSelector: some View {
        Menu {
            ForEach(walletState.configuredMints, id: \.self) { mint in
                Button {
                    selectedMint = mint
                } label: {
                    HStack {
                        Text(mintDisplayName(mint))
                        if selectedMint == mint {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text("Mint: \(mintDisplayName(selectedMint ?? walletState.configuredMints.first ?? ""))")
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.2), in: Capsule())
        }
        .onAppear {
            if selectedMint == nil {
                selectedMint = walletState.configuredMints.first
            }
        }
    }

    @ViewBuilder
    private var numberPad: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { row in
                HStack(spacing: 24) {
                    ForEach(1...3, id: \.self) { col in
                        let digit = row * 3 + col
                        numberButton("\(digit)")
                    }
                }
            }
            HStack(spacing: 24) {
                numberButton("00")
                numberButton("0")
                numberButton("⌫", isBackspace: true)
            }
        }
    }

    @ViewBuilder
    private func numberButton(_ label: String, isBackspace: Bool = false) -> some View {
        Button {
            if isBackspace {
                if !amount.isEmpty {
                    amount.removeLast()
                }
            } else {
                // Prevent leading zeros
                if amount == "0" && label != "00" {
                    amount = label
                } else if amount.isEmpty && label == "00" {
                    // Don't add leading double zero
                } else {
                    amount += label
                }
            }
        } label: {
            Text(label)
                .font(.title)
                .fontWeight(.medium)
                .frame(width: 72, height: 72)
                .background(Color.secondary.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invoice View

    @ViewBuilder
    private func invoiceView(_ invoice: String) -> some View {
        VStack(spacing: 24) {
            // Status
            if let status = walletState.depositStatus {
                depositStatusView(status)
            } else {
                Text("Waiting for payment...")
                    .foregroundStyle(.secondary)
            }

            // QR Code
            if let qrImage = generateQRCode(from: invoice) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250, maxHeight: 250)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Invoice text
            VStack(spacing: 8) {
                Text(invoice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    copyToClipboard(invoice)
                } label: {
                    Label("Copy Invoice", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    @ViewBuilder
    private func depositStatusView(_ status: DepositStatus) -> some View {
        switch status {
        case .pending:
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for payment...")
            }
            .foregroundStyle(.secondary)

        case .minted(let amount):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Received \(amount) sats!")
                    .font(.headline)
            }

        case .expired:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Invoice expired")
            }

        case .cancelled:
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Cancelled")
            }
        }
    }

    // MARK: - Helpers

    private var isValidAmount: Bool {
        guard let amt = Int64(amount), amt > 0 else {
            return false
        }
        return true
    }

    private func mintDisplayName(_ url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.host ?? url
    }

    private func createInvoice() async {
        guard let amt = Int64(amount), amt > 0 else {
            errorMessage = "Please enter a valid amount"
            return
        }

        isCreating = true
        defer { isCreating = false }

        do {
            switch walletState.walletType {
            case .cashu:
                guard let mint = selectedMint ?? walletState.configuredMints.first else {
                    errorMessage = "No mint configured"
                    return
                }

                let quote = try await walletState.requestDeposit(amount: amt, mintURL: mint)
                invoice = quote.invoice

                // Start monitoring deposit - updates walletState.depositStatus
                walletState.startMonitoringDeposit(quote: quote)

            case .nwc:
                let response = try await walletState.createInvoiceNWC(amount: amt, description: nil)
                invoice = response.invoice
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyToClipboard(_ string: String) {
        UIPasteboard.general.string = string
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    NavigationStack {
        ReceiveView(walletState: WalletState(ndk: NDK(relayURLs: [])))
    }
}
