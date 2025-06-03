import Foundation

// MARK: - Data extensions for hex conversion

public extension Data {
    /// Initialize Data from hex string
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    /// Convert Data to hex string
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// Extension for Foundation.Data (from CryptoSwift)
public extension Foundation.Data {
    /// Convert Data to hex string
    func toHexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}