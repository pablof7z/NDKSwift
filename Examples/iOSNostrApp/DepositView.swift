import SwiftUI
import NDKSwift

struct DepositView: View {
    @ObservedObject var walletViewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var amount = ""
    @State private var lightningInvoice = ""
    @State private var isGeneratingInvoice = false
    @State private var showingInvoice = false
    @State private var isMinting = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingQR = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Deposit Amount") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("sats")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Enter the amount you want to deposit into your wallet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isGeneratingInvoice {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Generating Lightning invoice...")
                        }
                    }
                } else if !lightningInvoice.isEmpty {
                    Section("Lightning Invoice") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pay this Lightning invoice to deposit sats:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(lightningInvoice)
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                            
                            HStack {
                                Button("Copy Invoice") {
                                    copyToClipboard(lightningInvoice)
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button("Show QR") {
                                    showingQR = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    if isMinting {
                        Section {
                            HStack {
                                ProgressView()
                                Text("Waiting for payment and minting tokens...")
                            }
                        }
                    } else {
                        Section {
                            VStack(spacing: 8) {
                                Button("Check Payment & Mint Tokens") {
                                    mintTokens()
                                }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.borderedProminent)
                                
                                Text("Pay the invoice above, then tap this button to mint your Cashu tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                } else {
                    Section {
                        Button("Generate Invoice") {
                            generateInvoice()
                        }
                        .disabled(amount.isEmpty || Int64(amount) == nil || Int64(amount) ?? 0 <= 0)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How deposits work:")
                            .font(.headline)
                        
                        Text("1. Enter amount and generate a Lightning invoice")
                            .font(.caption)
                        Text("2. Pay the invoice with any Lightning wallet")
                            .font(.caption)
                        Text("3. Check payment to mint Cashu tokens to your wallet")
                            .font(.caption)
                        Text("4. Your wallet balance will be updated")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Deposit Funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingQR) {
                QRCodeView(text: lightningInvoice)
            }
        }
    }
    
    private func generateInvoice() {
        guard let amountValue = Int64(amount) else { return }
        
        isGeneratingInvoice = true
        errorMessage = ""
        
        Task {
            do {
                let invoice = try await walletViewModel.generateDepositInvoice(amount: amountValue)
                
                await MainActor.run {
                    lightningInvoice = invoice
                    isGeneratingInvoice = false
                    showingInvoice = true
                }
            } catch {
                await MainActor.run {
                    isGeneratingInvoice = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func mintTokens() {
        guard let amountValue = Int64(amount) else { return }
        guard !lightningInvoice.isEmpty else { return }
        
        isMinting = true
        errorMessage = ""
        
        Task {
            do {
                try await walletViewModel.checkPaymentAndMint(invoice: lightningInvoice, amount: amountValue)
                
                await MainActor.run {
                    isMinting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isMinting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    DepositView(walletViewModel: WalletViewModel())
}