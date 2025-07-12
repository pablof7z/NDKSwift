import Foundation

enum NostrIdentifier {
    static func nsec(fromHex hex: String) -> String? {
        guard hex.count == 64 else { return nil }
        guard let data = Data(fromHex: hex) else { return nil }
        return bech32Encode(hrp: "nsec", data: data)
    }
    
    static func npub(fromHex hex: String) -> String? {
        guard hex.count == 64 else { return nil }
        guard let data = Data(fromHex: hex) else { return nil }
        return bech32Encode(hrp: "npub", data: data)
    }
    
    static func hex(fromNsec nsec: String) -> String? {
        guard nsec.starts(with: "nsec1") else { return nil }
        guard let decoded = bech32Decode(nsec) else { return nil }
        guard decoded.hrp == "nsec" else { return nil }
        return decoded.data.toHex()
    }
    
    static func hex(fromNpub npub: String) -> String? {
        guard npub.starts(with: "npub1") else { return nil }
        guard let decoded = bech32Decode(npub) else { return nil }
        guard decoded.hrp == "npub" else { return nil }
        return decoded.data.toHex()
    }
    
    // Simple bech32 implementation
    private static func bech32Encode(hrp: String, data: Data) -> String? {
        let values = convertBits(from: 8, to: 5, pad: true, data: data)
        guard let values = values else { return nil }
        
        let checksum = createChecksum(hrp: hrp, values: values)
        let combined = values + checksum
        
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        var result = hrp + "1"
        
        for value in combined {
            let index = Int(value)
            guard index < charset.count else { return nil }
            let char = charset[charset.index(charset.startIndex, offsetBy: index)]
            result.append(char)
        }
        
        return result
    }
    
    private static func bech32Decode(_ string: String) -> (hrp: String, data: Data)? {
        guard let separatorIndex = string.lastIndex(of: "1") else { return nil }
        
        let hrp = String(string[..<separatorIndex])
        let dataString = String(string[string.index(after: separatorIndex)...])
        
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        var values: [UInt8] = []
        
        for char in dataString {
            guard let index = charset.firstIndex(of: char) else { return nil }
            let value = charset.distance(from: charset.startIndex, to: index)
            values.append(UInt8(value))
        }
        
        guard values.count > 6 else { return nil }
        
        let dataValues = Array(values.dropLast(6))
        guard let data = convertBits(from: 5, to: 8, pad: false, data: Data(dataValues)) else { return nil }
        
        return (hrp, Data(data))
    }
    
    private static func convertBits(from: Int, to: Int, pad: Bool, data: Data) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << to) - 1
        
        for byte in data {
            acc = (acc << from) | Int(byte)
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (to - bits)) & maxv))
            }
        } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
            return nil
        }
        
        return result
    }
    
    private static func createChecksum(hrp: String, values: [UInt8]) -> [UInt8] {
        let enc = hrpExpand(hrp) + values + [0, 0, 0, 0, 0, 0]
        let mod = polymod(enc) ^ 1
        var ret: [UInt8] = []
        for i in 0..<6 {
            ret.append(UInt8((mod >> (5 * (5 - i))) & 31))
        }
        return ret
    }
    
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var ret: [UInt8] = []
        for char in hrp {
            ret.append(UInt8(char.asciiValue! >> 5))
        }
        ret.append(0)
        for char in hrp {
            ret.append(UInt8(char.asciiValue! & 31))
        }
        return ret
    }
    
    private static func polymod(_ values: [UInt8]) -> Int {
        let gen: [Int] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk = 1
        for value in values {
            let b = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ Int(value)
            for i in 0..<5 {
                chk ^= ((b >> i) & 1) != 0 ? gen[i] : 0
            }
        }
        return chk
    }
}

extension Data {
    init?(fromHex hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
    
    func toHex() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}