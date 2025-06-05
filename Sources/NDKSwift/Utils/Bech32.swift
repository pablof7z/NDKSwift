import Foundation

/// Bech32 encoding/decoding utilities for Nostr entities
public enum Bech32 {
    /// Bech32 character set
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    /// Generator coefficients for checksum
    private static let generator: [UInt32] = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]

    /// Errors that can occur during Bech32 operations
    public enum Bech32Error: Error, LocalizedError {
        case invalidCharacter(Character)
        case invalidChecksum
        case invalidLength
        case invalidHRP
        case invalidData
        case invalidPadding

        public var errorDescription: String? {
            switch self {
            case let .invalidCharacter(char):
                return "Invalid character in bech32 string: \(char)"
            case .invalidChecksum:
                return "Invalid bech32 checksum"
            case .invalidLength:
                return "Invalid bech32 string length"
            case .invalidHRP:
                return "Invalid human-readable part"
            case .invalidData:
                return "Invalid bech32 data"
            case .invalidPadding:
                return "Invalid padding in bech32 data"
            }
        }
    }

    /// Encode data to bech32
    public static func encode(hrp: String, data: [UInt8]) throws -> String {
        let values = try convertBits(data: data, fromBits: 8, toBits: 5, pad: true)
        let checksum = createChecksum(hrp: hrp, values: values)
        let combined = values + checksum

        let encoded = combined.map { charset[charset.index(charset.startIndex, offsetBy: Int($0))] }
        return hrp + "1" + String(encoded)
    }

    /// Decode bech32 string
    public static func decode(_ bech32: String) throws -> (hrp: String, data: [UInt8]) {
        guard let separatorIndex = bech32.lastIndex(of: "1") else {
            throw Bech32Error.invalidHRP
        }

        let hrp = String(bech32[..<separatorIndex]).lowercased()
        let dataString = String(bech32[bech32.index(after: separatorIndex)...]).lowercased()

        guard !hrp.isEmpty, !dataString.isEmpty else {
            throw Bech32Error.invalidLength
        }

        var values: [UInt8] = []
        for char in dataString {
            guard let position = charset.firstIndex(of: char) else {
                throw Bech32Error.invalidCharacter(char)
            }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: position)))
        }

        guard values.count >= 6 else {
            throw Bech32Error.invalidLength
        }

        let checksumLength = 6
        let dataValues = Array(values.dropLast(checksumLength))

        guard verifyChecksum(hrp: hrp, values: values) else {
            throw Bech32Error.invalidChecksum
        }

        let data = try convertBits(data: dataValues, fromBits: 5, toBits: 8, pad: false)
        return (hrp, data)
    }

    /// Convert bits
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            if Int(value) >= (1 << fromBits) {
                throw Bech32Error.invalidData
            }
            acc = ((acc << fromBits) | Int(value)) & maxAcc
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
            throw Bech32Error.invalidPadding
        }

        return result
    }

    /// Create checksum
    private static func createChecksum(hrp: String, values: [UInt8]) -> [UInt8] {
        let polymod = polymodStep(pre: 1, values: hrpExpand(hrp) + values + [0, 0, 0, 0, 0, 0]) ^ 1
        var result: [UInt8] = []
        for i in 0 ..< 6 {
            result.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }
        return result
    }

    /// Verify checksum
    private static func verifyChecksum(hrp: String, values: [UInt8]) -> Bool {
        return polymodStep(pre: 1, values: hrpExpand(hrp) + values) == 1
    }

    /// HRP expansion
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result: [UInt8] = []
        for char in hrp {
            guard let scalar = char.unicodeScalars.first else { continue }
            result.append(UInt8(scalar.value >> 5))
        }
        result.append(0)
        for char in hrp {
            guard let scalar = char.unicodeScalars.first else { continue }
            result.append(UInt8(scalar.value & 31))
        }
        return result
    }

    /// Polymod step
    private static func polymodStep(pre: UInt32, values: [UInt8]) -> UInt32 {
        var chk = pre
        for value in values {
            let b = chk >> 25
            chk = (chk & 0x1FFFFFF) << 5 ^ UInt32(value)
            for i in 0 ..< 5 {
                chk ^= ((b >> i) & 1) == 1 ? generator[i] : 0
            }
        }
        return chk
    }
}

/// Nostr-specific Bech32 encoding/decoding
public extension Bech32 {
    /// Encode a public key to npub format
    static func npub(from pubkey: PublicKey) throws -> String {
        guard pubkey.count == 64, let data = Data(hexString: pubkey), data.count == 32 else {
            throw Bech32Error.invalidData
        }
        return try encode(hrp: "npub", data: Array(data))
    }

    /// Decode npub to public key
    static func pubkey(from npub: String) throws -> PublicKey {
        let (hrp, data) = try decode(npub)
        guard hrp == "npub" else {
            throw Bech32Error.invalidHRP
        }
        return Data(data).hexString
    }

    /// Encode a private key to nsec format
    static func nsec(from privateKey: PrivateKey) throws -> String {
        guard privateKey.count == 64 else {
            throw Bech32Error.invalidData
        }

        guard let data = Data(hexString: privateKey) else {
            throw Bech32Error.invalidData
        }

        guard data.count == 32 else {
            throw Bech32Error.invalidData
        }

        return try encode(hrp: "nsec", data: Array(data))
    }

    /// Decode nsec to private key
    static func privateKey(from nsec: String) throws -> PrivateKey {
        let (hrp, data) = try decode(nsec)
        guard hrp == "nsec" else {
            throw Bech32Error.invalidHRP
        }
        return Data(data).hexString
    }

    /// Encode an event ID to note format
    static func note(from eventId: EventID) throws -> String {
        guard eventId.count == 64, let data = Data(hexString: eventId), data.count == 32 else {
            throw Bech32Error.invalidData
        }
        return try encode(hrp: "note", data: Array(data))
    }

    /// Decode note to event ID
    static func eventId(from note: String) throws -> EventID {
        let (hrp, data) = try decode(note)
        guard hrp == "note" else {
            throw Bech32Error.invalidHRP
        }
        return Data(data).hexString
    }

    /// Encode event with optional metadata to nevent format
    static func nevent(
        eventId: EventID,
        relays: [String]? = nil,
        author: PublicKey? = nil,
        kind: Int? = nil
    ) throws -> String {
        guard eventId.count == 64, let eventData = Data(hexString: eventId), eventData.count == 32 else {
            throw Bech32Error.invalidData
        }

        var tlvData: [UInt8] = []

        // Type 0: Event ID (32 bytes)
        tlvData.append(0)
        tlvData.append(32)
        tlvData.append(contentsOf: eventData)

        // Type 1: Relay hints (optional)
        if let relays = relays {
            for relay in relays {
                let relayData = Array(relay.utf8)
                tlvData.append(1)
                tlvData.append(UInt8(relayData.count))
                tlvData.append(contentsOf: relayData)
            }
        }

        // Type 2: Author (optional)
        if let author = author, author.count == 64, let authorData = Data(hexString: author), authorData.count == 32 {
            tlvData.append(2)
            tlvData.append(32)
            tlvData.append(contentsOf: authorData)
        }

        // Type 3: Kind (optional)
        if let kind = kind {
            let kindBytes = withUnsafeBytes(of: UInt32(kind).bigEndian) { Array($0) }
            tlvData.append(3)
            tlvData.append(UInt8(kindBytes.count))
            tlvData.append(contentsOf: kindBytes)
        }

        return try encode(hrp: "nevent", data: tlvData)
    }

    /// Encode addressable event to naddr format
    static func naddr(
        identifier: String,
        kind: Int,
        author: PublicKey,
        relays: [String]? = nil
    ) throws -> String {
        guard author.count == 64, let authorData = Data(hexString: author), authorData.count == 32 else {
            throw Bech32Error.invalidData
        }

        var tlvData: [UInt8] = []

        // Type 0: Identifier
        let identifierData = Array(identifier.utf8)
        tlvData.append(0)
        tlvData.append(UInt8(identifierData.count))
        tlvData.append(contentsOf: identifierData)

        // Type 1: Relay hints (optional)
        if let relays = relays {
            for relay in relays {
                let relayData = Array(relay.utf8)
                tlvData.append(1)
                tlvData.append(UInt8(relayData.count))
                tlvData.append(contentsOf: relayData)
            }
        }

        // Type 2: Author (required)
        tlvData.append(2)
        tlvData.append(32)
        tlvData.append(contentsOf: authorData)

        // Type 3: Kind (required)
        let kindBytes = withUnsafeBytes(of: UInt32(kind).bigEndian) { Array($0) }
        tlvData.append(3)
        tlvData.append(UInt8(kindBytes.count))
        tlvData.append(contentsOf: kindBytes)

        return try encode(hrp: "naddr", data: tlvData)
    }
}
