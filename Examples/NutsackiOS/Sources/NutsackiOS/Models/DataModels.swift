import Foundation
import SwiftData
import NDKSwift

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