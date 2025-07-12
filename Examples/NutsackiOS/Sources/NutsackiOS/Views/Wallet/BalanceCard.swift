import SwiftUI

struct BalanceCard: View {
    @EnvironmentObject private var appState: AppState
    
    let balance: Int
    
    @State private var convertedBalance: String = ""
    
    private let cardWidth: CGFloat = 330
    private let cardHeight: CGFloat = 150
    
    var body: some View {
        ZStack {
            // Card background with gradient and border
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color(white: 0.12), Color.black]),
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: cardWidth * 3
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                )
                .frame(width: cardWidth, height: cardHeight)
            
            // Content
            VStack(alignment: .leading) {
                HStack {
                    Text(balance == 0 ? "-" : formatBalance(balance))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("sats")
                        .font(.title)
                        .foregroundColor(Color.gray)
                }
                
                Spacer()
                
                // Fiat conversion
                if appState.preferredConversionUnit != .sat {
                    HStack {
                        Text(convertedBalance)
                        Spacer()
                    }
                    .opacity(0.7)
                    .animation(.default, value: convertedBalance)
                }
            }
            .padding(24)
            .frame(width: cardWidth, height: cardHeight)
        }
        .task(id: balance) {
            await convert()
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
}

// MARK: - Wallet Selector
struct WalletSelector: View {
    let wallets: [CashuWallet]
    @Binding var selectedWallet: CashuWallet?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(wallets) { wallet in
                    WalletChip(
                        wallet: wallet,
                        isSelected: selectedWallet?.walletID == wallet.walletID
                    ) {
                        selectedWallet = wallet
                    }
                }
            }
        }
    }
}

struct WalletChip: View {
    let wallet: CashuWallet
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "wallet.pass")
                    .font(.caption)
                Text(wallet.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.orange : Color.secondary.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(20)
        }
    }
}