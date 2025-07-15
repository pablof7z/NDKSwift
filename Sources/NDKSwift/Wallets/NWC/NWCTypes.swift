import Foundation

// MARK: - NWC Methods

public enum NWCMethod: String, CaseIterable {
    case payInvoice = "pay_invoice"
    case multiPayInvoice = "multi_pay_invoice"
    case payKeysend = "pay_keysend"
    case multiPayKeysend = "multi_pay_keysend"
    case makeInvoice = "make_invoice"
    case lookupInvoice = "lookup_invoice"
    case listTransactions = "list_transactions"
    case getBalance = "get_balance"
    case getInfo = "get_info"
}

// MARK: - NWC Capabilities

public enum NWCCapability: String {
    case notifications = "notifications"
    case paymentReceived = "payment_received"
    case paymentSent = "payment_sent"
}

// MARK: - Base Request/Response

public protocol NWCRequest: Codable {
    var method: String { get }
}

public struct NWCRequestEnvelope<T: Encodable>: Encodable {
    public let method: String
    public let params: T
    
    public init(method: String, params: T) {
        self.method = method
        self.params = params
    }
}

public struct NWCResponse<T: Decodable>: Decodable {
    public let resultType: String
    public let error: NWCResponseError?
    public let result: T?
    
    enum CodingKeys: String, CodingKey {
        case resultType = "result_type"
        case error
        case result
    }
}

public struct NWCResponseError: Codable {
    public let code: String
    public let message: String
}

// MARK: - Pay Invoice

public struct PayInvoiceRequest: Codable {
    public let invoice: String
    public let amount: Int64?
    
    public init(invoice: String, amount: Int64? = nil) {
        self.invoice = invoice
        self.amount = amount
    }
}

public struct PayInvoiceResponse: Codable {
    public let preimage: String
    public let feesPaid: Int64?
    
    enum CodingKeys: String, CodingKey {
        case preimage
        case feesPaid = "fees_paid"
    }
}

// MARK: - Multi Pay Invoice

public struct MultiPayInvoiceRequest: Codable {
    public let invoices: [PayableInvoice]
    
    public struct PayableInvoice: Codable {
        public let id: String?
        public let invoice: String
        public let amount: Int64?
        
        public init(id: String? = nil, invoice: String, amount: Int64? = nil) {
            self.id = id
            self.invoice = invoice
            self.amount = amount
        }
    }
    
    public init(invoices: [PayableInvoice]) {
        self.invoices = invoices
    }
}

// MARK: - Pay Keysend

public struct PayKeysendRequest: Codable {
    public let amount: Int64
    public let pubkey: String
    public let preimage: String?
    public let tlvRecords: [TLVRecord]?
    
    public struct TLVRecord: Codable {
        public let type: Int
        public let value: String
        
        public init(type: Int, value: String) {
            self.type = type
            self.value = value
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case amount
        case pubkey
        case preimage
        case tlvRecords = "tlv_records"
    }
    
    public init(amount: Int64, pubkey: String, preimage: String? = nil, tlvRecords: [TLVRecord]? = nil) {
        self.amount = amount
        self.pubkey = pubkey
        self.preimage = preimage
        self.tlvRecords = tlvRecords
    }
}

public struct PayKeysendResponse: Codable {
    public let preimage: String
    public let feesPaid: Int64?
    
    enum CodingKeys: String, CodingKey {
        case preimage
        case feesPaid = "fees_paid"
    }
}

// MARK: - Multi Pay Keysend

public struct MultiPayKeysendRequest: Codable {
    public let keysends: [PayableKeysend]
    
    public struct PayableKeysend: Codable {
        public let id: String?
        public let pubkey: String
        public let amount: Int64
        public let preimage: String?
        public let tlvRecords: [PayKeysendRequest.TLVRecord]?
        
        enum CodingKeys: String, CodingKey {
            case id
            case pubkey
            case amount
            case preimage
            case tlvRecords = "tlv_records"
        }
        
        public init(id: String? = nil, pubkey: String, amount: Int64, preimage: String? = nil, tlvRecords: [PayKeysendRequest.TLVRecord]? = nil) {
            self.id = id
            self.pubkey = pubkey
            self.amount = amount
            self.preimage = preimage
            self.tlvRecords = tlvRecords
        }
    }
    
    public init(keysends: [PayableKeysend]) {
        self.keysends = keysends
    }
}

// MARK: - Make Invoice

public struct MakeInvoiceRequest: Codable {
    public let amount: Int64?
    public let description: String?
    public let descriptionHash: String?
    public let expiry: Int?
    
    enum CodingKeys: String, CodingKey {
        case amount
        case description
        case descriptionHash = "description_hash"
        case expiry
    }
    
    public init(amount: Int64? = nil, description: String? = nil, descriptionHash: String? = nil, expiry: Int? = nil) {
        self.amount = amount
        self.description = description
        self.descriptionHash = descriptionHash
        self.expiry = expiry
    }
}

public struct MakeInvoiceResponse: Codable {
    public let type: TransactionType
    public let invoice: String?
    public let description: String?
    public let descriptionHash: String?
    public let preimage: String?
    public let paymentHash: String
    public let amount: Int64
    public let feesPaid: Int64?
    public let createdAt: Int64
    public let expiresAt: Int64?
    public let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case invoice
        case description
        case descriptionHash = "description_hash"
        case preimage
        case paymentHash = "payment_hash"
        case amount
        case feesPaid = "fees_paid"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case metadata
    }
}

// MARK: - Lookup Invoice

public struct LookupInvoiceRequest: Codable {
    public let paymentHash: String?
    public let invoice: String?
    
    enum CodingKeys: String, CodingKey {
        case paymentHash = "payment_hash"
        case invoice
    }
    
    public init(paymentHash: String? = nil, invoice: String? = nil) {
        self.paymentHash = paymentHash
        self.invoice = invoice
    }
}

// MARK: - List Transactions

public struct ListTransactionsRequest: Codable {
    public let from: Int64?
    public let until: Int64?
    public let limit: Int?
    public let offset: Int?
    public let unpaid: Bool?
    public let type: TransactionType?
    
    public init(from: Int64? = nil, until: Int64? = nil, limit: Int? = nil, offset: Int? = nil, unpaid: Bool? = nil, type: TransactionType? = nil) {
        self.from = from
        self.until = until
        self.limit = limit
        self.offset = offset
        self.unpaid = unpaid
        self.type = type
    }
}

public struct ListTransactionsResponse: Codable {
    public let transactions: [Transaction]
}

public struct Transaction: Codable {
    public let type: TransactionType
    public let invoice: String?
    public let description: String?
    public let descriptionHash: String?
    public let preimage: String?
    public let paymentHash: String
    public let amount: Int64
    public let feesPaid: Int64?
    public let createdAt: Int64
    public let expiresAt: Int64?
    public let settledAt: Int64?
    public let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case invoice
        case description
        case descriptionHash = "description_hash"
        case preimage
        case paymentHash = "payment_hash"
        case amount
        case feesPaid = "fees_paid"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case settledAt = "settled_at"
        case metadata
    }
}

public enum TransactionType: String, Codable {
    case incoming
    case outgoing
}

// MARK: - Get Balance

public struct GetBalanceRequest: Codable {
    public init() {}
}

public struct GetBalanceResponse: Codable {
    /// Balance in millisatoshis (msat)
    public let balance: Int64
}

// MARK: - Get Info

public struct GetInfoRequest: Codable {
    public init() {}
}

public struct GetInfoResponse: Codable {
    public let alias: String?
    public let color: String?
    public let pubkey: String?
    public let network: String?
    public let blockHeight: Int?
    public let blockHash: String?
    public let methods: [String]
    public let notifications: [String]?
    
    enum CodingKeys: String, CodingKey {
        case alias
        case color
        case pubkey
        case network
        case blockHeight = "block_height"
        case blockHash = "block_hash"
        case methods
        case notifications
    }
}

// MARK: - Notifications

public enum NWCNotificationType: String {
    case paymentReceived = "payment_received"
    case paymentSent = "payment_sent"
}

public struct NWCNotification<T: Decodable>: Decodable {
    public let notificationType: String
    public let notification: T
    
    enum CodingKeys: String, CodingKey {
        case notificationType = "notification_type"
        case notification
    }
}

public struct PaymentNotification: Codable {
    public let type: TransactionType
    public let invoice: String?
    public let description: String?
    public let descriptionHash: String?
    public let preimage: String
    public let paymentHash: String
    public let amount: Int64
    public let feesPaid: Int64?
    public let createdAt: Int64
    public let expiresAt: Int64?
    public let settledAt: Int64
    public let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case invoice
        case description
        case descriptionHash = "description_hash"
        case preimage
        case paymentHash = "payment_hash"
        case amount
        case feesPaid = "fees_paid"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case settledAt = "settled_at"
        case metadata
    }
}

// MARK: - Helper for Any Codable

public struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode(Int64.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self.value = value.mapValues { $0.value }
        } else if let value = try? container.decode([AnyCodable].self) {
            self.value = value.map { $0.value }
        } else if container.decodeNil() {
            self.value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let value as Bool:
            try container.encode(value)
        case let value as Int64:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as String:
            try container.encode(value)
        case let value as [String: Any]:
            try container.encode(value.mapValues { AnyCodable($0) })
        case let value as [Any]:
            try container.encode(value.map { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}
