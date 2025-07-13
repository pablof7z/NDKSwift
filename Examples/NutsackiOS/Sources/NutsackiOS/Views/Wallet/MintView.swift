import SwiftUI
import SwiftData
import NDKSwift
import CashuSwift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MintView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var amount = ""
    @State private var selectedMintURL: String = ""
    @State private var availableMints: [NDKCashuWallet.MintInfo] = []
    @State private var isMinting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var mintQuote: CashuMintQuote?
    @State private var showInvoice = false
    @State private var depositTask: Task<Void, Never>?
    
    var body: some View {
        Form {
            Section {
                TextField("Amount in sats", text: $amount)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                
                if !availableMints.isEmpty {
                    Picker("Mint", selection: $selectedMintURL) {
                        ForEach(availableMints, id: \.url.absoluteString) { mint in
                            Text(mint.url.host ?? mint.url.absoluteString).tag(mint.url.absoluteString)
                        }
                    }
                }
            } header: {
                Text("Mint Details")
            } footer: {
                Text("Create a Lightning invoice to mint ecash")
            }
            
            Section {
                Button(action: createMintQuote) {
                    if isMinting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Invoice")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(amount.isEmpty || selectedMintURL.isEmpty || isMinting)
            }
        }
        .navigationTitle("Mint Ecash")
        .platformNavigationBarTitleDisplayMode(inline: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showInvoice) {
            if let quote = mintQuote {
                InvoiceView(
                    invoice: quote.invoice,
                    amount: Int(quote.amount),
                    onPaid: { checkMintStatus() }
                )
            }
        }
        .task {
            await loadMints()
        }
        .onDisappear {
            depositTask?.cancel()
        }
    }
    
    private func loadMints() async {
        guard let wallet = walletManager.activeWallet else { return }
        
        let mints = await wallet.getMints()
        await MainActor.run {
            availableMints = mints
            if selectedMintURL.isEmpty && !mints.isEmpty {
                selectedMintURL = mints.first?.url.absoluteString ?? ""
            }
        }
    }
    
    private func createMintQuote() {
        guard let amountInt = Int(amount),
              amountInt > 0,
              !selectedMintURL.isEmpty else { return }
        
        isMinting = true
        
        Task {
            do {
                // Request mint quote from the wallet
                let quote = try await walletManager.requestMint(
                    amount: Int64(amountInt),
                    mintURL: selectedMintURL
                )
                
                await MainActor.run {
                    mintQuote = quote
                    showInvoice = true
                    isMinting = false
                }
                
                // Start monitoring for deposit
                startDepositMonitoring(quote: quote)
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isMinting = false
                }
            }
        }
    }
    
    private func startDepositMonitoring(quote: CashuMintQuote) {
        depositTask?.cancel()
        
        depositTask = Task {
            do {
                for try await status in await walletManager.monitorDeposit(quote: quote) {
                    switch status {
                    case .pending:
                        // Still waiting for payment
                        print("Deposit pending for quote: \(quote.quoteId)")
                        
                    case .minted(let proofs):
                        // Success! Tokens have been minted
                        print("Successfully minted \(proofs.count) proofs")
                        
                        await MainActor.run {
                            // Update wallet balance in UI
                            // The wallet manager already saved the proofs
                            dismiss()
                        }
                        return
                        
                    case .expired:
                        await MainActor.run {
                            errorMessage = "Lightning invoice expired"
                            showError = true
                            showInvoice = false
                        }
                        return
                        
                    case .cancelled:
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to monitor deposit: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func checkMintStatus() {
        // This is called when the invoice view is shown
        // The actual monitoring is handled by startDepositMonitoring
    }
}

// MARK: - Invoice View
struct InvoiceView: View {
    let invoice: String
    let amount: Int
    let onPaid: () -> Void
    
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Amount
                VStack(spacing: 8) {
                    Text("\(amount)")
                        .font(.system(size: 48, weight: .bold))
                    Text("sats")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)
                
                // QR Code
                QRCodeView(content: invoice)
                
                // Invoice text
                VStack(spacing: 12) {
                    Text(invoice)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                    
                    Button(action: copyInvoice) {
                        Label(
                            copied ? "Copied!" : "Copy Invoice",
                            systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(copied ? .green : .orange)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Status
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Waiting for payment...")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Lightning Invoice")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func copyInvoice() {
        invoice.copyToPasteboard()
        withAnimation {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
    
}