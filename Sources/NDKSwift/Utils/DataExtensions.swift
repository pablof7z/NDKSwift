import Foundation

// MARK: - Data extensions for hex conversion

public extension Data {
    /// Initialize Data from hex string
    /// - Parameter hexString: Hex string to convert (supports "0x" prefix and odd-length strings)
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove 0x prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        // Ensure even number of characters by padding with leading zero if needed
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    /// Convert Data to hex string
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    /// Pad Data to specified length with zeros
    /// - Parameter length: Target length
    /// - Returns: Data padded with zeros to reach the specified length
    func paddedToLength(_ length: Int) -> Data {
        if count >= length {
            return self
        }
        var padded = self
        padded.append(Data(repeating: 0, count: length - count))
        return padded
    }
}

// MARK: - String extensions for hex conversion

public extension String {
    /// Convert hex string to Data
    /// - Returns: Data representation of the hex string, or nil if invalid
    func hexDecoded() -> Data? {
        return Data(hexString: self)
    }
}

