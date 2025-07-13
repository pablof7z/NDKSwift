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
    
    @Relationship(deleteRule: .cascade, inverse: \WalletState.account)
    var walletState: WalletState?
    
    init(publicKey: String, privateKey: String? = nil, displayName: String) {
        self.accountID = UUID()
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.displayName = displayName
        self.createdAt = Date()
        self.lastUsed = Date()
        self.hasWallet = false
        self.walletState = nil
    }
}

// MARK: - Wallet State (NIP-60)
// NIP-60 wallets are stored on Nostr, not locally
// This is just for tracking UI state and cached data
@Model
final class WalletState {
    @Attribute(.unique)
    var stateID: UUID
    
    var account: NostrAccount?
    var lastSync: Date?
    var cachedBalance: Int = 0
    
    @Relationship(deleteRule: .cascade)
    var transactions: [Transaction] = []
    
    init() {
        self.stateID = UUID()
        self.transactions = []
    }
}

// MARK: - Mint
@Model
final class Mint {
    @Attribute(.unique)
    var mintID: UUID
    
    var url: URL
    var name: String?
    var mintDescription: String?
    var pubkey: String?
    var contactInfo: [String]?
    var motd: String?
    var keysets: Data?  // Encoded keyset data
    var units: [String]
    var lastSync: Date?
    
    var account: NostrAccount?
    
    @Relationship(deleteRule: .nullify)
    var tokens: [CashuToken] = []
    
    init(url: URL, units: [String] = ["sat"]) {
        self.mintID = UUID()
        self.url = url
        self.units = units
        self.tokens = []
    }
    
    var displayName: String {
        name ?? url.host ?? url.absoluteString
    }
}

// MARK: - Cashu Token
@Model
final class CashuToken {
    @Attribute(.unique)
    var tokenID: UUID
    
    var amount: Int
    var keysetID: String
    var C: String  // Token commitment
    var secret: String
    var state: TokenState
    var createdAt: Date
    var spentAt: Date?
    var memo: String?
    var dleqVerified: Bool? // Whether DLEQ proof was verified
    
    var account: NostrAccount?
    
    var mint: Mint?
    
    var transaction: Transaction?
    
    init(amount: Int, keysetID: String, C: String, secret: String) {
        self.tokenID = UUID()
        self.amount = amount
        self.keysetID = keysetID
        self.C = C
        self.secret = secret
        self.state = .unspent
        self.createdAt = Date()
        self.dleqVerified = nil
    }
    
    enum TokenState: String, Codable {
        case unspent
        case pending
        case spent
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
    
    @Relationship(deleteRule: .nullify)
    var tokens: [CashuToken] = []
    
    init(type: TransactionType, amount: Int, memo: String? = nil) {
        self.transactionID = UUID()
        self.type = type
        self.amount = amount
        self.memo = memo
        self.createdAt = Date()
        self.status = .pending
        self.tokens = []
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