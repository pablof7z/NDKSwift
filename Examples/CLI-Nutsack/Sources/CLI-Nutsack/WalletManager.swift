import Foundation
import NDKSwift

@MainActor
class WalletManager {
    private var ndk: NDK
    private var wallet: NDKCashuWallet?
    private var walletSubscription: Task<Void, Never>?
    
    init() throws {
        // Initialize NDK
        ndk = NDK(relayUrls: ["wss://relay.primal.net", "wss://relay.damus.io"])
    }
    
    func initialize(privateKey: String) async throws {
        // Create signer
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        ndk.signer = signer
        
        // Connect to relays
        print("📡 Connecting to relays...")
        try await ndk.connect()
        print("✅ Connected successfully!")
        
        // Load or create wallet
        wallet = try await loadOrCreateWallet()
        
        // Start wallet subscription for monitoring
        if let wallet = wallet {
            await wallet.startWalletSubscription()
        }
    }
    
    private func loadOrCreateWallet() async throws -> NDKCashuWallet {
        guard let pubkey = try await ndk.signer?.publicKey() else {
            throw WalletError.noSigner
        }
        
        print("🔍 Looking for existing wallet...")
        
        // Create wallet instance
        let wallet = NDKCashuWallet(ndk: ndk)
        
        // Load existing wallet or create new one
        try await wallet.load()
        
        // Check if this is a new wallet by checking balance
        let balance = try await wallet.getBalance()
        if balance == 0 {
            print("🔨 Setting up new wallet...")
            
            // Add default mints
            try await wallet.addMint(url: URL(string: "https://testnut.cashu.space")!)
            try await wallet.addMint(url: URL(string: "https://nofees.testnut.cashu.space")!)
            
            // Save wallet configuration
            try await wallet.save()
            
            // Publish nutzap preferences
            try await wallet.publishNutzapPreferences()
            
            print("✅ New wallet created and saved!")
        } else {
            print("✅ Wallet loaded successfully! Balance: \(balance) sats")
        }
        
        return wallet
    }
    
    func publishNutzapPreferences() async throws {
        guard let wallet = wallet else {
            throw WalletError.walletNotInitialized
        }
        
        try await wallet.publishNutzapPreferences()
    }
    
    func getBalance() async throws -> (total: Int, byMint: [String: Int]) {
        guard let wallet = wallet else {
            throw WalletError.walletNotInitialized
        }
        
        let total = Int(try await wallet.getBalance())
        
        // Get balance by mint
        var byMint: [String: Int] = [:]
        let mints = await wallet.getMintsInfo()
        for mintInfo in mints {
            let balance = await wallet.getBalance(mint: mintInfo.url)
            byMint[mintInfo.url.absoluteString] = Int(balance)
        }
        
        return (total, byMint)
    }
    
    func updateMints(_ mintUrls: [String]) async throws {
        guard let wallet = wallet else {
            throw WalletError.walletNotInitialized
        }
        
        // Remove all existing mints
        let currentMints = await wallet.getMintsInfo()
        for mintInfo in currentMints {
            try await wallet.removeMint(url: mintInfo.url)
        }
        
        // Add new mints
        for mintUrl in mintUrls {
            if let url = URL(string: mintUrl) {
                try await wallet.addMint(url: url)
            }
        }
        
        // Save and publish preferences
        try await wallet.save()
        try await wallet.publishNutzapPreferences()
    }
    
    func sendNutzap(to recipientPubkey: String, amount: Int, comment: String?) async throws -> String {
        guard let wallet = wallet else {
            throw WalletError.walletNotInitialized
        }
        
        // Check if recipient accepts nutzaps
        let filter = NDKFilter(
            kinds: [10019], // nutzapPreferences
            authors: [recipientPubkey]
        )
        
        let preferences = try await ndk.fetchEvents(filter)
        guard let prefEvent = preferences.first else {
            throw WalletError.recipientDoesNotAcceptNutzaps
        }
        
        // Extract accepted mints
        let acceptedMints = prefEvent.tags
            .filter { $0.first == "mint" && $0.count > 1 }
            .compactMap { URL(string: $0[1]) }
        
        guard !acceptedMints.isEmpty else {
            throw WalletError.recipientDoesNotAcceptNutzaps
        }
        
        // Check balance
        let balance = Int(try await wallet.getBalance())
        guard balance >= amount else {
            throw WalletError.insufficientBalance(have: balance, need: amount)
        }
        
        // Create nutzap request
        let request = NDKNutzapRequest(
            recipientPubkey: recipientPubkey,
            amount: Int64(amount),
            comment: comment,
            mints: acceptedMints
        )
        
        // Send nutzap
        let confirmation = try await wallet.pay(request) as! NDKCashuWallet.NDKCashuPaymentConfirmation
        
        return confirmation.nutzap.id
    }
    
    func getWallet() -> NDKCashuWallet? {
        return wallet
    }
    
    func getNDK() -> NDK {
        return ndk
    }
    
    func getMintURLs() async -> [String] {
        guard let wallet = wallet else { return [] }
        let mints = await wallet.getMintsInfo()
        return mints.map { $0.url.absoluteString }
    }
}

enum WalletError: Error, LocalizedError {
    case noSigner
    case walletNotInitialized
    case recipientDoesNotAcceptNutzaps
    case insufficientBalance(have: Int, need: Int)
    
    var errorDescription: String? {
        switch self {
        case .noSigner:
            return "No signer available"
        case .walletNotInitialized:
            return "Wallet not initialized"
        case .recipientDoesNotAcceptNutzaps:
            return "Recipient has not configured nutzap reception"
        case .insufficientBalance(let have, let need):
            return "Insufficient balance. You have \(have) sats but need \(need) sats"
        }
    }
}