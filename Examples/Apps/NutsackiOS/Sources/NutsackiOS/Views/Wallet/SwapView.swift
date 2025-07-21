import SwiftUI
import SwiftData
import NDKSwift

struct SwapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var walletManager
    
    @State private var sourceMint: MintBalance?
    @State private var destinationMint: MintBalance?
    @State private var isSwapping = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var transferResult: TransferResult?
    
    // Fee estimation
    @State private var estimatedFees: (lightningFee: Int64, inputFee: Int64, totalFee: Int64)?
    @State private var isEstimatingFees = false
    @State private var mintBalances: [MintBalance] = []
    
    // Allocation slider
    @State private var allocationPercentage: Double = 50.0
    
    var transferAmount: Int64 {
        guard let source = sourceMint, let destination = destinationMint else { return 0 }
        let totalBalance = source.balance + destination.balance
        let targetSourceBalance = Int64(Double(totalBalance) * (allocationPercentage / 100.0))
        return source.balance - targetSourceBalance
    }
    
    var canSwap: Bool {
        guard let source = sourceMint else { return false }
        guard let destination = destinationMint else { return false }
        guard source.url != destination.url else { return false }
        guard transferAmount > 0 else { return false }
        guard source.balance >= transferAmount else { return false }
        guard !isSwapping else { return false }
        return true
    }
    
    @ViewBuilder
    var allocationSection: some View {
        if let source = sourceMint, let destination = destinationMint {
            Section {
                VStack(spacing: 16) {
                    // Visual representation
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 8, height: 8)
                                Text(source.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            Text("\(Int64(Double(source.balance + destination.balance) * (allocationPercentage / 100.0))) sats")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        // Flow arrow
                        VStack {
                            Image(systemName: "arrow.right")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("\(abs(transferAmount)) sats")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack {
                                Text(destination.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 8, height: 8)
                            }
                            Text("\(Int64(Double(source.balance + destination.balance) * ((100.0 - allocationPercentage) / 100.0))) sats")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // Allocation slider
                    VStack(spacing: 8) {
                        HStack {
                            Text("0%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(allocationPercentage))% / \(100 - Int(allocationPercentage))%")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text("100%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $allocationPercentage, in: 0...100, step: 1)
                            .tint(.orange)
                    }
                }
            } header: {
                Text("Balance Allocation")
            } footer: {
                if transferAmount > 0 {
                    Text("Transfer \(transferAmount) sats from \(source.displayName) to \(destination.displayName)")
                } else if transferAmount < 0 {
                    Text("Transfer \(-transferAmount) sats from \(destination.displayName) to \(source.displayName)")
                } else {
                    Text("Balances are already allocated as desired")
                }
            }
        }
    }
    
    @ViewBuilder
    var mintPickerSection: some View {
        Section {
            Picker("From Mint", selection: $sourceMint) {
                Text("Select mint").tag(nil as MintBalance?)
                ForEach(mintBalances.filter { $0.balance > 0 }, id: \.url) { mintBalance in
                    MintBalancePickerRow(mintBalance: mintBalance)
                        .tag(mintBalance as MintBalance?)
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
                Text("Select mint").tag(nil as MintBalance?)
                ForEach(mintBalances, id: \.url) { mintBalance in
                    MintBalancePickerRow(mintBalance: mintBalance)
                        .tag(mintBalance as MintBalance?)
                }
            }
        } header: {
            Text("Select Mints")
        } footer: {
            Text("Only mints with available balance are shown as source options")
        }
    }
    
    @ViewBuilder
    var feesSection: some View {
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
                    Text("\(max(0, abs(transferAmount) - fees.totalFee)) sats")
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Estimated Fees")
            } footer: {
                Text("Actual fees may vary slightly")
            }
        }
    }
    
    @ViewBuilder
    var actionSection: some View {
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
    
    var body: some View {
        Form {
            mintPickerSection
            allocationSection
            feesSection
            actionSection
        }
        .navigationTitle("Balance Reconcile")
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
        .onChange(of: sourceMint) { _, _ in
            updateAllocationPercentage()
            estimateFees()
        }
        .onChange(of: destinationMint) { _, _ in
            updateAllocationPercentage()
            estimateFees()
        }
        .onChange(of: allocationPercentage) { _, _ in
            estimateFees()
        }
        .onAppear {
            loadMintBalances()
        }
    }
    
    
    private func swapMints() {
        let temp = sourceMint
        sourceMint = destinationMint
        destinationMint = temp
    }
    
    private func updateAllocationPercentage() {
        guard let source = sourceMint, let destination = destinationMint else { return }
        let totalBalance = source.balance + destination.balance
        if totalBalance > 0 {
            allocationPercentage = Double(source.balance) / Double(totalBalance) * 100.0
        }
    }
    
    private func estimateFees() {
        guard abs(transferAmount) > 0,
              let source = sourceMint,
              let destination = destinationMint,
              source.url != destination.url else {
            estimatedFees = nil
            return
        }
        
        isEstimatingFees = true
        
        Task {
            do {
                let fees = try await walletManager.estimateTransferFees(
                    amount: abs(transferAmount),
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
        guard canSwap else { return }
        
        let actualTransferAmount = abs(transferAmount)
        let actualSource = transferAmount > 0 ? sourceMint! : destinationMint!
        let actualDestination = transferAmount > 0 ? destinationMint! : sourceMint!
        
        isSwapping = true
        
        Task {
            do {
                let result = try await walletManager.transferBetweenMints(
                    amount: actualTransferAmount,
                    fromMint: actualSource.url,
                    toMint: actualDestination.url
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
    
    private func loadMintBalances() {
        Task {
            guard let wallet = walletManager.activeWallet else { return }
            
            // Get balances by mint from the wallet
            let balancesByMint = await wallet.getBalancesByMint()
            
            // Create MintBalance objects
            let loadedMintBalances = balancesByMint.map { (mintUrl, balance) in
                MintBalance(url: URL(string: mintUrl)!, balance: balance)
            }.sorted { $0.balance > $1.balance } // Sort by balance descending
            
            await MainActor.run {
                mintBalances = loadedMintBalances
                
                // Auto-select the two mints with highest balances
                if mintBalances.count >= 2 {
                    sourceMint = mintBalances[0]
                    destinationMint = mintBalances[1]
                    updateAllocationPercentage()
                } else if mintBalances.count == 1 {
                    sourceMint = mintBalances[0]
                }
            }
        }
    }
}

// MARK: - Supporting Types
struct MintBalance: Hashable {
    let url: URL
    let balance: Int64
    
    var displayName: String {
        url.host ?? url.absoluteString
    }
}

// MARK: - Helper Views
struct MintBalancePickerRow: View {
    let mintBalance: MintBalance
    
    var body: some View {
        HStack {
            Text(mintBalance.displayName)
            Spacer()
            Text("\(mintBalance.balance) sats")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MintPickerRow: View {
    let mint: MintInfo
    let balance: Int
    
    var body: some View {
        HStack {
            Text(mint.url.host ?? mint.url.absoluteString)
            Spacer()
            Text("\(balance) sats")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}