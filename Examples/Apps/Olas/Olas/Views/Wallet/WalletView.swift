import SwiftUI
import NDKSwift

// This file is kept for backward compatibility but redirects to OlasWalletView
struct WalletView: View {
    @ObservedObject var walletManager: OlasWalletManager
    
    var body: some View {
        OlasWalletView(walletManager: walletManager)
    }
}