import SwiftUI
import SwiftData
import NDKSwift

struct MeltView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var lightningInvoice = ""
    @State private var decodedAmount: Int64?
    @State private var decodedDescription: String?
    @State private var selectedMint: MintInfo?
    @State private var availableBalance: Int = 0
    @State private var isMelting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showScanner = false
    @State private var showSuccess = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Lightning invoice", text: $lightningInvoice, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.system(.caption, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        
                        Button(action: { showScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if let amount = decodedAmount {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.orange)
                                Text("\(amount) sats")
                                    .font(.headline)
                            }
                            
                            if let description = decodedDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            } header: {
                Text("Lightning Invoice")
            } footer: {
                Text("Pay a Lightning invoice using your ecash balance")
            }
            
            if let amount = decodedAmount {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(Int(amount)) sats")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Fee (est.)")
                        Spacer()
                        Text("~1 sat")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Total")
                        Spacer()
                        Text("\(Int(amount + 1)) sats")
                            .fontWeight(.bold)
                            .foregroundStyle(amount + 1 > availableBalance ? .red : .primary)
                    }
                } header: {
                    Text("Payment Details")
                }
            }
            
            Section {
                Button(action: meltTokens) {
                    if isMelting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Pay Invoice")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(lightningInvoice.isEmpty || decodedAmount == nil || isMelting)
            }
        }
        .navigationTitle("Pay Lightning")
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
        .sheet(isPresented: $showScanner) {
            QRScannerView { scannedValue in
                lightningInvoice = scannedValue
                showScanner = false
                decodeInvoice()
            }
        }
        .sheet(isPresented: $showSuccess) {
            MeltSuccessView(amount: Int(decodedAmount ?? 0)) {
                dismiss()
            }
        }
        .onChange(of: lightningInvoice) { _, _ in
            decodeInvoice()
        }
        .onAppear {
            Task {
                do {
                    let balance = try await walletManager.getBalance()
                    await MainActor.run {
                        availableBalance = Int(balance)
                    }
                } catch {
                    print("Failed to get balance: \(error)")
                }
            }
        }
    }
    
    private func decodeInvoice() {
        // Basic Lightning invoice decoding
        var cleanInvoice = lightningInvoice
        if cleanInvoice.starts(with: "lightning:") {
            cleanInvoice = String(cleanInvoice.dropFirst(10))
        }
        
        if cleanInvoice.starts(with: "lnbc") {
            // Extract amount from invoice if present
            let trimmed = cleanInvoice.dropFirst(4)
            var amountStr = ""
            var multiplier: Int64 = 1
            
            for char in trimmed {
                if char.isNumber {
                    amountStr.append(char)
                } else if char == "m" {
                    multiplier = 100 // milli-bitcoin
                    break
                } else if char == "u" {
                    multiplier = 100000 // micro-bitcoin
                    break
                } else if char == "n" {
                    multiplier = 100000000 // nano-bitcoin
                    break
                } else if char == "p" {
                    multiplier = 100000000000 // pico-bitcoin
                    break
                } else {
                    break
                }
            }
            
            if let amount = Int64(amountStr) {
                // Convert to sats
                decodedAmount = (amount * multiplier) / 1000
            }
            
            // Parse payment hash and description if available
            decodedDescription = "Lightning payment" // TODO: Add invoice parsing
        } else {
            decodedAmount = nil
            decodedDescription = nil
        }
    }
    
    private func meltTokens() {
        guard let amount = decodedAmount else { return }
        
        isMelting = true
        
        Task {
            do {
                // Pay the Lightning invoice
                let _ = try await walletManager.payLightning(
                    invoice: lightningInvoice.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: amount
                )
                
                // Create transaction record
                let transaction = Transaction(
                    type: .melt,
                    amount: Int(amount),
                    memo: decodedDescription
                )
                transaction.lightningInvoice = lightningInvoice
                transaction.status = .completed
                
                await MainActor.run {
                    modelContext.insert(transaction)
                    do {
                        try modelContext.save()
                    } catch {
                        print("Failed to save transaction: \(error)")
                    }
                    
                    showSuccess = true
                    isMelting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isMelting = false
                }
            }
        }
    }
}

// MARK: - Melt Success View
struct MeltSuccessView: View {
    let amount: Int
    let onDone: () -> Void
    
    @State private var animationAmount = 0.0
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Success animation
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 4)
                    .frame(width: 120, height: 120)
                    .scaleEffect(animationAmount)
                    .opacity(2 - animationAmount)
                
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
                    .scaleEffect(animationAmount > 0 ? 1 : 0.5)
            }
            
            VStack(spacing: 8) {
                Text("Payment Sent!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("\(amount) sats")
                    .font(.title)
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animationAmount = 1.5
            }
        }
    }
    
    private func parseLightningDescription(_ invoice: String) -> String? {
        // This is a simplified parser - in production use a proper Lightning invoice decoder
        // Look for description tag 'd' in the invoice
        
        // Remove the human-readable part and amount
        var dataPartStart = 0
        for (index, char) in invoice.enumerated() {
            if char == "1" && index > 4 { // Found separator '1' after prefix
                dataPartStart = index + 1
                break
            }
        }
        
        guard dataPartStart > 0 && dataPartStart < invoice.count else {
            return nil
        }
        
        // The data part contains tagged fields
        // 'd' tag = description (UTF-8 string)
        // This is a very simplified check - real implementation would properly decode bech32
        // and parse tagged fields according to BOLT 11
        
        return nil // For now, return nil as proper decoding requires bech32 decoder
    }
    
}