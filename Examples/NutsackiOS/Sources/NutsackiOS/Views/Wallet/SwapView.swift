import SwiftUI
import SwiftData
import NDKSwift

struct SwapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var amount = ""
    @State private var sourceMint: Mint?
    @State private var destinationMint: Mint?
    @State private var isSwapping = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var transferResult: TransferResult?
    
    // Fee estimation
    @State private var estimatedFees: (lightningFee: Int64, inputFee: Int64, totalFee: Int64)?
    @State private var isEstimatingFees = false
    @State private var mints: [Mint] = []
    
    var amountInt: Int64 {
        Int64(amount) ?? 0
    }
    
    var canSwap: Bool {
        guard !amount.isEmpty else { return false }
        guard amountInt > 0 else { return false }
        guard sourceMint != nil else { return false }
        guard destinationMint != nil else { return false }
        guard sourceMint != destinationMint else { return false }
        guard !isSwapping else { return false }
        return true
    }
    
    @ViewBuilder
    var amountSection: some View {
        Section {
            HStack {
                TextField("Amount", text: $amount)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Text("sats")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Amount to Transfer")
        }
    }
    
    var body: some View {
        Form {
            amountSection
            
            Section {
                Picker("From Mint", selection: $sourceMint) {
                    Text("Select mint").tag(nil as Mint?)
                    ForEach(mints) { mint in
                        MintPickerRow(mint: mint, balance: mintBalance(mint))
                            .tag(mint as Mint?)
                    }
                }
                
                Button(action: swapMints) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("Swap Direction")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(sourceMint == nil || destinationMint == nil)
                
                Picker("To Mint", selection: $destinationMint) {
                    Text("Select mint").tag(nil as Mint?)
                    ForEach(mints) { mint in
                        Text(mint.displayName).tag(mint as Mint?)
                    }
                }
            } header: {
                Text("Transfer Between Mints")
            }
            
            if let fees = estimatedFees {
                Section {
                    HStack {
                        Text("Lightning Fee")
                        Spacer()
                        Text("\(fees.lightningFee) sats")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Input Fee")
                        Spacer()
                        Text("\(fees.inputFee) sats")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total Fee")
                        Spacer()
                        Text("\(fees.totalFee) sats")
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("You'll Receive")
                        Spacer()
                        Text("\(max(0, amountInt - fees.totalFee)) sats")
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Estimated Fees")
                } footer: {
                    Text("Actual fees may vary slightly")
                }
            }
            
            Section {
                Button(action: performSwap) {
                    if isSwapping {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Transfer")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSwap)
            }
        }
        .navigationTitle("Transfer Between Mints")
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
        .alert("Transfer Successful", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            if let result = transferResult {
                Text("Transferred \(result.amountTransferred) sats\nFee paid: \(result.feePaid) sats")
            }
        }
        .onChange(of: amount) { _, _ in
            estimateFees()
        }
        .onChange(of: sourceMint) { _, _ in
            estimateFees()
        }
        .onChange(of: destinationMint) { _, _ in
            estimateFees()
        }
        .onAppear {
            loadMints()
        }
    }
    
    private func mintBalance(_ mint: Mint) -> Int {
        mint.tokens.filter { $0.state == .unspent }.reduce(0) { $0 + $1.amount }
    }
    
    private func swapMints() {
        let temp = sourceMint
        sourceMint = destinationMint
        destinationMint = temp
    }
    
    private func estimateFees() {
        guard amountInt > 0,
              let source = sourceMint,
              let destination = destinationMint,
              source != destination else {
            estimatedFees = nil
            return
        }
        
        isEstimatingFees = true
        
        Task {
            do {
                let fees = try await walletManager.estimateTransferFees(
                    amount: amountInt,
                    fromMint: source.url,
                    toMint: destination.url
                )
                
                await MainActor.run {
                    estimatedFees = fees
                    isEstimatingFees = false
                }
            } catch {
                await MainActor.run {
                    estimatedFees = nil
                    isEstimatingFees = false
                }
            }
        }
    }
    
    private func performSwap() {
        guard canSwap,
              let source = sourceMint,
              let destination = destinationMint else { return }
        
        isSwapping = true
        
        Task {
            do {
                let result = try await walletManager.transferBetweenMints(
                    amount: amountInt,
                    fromMint: source.url,
                    toMint: destination.url
                )
                
                await MainActor.run {
                    transferResult = result
                    showSuccess = true
                    isSwapping = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSwapping = false
                }
            }
        }
    }
    
    private func loadMints() {
        Task {
            if let wallet = walletManager.activeWallet {
                let loadedMints = await wallet.getMints()
                await MainActor.run {
                    mints = loadedMints
                    // Select first two different mints by default
                    if mints.count >= 2 {
                        sourceMint = mints[0]
                        destinationMint = mints[1]
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views
struct MintPickerRow: View {
    let mint: Mint
    let balance: Int
    
    var body: some View {
        HStack {
            Text(mint.displayName)
            Spacer()
            Text("\(balance) sats")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}