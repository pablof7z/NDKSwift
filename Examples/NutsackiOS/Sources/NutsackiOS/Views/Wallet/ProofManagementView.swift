import SwiftUI
import SwiftData

struct ProofManagementView: View {
    let wallet: CashuWallet
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedMint: Mint?
    @State private var showConsolidation = false
    @State private var consolidationAmount = ""
    @State private var isConsolidating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var selectedMintTokens: [CashuToken] {
        if let mint = selectedMint {
            return wallet.tokens.filter { $0.mint == mint && $0.state == .unspent }
        }
        return wallet.tokens.filter { $0.state == .unspent }
    }
    
    var tokensByDenomination: [(amount: Int, count: Int)] {
        Dictionary(grouping: selectedMintTokens, by: { $0.amount })
            .map { (amount: $0.key, count: $0.value.count) }
            .sorted { $0.amount < $1.amount }
    }
    
    var totalProofs: Int {
        selectedMintTokens.count
    }
    
    var totalValue: Int {
        selectedMintTokens.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Mint selector
                if wallet.mints.count > 1 {
                    Section {
                        Picker("Mint", selection: $selectedMint) {
                            Text("All Mints").tag(nil as Mint?)
                            ForEach(wallet.mints) { mint in
                                Text(mint.displayName).tag(mint as Mint?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                // Summary
                Section {
                    LabeledContent("Total Proofs", value: "\(totalProofs)")
                    LabeledContent("Total Value", value: "\(totalValue) sats")
                    
                    if totalProofs > 0 {
                        LabeledContent("Average Denomination") {
                            Text("\(totalValue / totalProofs) sats")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Summary")
                }
                
                // Denomination breakdown
                Section {
                    ForEach(tokensByDenomination, id: \.amount) { item in
                        HStack {
                            Text("\(item.amount) sat")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("×\(item.count)")
                                .foregroundStyle(.secondary)
                            Text("= \(item.amount * item.count) sats")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Denominations")
                } footer: {
                    Text("Smaller denominations provide better privacy but increase proof count")
                }
                
                // Proof health
                Section {
                    ProofHealthIndicator(tokens: selectedMintTokens)
                } header: {
                    Text("Proof Health")
                }
                
                // Actions
                Section {
                    Button(action: { showConsolidation = true }) {
                        Label("Consolidate Proofs", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(totalProofs < 2)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Consolidation combines multiple small proofs into larger ones to reduce proof count")
                }
            }
            .navigationTitle("Proof Management")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .sheet(isPresented: $showConsolidation) {
                ProofConsolidationView(
                    wallet: wallet,
                    mint: selectedMint,
                    currentProofCount: totalProofs,
                    totalValue: totalValue
                )
            }
        }
    }
}

// MARK: - Proof Health Indicator
struct ProofHealthIndicator: View {
    let tokens: [CashuToken]
    
    var dleqStatus: (verified: Int, unverified: Int, unknown: Int) {
        let verified = tokens.filter { $0.dleqVerified == true }.count
        let unverified = tokens.filter { $0.dleqVerified == false }.count
        let unknown = tokens.filter { $0.dleqVerified == nil }.count
        return (verified, unverified, unknown)
    }
    
    var fragmentationScore: Double {
        guard !tokens.isEmpty else { return 0 }
        let avgDenomination = Double(tokens.reduce(0) { $0 + $1.amount }) / Double(tokens.count)
        // Good if average denomination is above 100 sats
        return min(avgDenomination / 100.0, 1.0)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // DLEQ verification status
            HStack {
                Text("Authenticity")
                Spacer()
                DLEQStatusBar(status: dleqStatus)
            }
            
            // Fragmentation
            HStack {
                Text("Fragmentation")
                Spacer()
                FragmentationIndicator(score: fragmentationScore)
            }
        }
    }
}

struct DLEQStatusBar: View {
    let status: (verified: Int, unverified: Int, unknown: Int)
    
    var total: Int {
        status.verified + status.unverified + status.unknown
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        if status.verified > 0 {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: geometry.size.width * CGFloat(status.verified) / CGFloat(total))
                        }
                        if status.unverified > 0 {
                            Rectangle()
                                .fill(Color.yellow)
                                .frame(width: geometry.size.width * CGFloat(status.unverified) / CGFloat(total))
                        }
                        if status.unknown > 0 {
                            Rectangle()
                                .fill(Color.gray)
                                .frame(width: geometry.size.width * CGFloat(status.unknown) / CGFloat(total))
                        }
                    }
                }
                .frame(width: 100, height: 8)
                .cornerRadius(4)
                
                Text("\(status.verified)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No proofs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FragmentationIndicator: View {
    let score: Double // 0-1, where 1 is good (not fragmented)
    
    var color: Color {
        if score > 0.7 { return .green }
        else if score > 0.3 { return .yellow }
        else { return .red }
    }
    
    var label: String {
        if score > 0.7 { return "Good" }
        else if score > 0.3 { return "Moderate" }
        else { return "High" }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Proof Consolidation View
struct ProofConsolidationView: View {
    let wallet: CashuWallet
    let mint: Mint?
    let currentProofCount: Int
    let totalValue: Int
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var targetDenominations = ""
    @State private var isConsolidating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var suggestedDenominations: String {
        // Suggest power of 2 denominations
        var remaining = totalValue
        var denominations: [Int] = []
        var power = 1
        
        while power * 2 <= remaining {
            power *= 2
        }
        
        while remaining > 0 && power >= 1 {
            if remaining >= power {
                denominations.append(power)
                remaining -= power
            } else {
                power /= 2
            }
        }
        
        return denominations.map(String.init).joined(separator: ", ")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Current Proofs", value: "\(currentProofCount)")
                    LabeledContent("Total Value", value: "\(totalValue) sats")
                } header: {
                    Text("Current State")
                }
                
                Section {
                    TextField("Target denominations (e.g., 1024, 512, 256)", text: $targetDenominations)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                } header: {
                    Text("Target Denominations")
                } footer: {
                    Text("Suggested: \(suggestedDenominations)")
                }
                
                Section {
                    Button(action: consolidate) {
                        if isConsolidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Consolidate")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(targetDenominations.isEmpty || isConsolidating)
                }
            }
            .navigationTitle("Consolidate Proofs")
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
            .onAppear {
                targetDenominations = suggestedDenominations
            }
        }
    }
    
    private func consolidate() {
        // Parse target denominations
        let denominations = targetDenominations
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        
        guard !denominations.isEmpty else {
            errorMessage = "Invalid denominations"
            showError = true
            return
        }
        
        isConsolidating = true
        
        Task {
            do {
                // Note: This would require implementing proof consolidation in NDKCashuWallet
                // For now, we show a message explaining the limitation
                await MainActor.run {
                    errorMessage = "Proof consolidation is not yet implemented in NDKCashuWallet. This feature will be added in a future update."
                    showError = true
                    isConsolidating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isConsolidating = false
                }
            }
        }
    }
}