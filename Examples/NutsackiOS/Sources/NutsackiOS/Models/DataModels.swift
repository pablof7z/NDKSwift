import Foundation
import SwiftData
import NDKSwift

// MARK: - Nostr Account
@Model
final class NostrAccount {
    @Attribute(.unique)
    var accountID: UUID
    
    var publicKey: String
    var privateKey: String?  // Encrypted in keychain in production
    var displayName: String
    var about: String?
    var picture: String?
    var nip05: String?
    var createdAt: Date
    var lastUsed: Date
    
    // NIP-60: One wallet per pubkey, no need to track multiple wallets
    var hasWallet: Bool = false
    
    init(publicKey: String, privateKey: String? = nil, displayName: String) {
        self.accountID = UUID()
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.displayName = displayName
        self.createdAt = Date()
        self.lastUsed = Date()
        self.hasWallet = false
    }
}

// MARK: - Transaction
@Model
final class Transaction {
    @Attribute(.unique)
    var transactionID: UUID
    
    var type: TransactionType
    var amount: Int
    var memo: String?
    var createdAt: Date
    var nostrEventID: String?  // For nutzaps
    var lightningInvoice: String?
    var status: TransactionStatus
    
    var account: NostrAccount?
    
    init(type: TransactionType, amount: Int, memo: String? = nil) {
        self.transactionID = UUID()
        self.type = type
        self.amount = amount
        self.memo = memo
        self.createdAt = Date()
        self.status = .pending
    }
    
    enum TransactionType: String, Codable {
        case mint      // Lightning -> Ecash
        case melt      // Ecash -> Lightning
        case send      // Send ecash token
        case receive   // Receive ecash token
        case nutzap    // NIP-61 zap
    }
    
    enum TransactionStatus: String, Codable {
        case pending
        case completed
        case failed
    }
}