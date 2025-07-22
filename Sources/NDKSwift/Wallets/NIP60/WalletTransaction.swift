import Foundation
import CashuSwift

// MARK: - WalletTransaction

/// Unified representation of a wallet transaction
/// Merges data from multiple event types (7375, 7376, 9321) into a single coherent model
public struct WalletTransaction: Identifiable, Sendable {
    public let id: String
    public let type: WalletTransactionType
    public let amount: Int64
    public let direction: TransactionDirection
    public let status: TransactionStatus
    public let memo: String?
    public let mint: String?
    public let timestamp: Date
    
    // Event tracking - which events are associated with this transaction
    public let events: TransactionEvents
    
    // Lookup keys for finding this transaction
    public let lookupKeys: TransactionLookupKeys
    
    // Type-specific data
    public let nutzapData: NutzapData?
    public let lightningData: LightningData?
    public let ecashTokenData: EcashTokenData?
    
    public init(
        id: String? = nil,
        type: WalletTransactionType,
        amount: Int64,
        direction: TransactionDirection,
        status: TransactionStatus,
        memo: String? = nil,
        mint: String? = nil,
        timestamp: Date,
        events: TransactionEvents = TransactionEvents(),
        lookupKeys: TransactionLookupKeys = TransactionLookupKeys(),
        nutzapData: NutzapData? = nil,
        lightningData: LightningData? = nil,
        ecashTokenData: EcashTokenData? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.type = type
        self.amount = amount
        self.direction = direction
        self.status = status
        self.memo = memo
        self.mint = mint
        self.timestamp = timestamp
        self.events = events
        self.lookupKeys = lookupKeys
        self.nutzapData = nutzapData
        self.lightningData = lightningData
        self.ecashTokenData = ecashTokenData
    }
    
    /// Create a copy with updated fields
    public func with(
        status: TransactionStatus? = nil,
        events: TransactionEvents? = nil,
        memo: String?? = nil
    ) -> WalletTransaction {
        return WalletTransaction(
            id: self.id,  // Keep the same ID
            type: self.type,
            amount: self.amount,
            direction: self.direction,
            status: status ?? self.status,
            memo: memo ?? self.memo,
            mint: self.mint,
            timestamp: self.timestamp,
            events: events ?? self.events,
            lookupKeys: self.lookupKeys,
            nutzapData: self.nutzapData,
            lightningData: self.lightningData,
            ecashTokenData: self.ecashTokenData
        )
    }
}

// MARK: - Transaction Event Tracking

/// Tracks which Nostr events are associated with this transaction
public struct TransactionEvents: Sendable {
    public let spendingHistoryId: String?  // kind 7376
    public let nutzapEventId: String?       // kind 9321
    public let tokenEventIds: [String]      // kind 7375
    public let quoteEventId: String?        // kind 7374
    
    public init(
        spendingHistoryId: String? = nil,
        nutzapEventId: String? = nil,
        tokenEventIds: [String] = [],
        quoteEventId: String? = nil
    ) {
        self.spendingHistoryId = spendingHistoryId
        self.nutzapEventId = nutzapEventId
        self.tokenEventIds = tokenEventIds
        self.quoteEventId = quoteEventId
    }
    
    /// Returns the primary event ID (most important event for this transaction)
    public var primaryEventId: String? {
        // Prefer spending history as it's the authoritative record
        return spendingHistoryId ?? nutzapEventId ?? tokenEventIds.first ?? quoteEventId
    }
    
    /// All event IDs associated with this transaction
    public var allEventIds: [String] {
        var ids: [String] = []
        if let spendingHistoryId = spendingHistoryId { ids.append(spendingHistoryId) }
        if let nutzapEventId = nutzapEventId { ids.append(nutzapEventId) }
        ids.append(contentsOf: tokenEventIds)
        if let quoteEventId = quoteEventId { ids.append(quoteEventId) }
        return ids
    }
}

// MARK: - Transaction Lookup Keys

/// Keys for efficiently finding transactions
public struct TransactionLookupKeys: Sendable {
    public let nutzapEventId: String?      // For finding by 9321 event
    public let spendingHistoryId: String?  // For finding by 7376 event
    public let quoteId: String?            // For finding by mint quote
    public let paymentHash: String?        // For finding by Lightning invoice
    public let recipientPubkey: String?    // For finding outgoing nutzaps
    
    public init(
        nutzapEventId: String? = nil,
        spendingHistoryId: String? = nil,
        quoteId: String? = nil,
        paymentHash: String? = nil,
        recipientPubkey: String? = nil
    ) {
        self.nutzapEventId = nutzapEventId
        self.spendingHistoryId = spendingHistoryId
        self.quoteId = quoteId
        self.paymentHash = paymentHash
        self.recipientPubkey = recipientPubkey
    }
}

// MARK: - Transaction Types

public enum WalletTransactionType: String, Sendable, CaseIterable {
    case mint = "mint"           // Lightning -> Ecash (deposit)
    case melt = "melt"           // Ecash -> Lightning (withdrawal)
    case send = "send"           // Send ecash token
    case receive = "receive"     // Receive ecash token
    case nutzapSent = "nutzap_sent"       // Sent a nutzap
    case nutzapReceived = "nutzap_received"  // Received a nutzap
    case swap = "swap"           // Swap between mints
    
    public var displayName: String {
        switch self {
        case .mint: return "Lightning Deposit"
        case .melt: return "Lightning Payment"
        case .send: return "Sent Ecash"
        case .receive: return "Received Ecash"
        case .nutzapSent: return "Sent Nutzap"
        case .nutzapReceived: return "Received Nutzap"
        case .swap: return "Mint Transfer"
        }
    }
    
    public var icon: String {
        switch self {
        case .mint: return "bolt.fill"
        case .melt: return "bolt"
        case .send: return "arrow.up"
        case .receive: return "arrow.down"
        case .nutzapSent: return "bolt.heart"
        case .nutzapReceived: return "bolt.heart.fill"
        case .swap: return "arrow.left.arrow.right"
        }
    }
}

public enum TransactionDirection: String, Sendable {
    case incoming = "in"
    case outgoing = "out"
    case neutral = "neutral"  // For swaps
}

public enum TransactionStatus: String, Sendable {
    case pending = "pending"        // Created but no events yet
    case processing = "processing"  // Partial events (e.g., 9321 but no 7376)
    case completed = "completed"    // All expected events present
    case failed = "failed"
    case expired = "expired"
}

// MARK: - Type-Specific Data

/// Data specific to nutzap transactions
public struct NutzapData: Sendable {
    public let senderPubkey: String?     // For received nutzaps
    public let recipientPubkey: String?  // For sent nutzaps
    public let nutzapEventId: String     // The 9321 event
    public let comment: String?
    public let eventBeingZapped: String? // Optional event ID being zapped
    
    public init(
        senderPubkey: String? = nil,
        recipientPubkey: String? = nil,
        nutzapEventId: String,
        comment: String? = nil,
        eventBeingZapped: String? = nil
    ) {
        self.senderPubkey = senderPubkey
        self.recipientPubkey = recipientPubkey
        self.nutzapEventId = nutzapEventId
        self.comment = comment
        self.eventBeingZapped = eventBeingZapped
    }
}

/// Data specific to Lightning transactions
public struct LightningData: Sendable {
    public let invoice: String
    public let preimage: String?
    public let feePaid: Int64?
    
    public init(invoice: String, preimage: String? = nil, feePaid: Int64? = nil) {
        self.invoice = invoice
        self.preimage = preimage
        self.feePaid = feePaid
    }
}

/// Data specific to ecash token transactions
public struct EcashTokenData: Sendable {
    public let tokenString: String?  // For offline tokens
    public let proofCount: Int
    
    public init(tokenString: String? = nil, proofCount: Int) {
        self.tokenString = tokenString
        self.proofCount = proofCount
    }
}

// MARK: - Convenience Extensions

extension WalletTransaction {
    /// The effective amount considering direction
    public var signedAmount: Int64 {
        switch direction {
        case .incoming: return amount
        case .outgoing: return -amount
        case .neutral: return 0
        }
    }
    
    /// A display-friendly description
    public var displayDescription: String {
        if let memo = memo, !memo.isEmpty {
            return memo
        }
        
        // Type-specific descriptions
        switch type {
        case .nutzapReceived:
            if let sender = nutzapData?.senderPubkey {
                return "From \(sender.prefix(8))..."
            }
            return "Nutzap received"
            
        case .nutzapSent:
            if let recipient = nutzapData?.recipientPubkey {
                return "To \(recipient.prefix(8))..."
            }
            return "Nutzap sent"
            
        default:
            return type.displayName
        }
    }
}

// MARK: - Sorting

extension Array where Element == WalletTransaction {
    /// Sort transactions by timestamp (newest first)
    public func sortedByDate() -> [WalletTransaction] {
        self.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Filter by transaction type
    public func filtered(by types: Set<WalletTransactionType>) -> [WalletTransaction] {
        self.filter { types.contains($0.type) }
    }
    
    /// Filter by direction
    public func filtered(by direction: TransactionDirection) -> [WalletTransaction] {
        self.filter { $0.direction == direction }
    }
}