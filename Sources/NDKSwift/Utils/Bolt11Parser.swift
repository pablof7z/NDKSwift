import Foundation

/// Comprehensive Bolt11 Lightning invoice parser
/// Based on the BOLT #11 specification
public enum Bolt11Parser {
    
    // MARK: - Public Types
    
    public struct Invoice: Equatable {
        public let network: Network
        public let date: Date
        public let paymentHash: Data?
        public let amount: Satoshi?
        public let description: String?
        public let expiry: TimeInterval?
        
        public init(network: Network, date: Date, paymentHash: Data? = nil, amount: Satoshi? = nil, description: String? = nil, expiry: TimeInterval? = nil) {
            self.network = network
            self.date = date
            self.paymentHash = paymentHash
            self.amount = amount
            self.description = description
            self.expiry = expiry
        }
    }
    
    public enum Network: String, Codable, CaseIterable {
        case regtest
        case testnet
        case mainnet
        case simnet
    }
    
    public enum Prefix: String {
        case lnbc   // Bitcoin mainnet
        case lntb   // Bitcoin testnet
        case lnbcrt // Bitcoin regtest
        case lnsb   // Bitcoin simnet
        
        public static func forNetwork(_ network: Network) -> Prefix {
            switch network {
            case .regtest:
                return .lnbcrt
            case .testnet:
                return .lntb
            case .mainnet:
                return .lnbc
            case .simnet:
                return .lnsb
            }
        }
    }
    
    // MARK: - Private Types
    
    private enum Multiplier: Character {
        case milli = "m"
        case micro = "u"
        case nano = "n"
        case pico = "p"
        
        var value: Decimal {
            switch self {
            case .milli:
                return 100000      // mBTC to millisats
            case .micro:
                return 100         // μBTC to millisats
            case .nano:
                return 0.1         // nBTC to millisats
            case .pico:
                return 0.0001      // pBTC to millisats
            }
        }
    }
    
    private enum FieldTypes: UInt8 {
        case fieldTypeP = 1  // Payment hash
        case fieldTypeD = 13 // Short description
        case fieldTypeN = 19 // Target node pubkey
        case fieldTypeH = 23 // Description hash
        case fieldTypeX = 6  // Expiry in seconds
        case fieldTypeF = 9  // Fallback on-chain address
        case fieldTypeR = 3  // Extra routing information
        case fieldTypeC = 24 // Final CLTV delta
    }
    
    // MARK: - Constants
    
    private static let signatureBase32Len = 104
    private static let timestampBase32Len = 7
    private static let hashBase32Len = 52
    
    // MARK: - Public Methods
    
    /// Decode a Bolt11 invoice string
    /// - Parameter string: The Bolt11 invoice string to decode
    /// - Returns: Decoded invoice or nil if invalid
    public static func decode(string: String) -> Invoice? {
        // Use NDKSwift's existing Bech32 implementation for basic validation
        guard Bech32.isBech32(string) else { return nil }
        
        // Parse using custom Bech32 decoder for Lightning invoices
        guard let (humanReadablePart, data) = decodeBech32(string, limit: false),
              humanReadablePart.count > 3,
              let network = decodeNetwork(humanReadablePart: humanReadablePart) else {
            return nil
        }
        
        let invoiceData = data.dropLast(signatureBase32Len)
        guard invoiceData.count >= timestampBase32Len else { return nil }
        
        let date = parseTimestamp(data: invoiceData[invoiceData.startIndex..<invoiceData.startIndex + timestampBase32Len])
        var invoice = Invoice(network: network, date: date)
        
        invoice = invoice.withAmount(decodeAmount(for: humanReadablePart, network: network))
        
        let tagData = invoiceData[invoiceData.startIndex + timestampBase32Len..<invoiceData.endIndex]
        
        return parseTaggedFields(data: tagData, invoice: invoice)
    }
    
    // MARK: - Private Methods
    
    private static func decodeBech32(_ bech32: String, limit: Bool) -> (String, Data)? {
        guard let separatorIndex = bech32.lastIndex(of: "1") else { return nil }
        
        let hrp = String(bech32[..<separatorIndex]).lowercased()
        let dataString = String(bech32[bech32.index(after: separatorIndex)...]).lowercased()
        
        guard !hrp.isEmpty, !dataString.isEmpty else { return nil }
        
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        var values: [UInt8] = []
        
        for char in dataString {
            guard let position = charset.firstIndex(of: char) else { return nil }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: position)))
        }
        
        return (hrp, Data(values))
    }
    
    private static func parseTimestamp(data: Data) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(base32ToUInt(data)))
    }
    
    private static func parseTaggedFields(data: Data, invoice: Invoice) -> Invoice? {
        var invoice = invoice
        var index: Data.Index = data.startIndex
        
        while data.endIndex - index >= 3 {
            let type = FieldTypes(rawValue: data[index])
            guard let dataLength = parseFieldDataLength(data[index + 1..<index + 3]),
                  data.endIndex >= index + 3 + dataLength else {
                return nil
            }
            
            let base32Data = data[index + 3..<index + 3 + dataLength]
            index += 3 + dataLength
            
            if let type = type {
                switch type {
                case .fieldTypeP:
                    guard invoice.paymentHash == nil else { break }
                    invoice = invoice.withPaymentHash(parsePaymentHash(data: base32Data))
                case .fieldTypeD:
                    guard invoice.description == nil else { break }
                    invoice = invoice.withDescription(parseDescription(data: base32Data))
                case .fieldTypeX:
                    guard invoice.expiry == nil else { break }
                    invoice = invoice.withExpiry(parseExpiry(data: base32Data))
                case .fieldTypeF, .fieldTypeN, .fieldTypeH, .fieldTypeC, .fieldTypeR:
                    break
                }
            }
        }
        
        return invoice
    }
    
    private static func base32ToUInt(_ data: Data) -> UInt {
        var result: UInt = 0
        for byte in data {
            result = result << 5 | UInt(byte)
        }
        return result
    }
    
    private static func parseFieldDataLength(_ data: Data) -> Int? {
        guard data.count == 2 else { return nil }
        return Int(data[data.startIndex]) << 5 | Int(data[data.startIndex + 1])
    }
    
    private static func parseDescription(data: Data) -> String? {
        guard let base256Data = data.convertBits(fromBits: 5, toBits: 8, pad: false) else {
            return nil
        }
        return String(data: base256Data, encoding: .utf8)
    }
    
    private static func parseExpiry(data: Data) -> TimeInterval {
        return TimeInterval(base32ToUInt(data))
    }
    
    private static func parsePaymentHash(data: Data) -> Data? {
        guard data.count == hashBase32Len else { return nil }
        return data.convertBits(fromBits: 5, toBits: 8, pad: false)
    }
    
    private static func decodeAmount(for humanReadablePart: String, network: Network) -> Satoshi? {
        let netPrefixLength = Prefix.forNetwork(network).rawValue.count
        var amountString = humanReadablePart[humanReadablePart.index(humanReadablePart.startIndex, offsetBy: netPrefixLength)..<humanReadablePart.endIndex]
        
        guard amountString.count >= 2 else { return nil }
        
        let lastCharacter = amountString.removeLast()
        
        guard let multiplier = Multiplier(rawValue: lastCharacter),
              let amount = Int(amountString) else {
            return nil
        }
        
        return Decimal(amount) * multiplier.value
    }
    
    private static func decodeNetwork(humanReadablePart: String) -> Network? {
        if humanReadablePart.starts(with: Prefix.forNetwork(.mainnet).rawValue) {
            return .mainnet
        } else if humanReadablePart.starts(with: Prefix.forNetwork(.testnet).rawValue) {
            return .testnet
        } else if humanReadablePart.starts(with: Prefix.forNetwork(.simnet).rawValue) {
            return .simnet
        }
        return nil
    }
}

// MARK: - Invoice Extensions

private extension Bolt11Parser.Invoice {
    mutating func setAmount(_ amount: Satoshi?) {
        self = withAmount(amount)
    }
    
    func withAmount(_ amount: Satoshi?) -> Bolt11Parser.Invoice {
        return Bolt11Parser.Invoice(
            network: self.network,
            date: self.date,
            paymentHash: self.paymentHash,
            amount: amount,
            description: self.description,
            expiry: self.expiry
        )
    }
    
    func withPaymentHash(_ paymentHash: Data?) -> Bolt11Parser.Invoice {
        return Bolt11Parser.Invoice(
            network: self.network,
            date: self.date,
            paymentHash: paymentHash,
            amount: self.amount,
            description: self.description,
            expiry: self.expiry
        )
    }
    
    func withDescription(_ description: String?) -> Bolt11Parser.Invoice {
        return Bolt11Parser.Invoice(
            network: self.network,
            date: self.date,
            paymentHash: self.paymentHash,
            amount: self.amount,
            description: description,
            expiry: self.expiry
        )
    }
    
    func withExpiry(_ expiry: TimeInterval?) -> Bolt11Parser.Invoice {
        return Bolt11Parser.Invoice(
            network: self.network,
            date: self.date,
            paymentHash: self.paymentHash,
            amount: self.amount,
            description: self.description,
            expiry: expiry
        )
    }
}

// MARK: - Data Extensions

private extension Data {
    /// Convert bits from one base to another
    func convertBits(fromBits: Int, toBits: Int, pad: Bool) -> Data? {
        var acc = 0
        var bits = 0
        var result = Data()
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1
        
        for byte in self {
            if Int(byte) >= (1 << fromBits) {
                return nil
            }
            acc = ((acc << fromBits) | Int(byte)) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        
        return result
    }
}

// MARK: - Satoshi Type

public typealias Satoshi = Decimal

public extension Satoshi {
    func rounded() -> Satoshi {
        var value = self
        var result: Decimal = 0
        NSDecimalRound(&result, &value, 0, .bankers)
        return result
    }
    
    var int64: Int64 {
        return Int64(truncating: self.rounded() as NSDecimalNumber)
    }
}