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
    
    @Relationship(deleteRule: .cascade)
    var wallets: [CashuWallet] = []
    
    init(publicKey: String, privateKey: String? = nil, displayName: String) {
        self.accountID = UUID()
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.displayName = displayName
        self.createdAt = Date()
        self.lastUsed = Date()
        self.wallets = []
    }
}

// MARK: - Cashu Wallet (NIP-60)
@Model
final class CashuWallet {
    @Attribute(.unique)
    var walletID: UUID
    
    var name: String
    var walletDescription: String?
    var nip60EventID: String?  // The event ID on Nostr
    var createdAt: Date
    var lastSync: Date?
    
    var account: NostrAccount?
    
    @Relationship(deleteRule: .cascade)
    var mints: [Mint] = []
    
    @Relationship(deleteRule: .cascade)
    var tokens: [CashuToken] = []
    
    @Relationship(deleteRule: .cascade)
    var transactions: [Transaction] = []
    
    init(name: String, description: String? = nil) {
        self.walletID = UUID()
        self.name = name
        self.walletDescription = description
        self.createdAt = Date()
        self.mints = []
        self.tokens = []
        self.transactions = []
    }
    
    var balance: Int {
        tokens.filter { $0.state == .unspent }.reduce(0) { $0 + $1.amount }
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
    
    var wallet: CashuWallet?
    
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
    
    var wallet: CashuWallet?
    
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
    
    var wallet: CashuWallet?
    
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