import SwiftUI
import NDKSwift

// This file is kept for backward compatibility but redirects to OlasWalletView
struct WalletView: View {
    @ObservedObject var walletManager: OlasWalletManager
    let nostrManager: NostrManager
    
    var body: some View {
        OlasWalletView(walletManager: walletManager, nostrManager: nostrManager)
    }
}