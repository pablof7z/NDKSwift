import Foundation
import SwiftData
import NDKSwift

// MARK: - MintInfo
// Local replacement for the removed NIP60Wallet.MintInfo type
struct MintInfo: Identifiable, Equatable, Hashable {
    let id: String
    let url: URL
    let name: String?
    let description: String?
    let isActive: Bool
    
    init(url: URL, name: String? = nil, description: String? = nil, isActive: Bool = true) {
        self.id = url.absoluteString
        self.url = url
        self.name = name
        self.description = description
        self.isActive = isActive
    }
}


// Note: MintInfo is now defined at the top level of this file
// References to NIP60Wallet.MintInfo should be changed to just MintInfo

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
    var senderPubkey: String?  // For nutzaps and received transactions
    var offlineToken: String?  // Store generated offline token
    
    
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