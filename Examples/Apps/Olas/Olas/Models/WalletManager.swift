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
    @Published var mintBalances: [String: Int64] = [:]
    @Published var activeTokens: [Token] = []
    @Published var pendingInvoices: [String: (amount: Int64, description: String, expiry: Date)] = [:]
    
    var isWalletConfigured: Bool {
        return activeWallet != nil && !mintURLs.isEmpty
    }
    
    // Enhanced transaction with more details
    @Published var recentTransactions: [WalletTransaction] = []
    
    enum TransactionType {
        case sent
        case received
        case zapped
        case minted
        case melted
        case swapped
    }
    
    struct WalletTransaction: Identifiable {
        let id = UUID()
        let type: TransactionType
        let amount: Int64
        let description: String
        let timestamp: Date
        let mint: String?
        let invoice: String?
        let fee: Int64?
        let status: TransactionStatus
        
        enum TransactionStatus {
            case pending
            case completed
            case failed
        }
    }
    
    private let nostrManager: NostrManager
    private var walletEventTask: Task<Void, Never>?
    private var cashuWallet: Wallet?
    private var currentMint: Mint?
    
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
            
            // Initialize with default mints if needed
            if mintURLs.isEmpty {
                mintURLs = [
                    "https://mint.minibits.cash/Bitcoin",
                    "https://testnut.cashu.space",
                    "https://8333.space:3338"
                ]
            }
            
            // Initialize Cashu wallet with first mint
            await initializeCashuWallet()
            
            // Start monitoring wallet events
            await startWalletEventMonitoring()
            
            // Load balances from all mints
            await updateAllBalances()
            
            // Load existing tokens from storage
            await loadStoredTokens()
            
            print("💰 Wallet loaded successfully with \(activeTokens.count) tokens")
        } catch {
            self.error = error
            print("💰 Error loading wallet: \(error)")
            throw error
        }
    }
    
    /// Initialize Cashu wallet with primary mint
    private func initializeCashuWallet() async {
        guard let primaryMintURL = mintURLs.first,
              let url = URL(string: primaryMintURL) else { return }
        
        do {
            currentMint = Mint(url: url)
            cashuWallet = Wallet(mint: currentMint!)
            
            // Get mint info
            if let mintInfo = try? await currentMint?.getInfo() {
                print("💰 Connected to mint: \(mintInfo.name ?? primaryMintURL)")
            }
        } catch {
            print("💰 Failed to initialize Cashu wallet: \(error)")
        }
    }
    
    /// Add a new mint
    func addMint(_ mintURL: String) async throws {
        guard let url = URL(string: mintURL) else {
            throw WalletError.invalidMintURL
        }
        
        // Test connection to mint
        let testMint = Mint(url: url)
        _ = try await testMint.getInfo()
        
        // Add to list if successful
        if !mintURLs.contains(mintURL) {
            mintURLs.append(mintURL)
            await updateMintBalance(mintURL)
        }
    }
    
    /// Remove a mint
    func removeMint(_ mintURL: String) async throws {
        // Check if we have tokens from this mint
        let tokensFromMint = activeTokens.filter { $0.mint == mintURL }
        if !tokensFromMint.isEmpty {
            throw WalletError.cannotRemoveMintWithTokens
        }
        
        mintURLs.removeAll { $0 == mintURL }
        mintBalances.removeValue(forKey: mintURL)
    }
    
    /// Send sats via Lightning invoice
    func payInvoice(_ invoice: String, comment: String?) async throws {
        guard let wallet = cashuWallet,
              let mint = currentMint else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Parse invoice to get amount
            let invoiceAmount = try await getInvoiceAmount(invoice)
            
            guard currentBalance >= invoiceAmount else {
                throw WalletError.insufficientBalance
            }
            
            // Get quote for melting tokens
            let meltQuote = try await mint.getMeltQuote(request: invoice)
            let totalAmount = invoiceAmount + (meltQuote.feeReserve ?? 0)
            
            // Select tokens to spend
            let tokensToSpend = selectTokensForAmount(totalAmount)
            guard !tokensToSpend.isEmpty else {
                throw WalletError.insufficientTokens
            }
            
            // Melt tokens to pay invoice
            let meltResponse = try await wallet.melt(
                quote: meltQuote.quote,
                inputs: tokensToSpend
            )
            
            // Remove spent tokens
            activeTokens.removeAll { token in
                tokensToSpend.contains { $0.id == token.id }
            }
            
            // Add change tokens if any
            if let change = meltResponse.change, !change.isEmpty {
                activeTokens.append(contentsOf: change)
            }
            
            // Record transaction
            let transaction = WalletTransaction(
                type: .sent,
                amount: invoiceAmount,
                description: comment ?? "Lightning payment",
                timestamp: Date(),
                mint: mint.url.absoluteString,
                invoice: invoice,
                fee: meltQuote.feeReserve,
                status: .completed
            )
            recentTransactions.insert(transaction, at: 0)
            
            // Update balance
            await updateAllBalances()
            
            print("💰 Successfully paid \(invoiceAmount) sats")
        } catch {
            print("💰 Payment failed: \(error)")
            throw error
        }
    }
    
    /// Send ecash tokens directly
    func sendEcash(amount: Int64, comment: String?) async throws -> String {
        guard cashuWallet != nil else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Select tokens for the amount
            let tokensToSend = selectTokensForAmount(amount)
            guard !tokensToSend.isEmpty else {
                throw WalletError.insufficientTokens
            }
            
            // Create cashu token string
            let tokenString = try encodeCashuToken(tokensToSend)
            
            // Remove sent tokens from wallet
            activeTokens.removeAll { token in
                tokensToSend.contains { $0.id == token.id }
            }
            
            // Record transaction
            let transaction = WalletTransaction(
                type: .sent,
                amount: amount,
                description: comment ?? "Sent ecash",
                timestamp: Date(),
                mint: tokensToSend.first?.mint,
                invoice: nil,
                fee: 0,
                status: .completed
            )
            recentTransactions.insert(transaction, at: 0)
            
            // Update balance
            await updateAllBalances()
            
            return tokenString
        } catch {
            print("💰 Failed to create ecash token: \(error)")
            throw error
        }
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
        guard let mint = currentMint else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Get mint quote for the amount
            let mintQuote = try await mint.getMintQuote(amount: UInt64(amount))
            
            // Store pending invoice
            pendingInvoices[mintQuote.quote] = (
                amount: amount,
                description: description ?? "Olas payment",
                expiry: Date().addingTimeInterval(mintQuote.expiry ?? 3600)
            )
            
            // Start monitoring for payment
            Task {
                await monitorInvoicePayment(quote: mintQuote.quote, amount: amount)
            }
            
            return mintQuote.request
        } catch {
            print("💰 Failed to generate invoice: \(error)")
            throw error
        }
    }
    
    /// Receive ecash tokens
    func receiveEcash(_ tokenString: String) async throws {
        guard let wallet = cashuWallet else {
            throw WalletError.walletNotConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Decode token string
            let receivedTokens = try decodeCashuToken(tokenString)
            
            // Verify tokens are valid and not already spent
            let validTokens = try await wallet.receive(tokens: receivedTokens)
            
            // Add to active tokens
            activeTokens.append(contentsOf: validTokens)
            
            // Calculate total amount
            let totalAmount = validTokens.reduce(0) { $0 + $1.amount }
            
            // Record transaction
            let transaction = WalletTransaction(
                type: .received,
                amount: Int64(totalAmount),
                description: "Received ecash",
                timestamp: Date(),
                mint: validTokens.first?.mint,
                invoice: nil,
                fee: 0,
                status: .completed
            )
            recentTransactions.insert(transaction, at: 0)
            
            // Update balance
            await updateAllBalances()
            
            // Store tokens
            await storeTokens()
            
            print("💰 Successfully received \(totalAmount) sats")
        } catch {
            print("💰 Failed to receive ecash: \(error)")
            throw error
        }
    }
    
    /// Monitor invoice payment
    private func monitorInvoicePayment(quote: String, amount: Int64) async {
        guard let mint = currentMint,
              let wallet = cashuWallet else { return }
        
        // Poll for payment (in production, use websocket)
        for _ in 0..<60 { // Check for 5 minutes
            do {
                // Try to mint tokens from the paid invoice
                let tokens = try await wallet.mint(quote: quote, amount: UInt64(amount))
                
                // Payment successful
                activeTokens.append(contentsOf: tokens)
                
                // Remove from pending
                pendingInvoices.removeValue(forKey: quote)
                
                // Record transaction
                let transaction = WalletTransaction(
                    type: .received,
                    amount: amount,
                    description: "Lightning payment received",
                    timestamp: Date(),
                    mint: mint.url.absoluteString,
                    invoice: nil,
                    fee: 0,
                    status: .completed
                )
                
                await MainActor.run {
                    recentTransactions.insert(transaction, at: 0)
                }
                
                // Update balance
                await updateAllBalances()
                
                // Store tokens
                await storeTokens()
                
                print("💰 Invoice paid: \(amount) sats received")
                return
            } catch {
                // Not paid yet, wait and retry
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
        
        // Invoice expired
        await MainActor.run {
            pendingInvoices.removeValue(forKey: quote)
        }
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
    
    private func updateAllBalances() async {
        var totalBalance: Int64 = 0
        
        // Calculate balance from active tokens
        for token in activeTokens {
            totalBalance += Int64(token.amount)
        }
        
        currentBalance = totalBalance
        
        // Update balance per mint
        for mintURL in mintURLs {
            await updateMintBalance(mintURL)
        }
    }
    
    private func updateMintBalance(_ mintURL: String) async {
        let mintTokens = activeTokens.filter { $0.mint == mintURL }
        let mintBalance = mintTokens.reduce(0) { $0 + Int64($1.amount) }
        
        await MainActor.run {
            mintBalances[mintURL] = mintBalance
        }
    }
    
    /// Select tokens for a specific amount
    private func selectTokensForAmount(_ amount: Int64) -> [Token] {
        var selectedTokens: [Token] = []
        var currentAmount: Int64 = 0
        
        // Sort tokens by amount (descending) for optimal selection
        let sortedTokens = activeTokens.sorted { $0.amount > $1.amount }
        
        for token in sortedTokens {
            if currentAmount >= amount {
                break
            }
            selectedTokens.append(token)
            currentAmount += Int64(token.amount)
        }
        
        return currentAmount >= amount ? selectedTokens : []
    }
    
    /// Get invoice amount from bolt11
    private func getInvoiceAmount(_ invoice: String) async throws -> Int64 {
        // In production, use proper bolt11 parsing
        // For now, extract amount from invoice string
        if let match = invoice.range(of: #"lnbc(\d+)"#, options: .regularExpression) {
            let amountString = String(invoice[match]).replacingOccurrences(of: "lnbc", with: "")
            if let amount = Int64(amountString) {
                return amount * 1000 // Convert to millisats
            }
        }
        throw WalletError.invalidInvoice
    }
    
    /// Encode tokens to cashu token string
    private func encodeCashuToken(_ tokens: [Token]) throws -> String {
        // In production, use proper cashu token encoding
        // For now, create a simple representation
        let tokenData = tokens.map { token in
            ["amount": token.amount, "C": token.C, "id": token.id, "secret": token.secret]
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: tokenData)
        return "cashuA" + jsonData.base64EncodedString()
    }
    
    /// Decode cashu token string
    private func decodeCashuToken(_ tokenString: String) throws -> [Token] {
        // In production, use proper cashu token decoding
        guard tokenString.hasPrefix("cashu") else {
            throw WalletError.invalidToken
        }
        
        // For now, return empty array
        return []
    }
    
    /// Store tokens securely
    private func storeTokens() async {
        // In production, store encrypted in keychain
        // For now, just log
        print("💰 Storing \(activeTokens.count) tokens")
    }
    
    /// Load stored tokens
    private func loadStoredTokens() async {
        // In production, load from keychain
        // For now, start with empty tokens
        activeTokens = []
    }
}

// MARK: - Error Types

enum WalletError: LocalizedError {
    case notAuthenticated
    case ndkNotInitialized
    case walletNotConfigured
    case insufficientBalance
    case insufficientTokens
    case invoiceGenerationFailed
    case paymentFailed(String)
    case invalidMintURL
    case cannotRemoveMintWithTokens
    case invalidInvoice
    case invalidToken
    case mintConnectionFailed
    
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
        case .insufficientTokens:
            return "Not enough tokens for this amount"
        case .invoiceGenerationFailed:
            return "Failed to generate invoice"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .invalidMintURL:
            return "Invalid mint URL"
        case .cannotRemoveMintWithTokens:
            return "Cannot remove mint with active tokens"
        case .invalidInvoice:
            return "Invalid lightning invoice"
        case .invalidToken:
            return "Invalid ecash token"
        case .mintConnectionFailed:
            return "Failed to connect to mint"
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