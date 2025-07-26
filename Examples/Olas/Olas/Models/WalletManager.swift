import Foundation
import NDKSwift
import CashuSwift
import SwiftUI

@MainActor
class OlasWalletManager: ObservableObject {
    @Published var activeWallet: NIP60Wallet?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentBalance: Int64 = 0
    @Published var mintURLs: [String] = []
    var isWalletConfigured: Bool {
        return activeWallet != nil && !mintURLs.isEmpty
    }
    
    // Simplified transaction type for UI
    @Published var recentTransactions: [(id: String, type: TransactionType, amount: Int64, description: String, timestamp: Date)] = []
    
    enum TransactionType {
        case sent
        case received
        case zapped
    }
    
    private let nostrManager: NostrManager
    private var walletEventTask: Task<Void, Never>?
    
    init(nostrManager: NostrManager) {
        self.nostrManager = nostrManager
    }
    
    deinit {
        walletEventTask?.cancel()
    }
    
    // MARK: - Wallet Operations
    
    /// Load or create wallet for current user
    func loadWallet() async throws {
        print("💰 OlasWalletManager.loadWallet() called")
        guard nostrManager.isAuthenticated else {
            throw WalletError.notAuthenticated
        }
        
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Create or load NIP60 wallet
            let wallet = try NIP60Wallet(ndk: ndk)
            activeWallet = wallet
            
            // Initialize with default mint if needed
            if mintURLs.isEmpty {
                mintURLs = ["https://mint.minibits.cash/Bitcoin"]
            }
            
            // Start monitoring wallet events
            await startWalletEventMonitoring()
            
            // Load initial balance
            await updateBalance()
            
            print("💰 Wallet loaded successfully")
        } catch {
            self.error = error
            print("💰 Error loading wallet: \(error)")
            throw error
        }
    }
    
    /// Send sats to another user
    func sendSats(to pubkey: String, amount: Int64, comment: String?) async throws {
        guard activeWallet != nil else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Create a lightning invoice request
        // In a real implementation, this would use wallet.requestInvoice or similar
        print("💰 Sending \(amount) sats to \(pubkey)")
        
        // Add to transactions
        let transaction = (
            id: UUID().uuidString,
            type: TransactionType.sent,
            amount: amount,
            description: comment ?? "Sent to \(pubkey.prefix(8))...",
            timestamp: Date()
        )
        recentTransactions.insert(transaction, at: 0)
        
        // Update balance
        currentBalance -= amount
    }
    
    /// Zap an event
    func zapEvent(_ event: NDKEvent, amount: Int64, comment: String?) async throws {
        guard activeWallet != nil else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        print("💰 Zapping event \(event.id) with \(amount) sats")
        
        // Add to transactions
        let transaction = (
            id: UUID().uuidString,
            type: TransactionType.zapped,
            amount: amount,
            description: comment ?? "Zapped a post",
            timestamp: Date()
        )
        recentTransactions.insert(transaction, at: 0)
        
        // Update balance
        currentBalance -= amount
    }
    
    /// Generate a lightning invoice to receive payment
    func generateInvoice(amount: Int64, description: String?) async throws -> String {
        guard activeWallet != nil else {
            throw WalletError.walletNotConfigured
        }
        
        // In a real implementation, this would generate an actual invoice
        // For now, return a mock invoice
        return "lnbc\(amount)n1pn0tjwxpp5..." // Mock invoice
    }
    
    // MARK: - Private Methods
    
    private func startWalletEventMonitoring() async {
        walletEventTask?.cancel()
        
        guard let ndk = nostrManager.ndk else { return }
        
        walletEventTask = Task {
            // Monitor for wallet events
            // In a real implementation, this would monitor proper wallet event kinds
            // For now, we'll just monitor for zap receipts
            guard let userPubkey = ndk.signer?.pubkey else { return }
            
            let filter = NDKFilter(
                authors: [userPubkey],
                kinds: [EventKind.zap]
            )
            
            do {
                for await event in await ndk.observe(filters: [filter]) {
                    await handleWalletEvent(event)
                }
            } catch {
                print("💰 Error monitoring wallet events: \(error)")
            }
        }
    }
    
    private func handleWalletEvent(_ event: NDKEvent) async {
        print("💰 Received wallet event: kind \(event.kind)")
        
        // Handle different wallet event types
        switch event.kind {
        case EventKind.zap:
            // Handle zap receipt
            // In a real implementation, parse the zap receipt to update balance
            await updateBalance()
        default:
            break
        }
    }
    
    private func updateBalance() async {
        // In a real implementation, this would query the wallet balance
        // For now, use a mock balance
        currentBalance = 100000 // 100k sats
    }
}

// MARK: - Error Types

enum WalletError: LocalizedError {
    case notAuthenticated
    case ndkNotInitialized
    case walletNotConfigured
    case insufficientBalance
    case invoiceGenerationFailed
    case paymentFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .ndkNotInitialized:
            return "NDK not initialized"
        case .walletNotConfigured:
            return "Wallet not configured"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invoiceGenerationFailed:
            return "Failed to generate invoice"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        }
    }
}

// MARK: - NWC Response (simplified)

private struct NWCResponse: Codable {
    let result_type: String
    let error: NWCError?
    let result: NWCResult?
}

private struct NWCError: Codable {
    let code: String
    let message: String
}

private struct NWCResult: Codable {
    let preimage: String?
}