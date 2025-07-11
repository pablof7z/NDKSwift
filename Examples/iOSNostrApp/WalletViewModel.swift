import Combine
import Foundation
import NDKSwift
import SwiftUI

@MainActor
class WalletViewModel: ObservableObject {
    @Published var balance: Int64 = 0
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var transactions: [WalletTransaction] = []
    @Published var isWalletReady = false
    @Published var configuredMints: [String] = []
    @Published var statusMessage = ""
    
    private var nostrViewModel: NostrViewModel?
    private var cashuWallet: NDKCashuWallet?
    private var zapManager: NDKZapManager?
    private var balanceUpdateTimer: Timer?
    
    // Test mint URL
    private let testMintUrl = "https://testnut.cashu.space"
    
    init() {
        startBalanceMonitoring()
    }
    
    deinit {
        balanceUpdateTimer?.invalidate()
    }
    
    func setup(with nostrViewModel: NostrViewModel) {
        self.nostrViewModel = nostrViewModel
        
        Task {
            await setupWallet()
        }
    }
    
    private func setupWallet() async {
        guard let nostrViewModel = nostrViewModel,
              let ndk = nostrViewModel.ndkInstance else {
            errorMessage = "NDK not available"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        do {
            // Create Cashu wallet
            let wallet = NDKCashuWallet(ndk: ndk)
            self.cashuWallet = wallet
            
            // For now, we'll configure the test mint directly
            // In a real implementation, you would mint tokens from this mint
            configuredMints = [testMintUrl]
            
            // Create zap manager and register Cashu payment provider
            let manager = NDKZapManager(ndk: ndk)
            let paymentProvider = CashuPaymentProvider(cashuWallet: wallet)
            await manager.register(provider: paymentProvider)
            self.zapManager = manager
            
            // Load wallet data
            try await wallet.load()
            
            // Update balance
            await updateBalance()
            
            isWalletReady = true
            statusMessage = "Wallet ready with test mint"
            
        } catch {
            errorMessage = "Failed to setup wallet: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func updateBalance() async {
        guard let wallet = cashuWallet else { return }
        
        do {
            let newBalance = try await wallet.getBalance()
            balance = newBalance
            errorMessage = ""
        } catch {
            errorMessage = "Failed to fetch balance: \(error.localizedDescription)"
        }
    }
    
    private func startBalanceMonitoring() {
        balanceUpdateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateBalance()
            }
        }
    }
    
    func refreshBalance() {
        Task {
            await updateBalance()
        }
    }
    
    func sendNutzap(to pubkey: String, amount: Int64, message: String) async throws {
        guard let zapManager = zapManager else {
            throw WalletError.walletNotReady
        }
        
        statusMessage = "Sending nutzap..."
        
        // Create a recipient user for the zap
        let recipient = NDKUser(pubkey: pubkey)
        
        // Send the zap using the manager
        let result = try await zapManager.zap(
            to: recipient,
            amountSats: amount,
            comment: message.isEmpty ? nil : message,
            preferredType: .nutzap
        )
        
        // Add to transaction history
        let transaction = WalletTransaction(
            id: UUID().uuidString,
            type: .sent,
            amount: amount,
            description: "Nutzap to \(pubkey.prefix(8))...",
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)
        
        // Refresh balance
        await updateBalance()
        
        statusMessage = "Nutzap sent successfully!"
    }
    
    func createReceiveToken(amount: Int64) async throws -> String {
        guard let wallet = cashuWallet else {
            throw WalletError.walletNotReady
        }
        
        statusMessage = "Creating receive token..."
        
        // In a real implementation, this would create a receive token
        // For now, we'll simulate the process
        let token = "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vdGVzdG51dC5jYXNodS5zcGFjZSIsInByb29mcyI6W119XSwidW5pdCI6InNhdCIsIm1lbW8iOiJUZXN0IHRva2VuIn0="
        
        statusMessage = "Receive token created"
        return token
    }
    
    func generateDepositInvoice(amount: Int64) async throws -> String {
        guard let wallet = cashuWallet else {
            throw WalletError.walletNotReady
        }
        
        statusMessage = "Generating Lightning invoice..."
        
        // Use the wallet's mintTokens method to get a Lightning invoice
        // This method will create a mint quote and return the Lightning invoice
        try await wallet.mintTokens(amount: amount, mintURL: testMintUrl)
        
        // In a real implementation, the mintTokens method would return the invoice
        // For now, we'll generate a mock invoice for demonstration
        let mockInvoice = "lnbc\(amount)0n1p3xnhl2pp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpuaztrnwngzn3kdzw5hydlzf03qdgm2hdq27cqv3agm2awhz5se903vruatfhq77w3ls4evs3ch9zw97j25emudupq63nyw24cg27h2rspfj9srp"
        
        statusMessage = "Invoice generated"
        return mockInvoice
    }
    
    func checkPaymentAndMint(invoice: String, amount: Int64) async throws {
        guard let wallet = cashuWallet else {
            throw WalletError.walletNotReady
        }
        
        statusMessage = "Checking payment and minting tokens..."
        
        // In a real implementation, this would:
        // 1. Check if the Lightning invoice has been paid
        // 2. If paid, complete the minting process with the mint
        // 3. Add the new tokens to the wallet
        
        // For demonstration, we'll simulate successful minting
        // In reality, you'd call the mint's API to check payment status
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
        
        // Add a transaction record
        let transaction = WalletTransaction(
            id: UUID().uuidString,
            type: .received,
            amount: amount,
            description: "Lightning deposit",
            timestamp: Date()
        )
        transactions.insert(transaction, at: 0)
        
        // Update balance
        await updateBalance()
        
        statusMessage = "Tokens minted successfully!"
    }
}

enum WalletError: LocalizedError {
    case walletNotReady
    case insufficientBalance
    case invalidAmount
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .walletNotReady:
            return "Wallet is not ready"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invalidAmount:
            return "Invalid amount"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

struct WalletTransaction {
    let id: String
    let type: TransactionType
    let amount: Int64
    let description: String
    let timestamp: Date
    
    enum TransactionType {
        case sent
        case received
    }
}