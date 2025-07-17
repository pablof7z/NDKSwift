import SwiftUI

struct BalanceCard: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WalletManager.self) private var walletManager
    
    let balance: Int
    
    @State private var convertedBalance: String = ""
    @State private var mintBalances: [(mint: String, balance: Int64, percentage: Double)] = []
    @State private var isLoadingMints = false
    
    private let mintColors: [Color] = [
        Color(red: 0.98, green: 0.54, blue: 0.13), // Orange
        Color(red: 0.13, green: 0.59, blue: 0.95), // Blue
        Color(red: 0.96, green: 0.26, blue: 0.21), // Red
        Color(red: 0.30, green: 0.69, blue: 0.31), // Green
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Balance display - centered
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBalance(balance))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("sats")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                // Fiat conversion
                if appState.preferredConversionUnit != .sat && !convertedBalance.isEmpty && convertedBalance != "..." {
                    Text(convertedBalance)
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                        .animation(.default, value: convertedBalance)
                }
            }
            
            // Mini pie chart
            if !mintBalances.isEmpty && mintBalances.count > 1 {
                MiniPieChart(mintBalances: mintBalances)
                    .frame(width: 80, height: 80)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .task(id: balance) {
            await convert()
            await loadMintBalances()
        }
        .task {
            await loadMintBalances()
        }
        .onChange(of: appState.preferredConversionUnit) { _, _ in
            Task {
                await convert()
            }
        }
        .onChange(of: appState.exchangeRates) { _, _ in
            Task {
                await convert()
            }
        }
    }
    
    private func formatBalance(_ sats: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? String(sats)
    }
    
    @MainActor
    private func convert() async {
        convertedBalance = "..."
        
        guard let prices = appState.exchangeRates else {
            convertedBalance = ""
            return
        }
        
        let bitcoinPrice: Int
        switch appState.preferredConversionUnit {
        case .usd: bitcoinPrice = prices.usd
        case .eur: bitcoinPrice = prices.eur
        case .btc:
            let btcAmount = Double(balance) / 100_000_000.0
            convertedBalance = String(format: "%.8f BTC", btcAmount)
            return
        case .sat:
            convertedBalance = ""
            return
        }
        
        let bitcoinAmount = Double(balance) / 100_000_000.0
        let fiatValue = bitcoinAmount * Double(bitcoinPrice)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.preferredConversionUnit.rawValue.uppercased()
        
        convertedBalance = formatter.string(from: NSNumber(value: fiatValue)) ?? ""
    }
    
    private func loadMintBalances() async {
        isLoadingMints = true
        defer { isLoadingMints = false }
        
        guard let wallet = walletManager.activeWallet else { return }
        
        let mintStrings = await wallet.mints.getMintURLs()
        let mints = mintStrings.compactMap { URL(string: $0) }
        var balances: [(mint: String, balance: Int64, percentage: Double)] = []
        var totalBalance: Int64 = 0
        
        // Get balance for each mint
        for url in mints {
            let balance = await wallet.getBalance(mint: url)
            if balance > 0 {
                balances.append((mint: url.absoluteString, balance: balance, percentage: 0))
                totalBalance += balance
            }
        }
        
        // Calculate percentages
        if totalBalance > 0 {
            balances = balances.map { item in
                let percentage = (Double(item.balance) / Double(totalBalance)) * 100
                return (mint: item.mint, balance: item.balance, percentage: percentage)
            }
        }
        
        // Sort by balance (largest first) and take top 4
        balances.sort { $0.balance > $1.balance }
        if balances.count > 4 {
            balances = Array(balances.prefix(4))
        }
        
        await MainActor.run {
            self.mintBalances = balances
        }
    }
}

struct MiniPieChart: View {
    let mintBalances: [(mint: String, balance: Int64, percentage: Double)]
    
    private let mintColors: [Color] = [
        Color(red: 0.98, green: 0.54, blue: 0.13), // Orange
        Color(red: 0.13, green: 0.59, blue: 0.95), // Blue
        Color(red: 0.96, green: 0.26, blue: 0.21), // Red
        Color(red: 0.30, green: 0.69, blue: 0.31), // Green
    ]
    
    var body: some View {
        ZStack {
            ForEach(Array(mintBalances.enumerated()), id: \.element.mint) { index, item in
                Circle()
                    .trim(from: startAngle(for: index), to: endAngle(for: index))
                    .stroke(
                        mintColors[index % mintColors.count],
                        style: StrokeStyle(lineWidth: 20, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
            
            // Center text showing number of mints
            Text("\(mintBalances.count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private func startAngle(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        
        let previousAngles = mintBalances[0..<index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0)
        }
        
        return previousAngles
    }
    
    private func endAngle(for index: Int) -> CGFloat {
        let cumulativeAngle = mintBalances[0...index].reduce(0) { sum, item in
            sum + (item.percentage / 100.0)
        }
        
        return cumulativeAngle
    }
}

