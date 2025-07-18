import Foundation

/// Encoder for Negentropy protocol messages
public struct NegentropyEncoder {
    
    /// Encode initial message with full set fingerprint
    public static func encodeInitialMessage(fingerprint: Data, count: Int) throws -> Data {
        var data = Data()
        
        // Message type: 0 for initial
        data.append(0)
        
        // Encode count as varint
        data.append(encodeVarint(UInt64(count)))
        
        // Encode fingerprint (32 bytes)
        data.append(fingerprint)
        
        return data
    }
    
    /// Encode reconciliation message with ranges and IDs
    public static func encodeReconciliationMessage(
        ranges: [NegentropyRange],
        haveIds: [Data],
        needIds: [Data],
        frameSizeLimit: Int
    ) throws -> Data {
        var data = Data()
        
        // Message type: 1 for reconciliation
        data.append(1)
        
        // Encode number of ranges
        data.append(encodeVarint(UInt64(ranges.count)))
        
        // Encode each range
        for range in ranges {
            data.append(try encodeRange(range))
        }
        
        // Encode have IDs
        data.append(encodeVarint(UInt64(haveIds.count)))
        for id in haveIds {
            data.append(encodeIdPrefix(id))
        }
        
        // Encode need IDs
        data.append(encodeVarint(UInt64(needIds.count)))
        for id in needIds {
            data.append(encodeIdPrefix(id))
        }
        
        // Check frame size limit
        if data.count > frameSizeLimit {
            throw NegentropyError.frameSizeExceeded
        }
        
        return data
    }
    
    /// Encode termination message
    public static func encodeTerminationMessage(haveIds: [Data], needIds: [Data]) throws -> Data {
        var data = Data()
        
        // Message type: 2 for termination
        data.append(2)
        
        // Encode have IDs
        data.append(encodeVarint(UInt64(haveIds.count)))
        for id in haveIds {
            data.append(id) // Full ID in termination
        }
        
        // Encode need IDs
        data.append(encodeVarint(UInt64(needIds.count)))
        for id in needIds {
            data.append(id) // Full ID in termination
        }
        
        return data
    }
    
    // MARK: - Helper Methods
    
    private static func encodeRange(_ range: NegentropyRange) throws -> Data {
        var data = Data()
        
        // Encode bounds mode (0: unbounded, 1: lower only, 2: upper only, 3: both)
        let boundsMode: UInt8 = {
            switch (range.lower, range.upper) {
            case (nil, nil): return 0
            case (_, nil): return 1
            case (nil, _): return 2
            case (_, _): return 3
            }
        }()
        data.append(boundsMode)
        
        // Encode lower bound if present
        if let lower = range.lower {
            data.append(encodeVarint(lower.timestamp))
            data.append(encodeIdPrefix(lower.id))
        }
        
        // Encode upper bound if present
        if let upper = range.upper {
            data.append(encodeVarint(upper.timestamp))
            data.append(encodeIdPrefix(upper.id))
        }
        
        // Encode count
        data.append(encodeVarint(UInt64(range.count)))
        
        // Encode fingerprint prefix (8 bytes for efficiency)
        data.append(range.fingerprint.prefix(8))
        
        return data
    }
    
    /// Encode variable-length integer
    private static func encodeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var n = value
        
        while n >= 0x80 {
            data.append(UInt8((n & 0x7F) | 0x80))
            n >>= 7
        }
        data.append(UInt8(n))
        
        return data
    }
    
    /// Encode ID prefix (8 bytes for efficiency during reconciliation)
    private static func encodeIdPrefix(_ id: Data) -> Data {
        return id.prefix(8)
    }
}

/// Decoder for Negentropy protocol messages
public struct NegentropyDecoder {
    
    /// Decode a message from data
    public static func decode(_ data: Data) throws -> NegentropyMessage {
        var index = data.startIndex
        
        // Read message type
        guard index < data.endIndex else {
            throw NegentropyError.decodingError
        }
        let messageType = data[index]
        index = data.index(after: index)
        
        switch messageType {
        case 0:
            return try decodeInitialMessage(data: data, index: &index)
        case 1:
            return try decodeReconciliationMessage(data: data, index: &index)
        case 2:
            return try decodeTerminationMessage(data: data, index: &index)
        default:
            throw NegentropyError.decodingError
        }
    }
    
    // MARK: - Message Decoders
    
    private static func decodeInitialMessage(data: Data, index: inout Data.Index) throws -> NegentropyMessage {
        // Decode count
        let count = try decodeVarint(data: data, index: &index)
        
        // Decode fingerprint (32 bytes)
        guard data.distance(from: index, to: data.endIndex) >= 32 else {
            throw NegentropyError.decodingError
        }
        let fingerprint = data[index..<data.index(index, offsetBy: 32)]
        index = data.index(index, offsetBy: 32)
        
        return .initial(fingerprint: Data(fingerprint), count: Int(count))
    }
    
    private static func decodeReconciliationMessage(data: Data, index: inout Data.Index) throws -> NegentropyMessage {
        // Decode number of ranges
        let rangeCount = try decodeVarint(data: data, index: &index)
        
        // Decode ranges
        var ranges: [NegentropyRange] = []
        for _ in 0..<rangeCount {
            let range = try decodeRange(data: data, index: &index)
            ranges.append(range)
        }
        
        // Decode have IDs
        let haveCount = try decodeVarint(data: data, index: &index)
        var haveIds: [Data] = []
        for _ in 0..<haveCount {
            let idPrefix = try decodeIdPrefix(data: data, index: &index)
            haveIds.append(idPrefix)
        }
        
        // Decode need IDs
        let needCount = try decodeVarint(data: data, index: &index)
        var needIds: [Data] = []
        for _ in 0..<needCount {
            let idPrefix = try decodeIdPrefix(data: data, index: &index)
            needIds.append(idPrefix)
        }
        
        return .reconciliation(ranges: ranges, haveIds: haveIds, needIds: needIds)
    }
    
    private static func decodeTerminationMessage(data: Data, index: inout Data.Index) throws -> NegentropyMessage {
        // Decode have IDs (full 32 bytes)
        let haveCount = try decodeVarint(data: data, index: &index)
        var haveIds: [Data] = []
        for _ in 0..<haveCount {
            guard data.distance(from: index, to: data.endIndex) >= 32 else {
                throw NegentropyError.decodingError
            }
            let id = data[index..<data.index(index, offsetBy: 32)]
            haveIds.append(Data(id))
            index = data.index(index, offsetBy: 32)
        }
        
        // Decode need IDs (full 32 bytes)
        let needCount = try decodeVarint(data: data, index: &index)
        var needIds: [Data] = []
        for _ in 0..<needCount {
            guard data.distance(from: index, to: data.endIndex) >= 32 else {
                throw NegentropyError.decodingError
            }
            let id = data[index..<data.index(index, offsetBy: 32)]
            needIds.append(Data(id))
            index = data.index(index, offsetBy: 32)
        }
        
        return .termination(haveIds: haveIds, needIds: needIds)
    }
    
    // MARK: - Helper Methods
    
    private static func decodeRange(data: Data, index: inout Data.Index) throws -> NegentropyRange {
        // Decode bounds mode
        guard index < data.endIndex else {
            throw NegentropyError.decodingError
        }
        let boundsMode = data[index]
        index = data.index(after: index)
        
        // Decode bounds based on mode
        var lower: NegentropyItem?
        var upper: NegentropyItem?
        
        if boundsMode & 1 != 0 {
            // Has lower bound
            let timestamp = try decodeVarint(data: data, index: &index)
            let id = try decodeFullId(data: data, index: &index)
            lower = NegentropyItem(id: id, timestamp: timestamp)
        }
        
        if boundsMode & 2 != 0 {
            // Has upper bound
            let timestamp = try decodeVarint(data: data, index: &index)
            let id = try decodeFullId(data: data, index: &index)
            upper = NegentropyItem(id: id, timestamp: timestamp)
        }
        
        // Decode count
        let count = try decodeVarint(data: data, index: &index)
        
        // Decode fingerprint prefix (8 bytes)
        guard data.distance(from: index, to: data.endIndex) >= 8 else {
            throw NegentropyError.decodingError
        }
        let fingerprintPrefix = data[index..<data.index(index, offsetBy: 8)]
        index = data.index(index, offsetBy: 8)
        
        // Note: In a real implementation, we'd need to expand the fingerprint prefix
        // For now, we'll use the prefix as-is
        return NegentropyRange(
            lower: lower,
            upper: upper,
            fingerprint: Data(fingerprintPrefix),
            count: Int(count)
        )
    }
    
    private static func decodeVarint(data: Data, index: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        
        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            
            result |= UInt64(byte & 0x7F) << shift
            
            if byte & 0x80 == 0 {
                return result
            }
            
            shift += 7
            if shift > 63 {
                throw NegentropyError.decodingError
            }
        }
        
        throw NegentropyError.decodingError
    }
    
    private static func decodeIdPrefix(data: Data, index: inout Data.Index) throws -> Data {
        guard data.distance(from: index, to: data.endIndex) >= 8 else {
            throw NegentropyError.decodingError
        }
        let prefix = data[index..<data.index(index, offsetBy: 8)]
        index = data.index(index, offsetBy: 8)
        return Data(prefix)
    }
    
    private static func decodeFullId(data: Data, index: inout Data.Index) throws -> Data {
        // In the actual protocol, IDs might be compressed
        // For now, we'll read 8 bytes as a prefix
        return try decodeIdPrefix(data: data, index: &index)
            .paddedToLength(32) // Extend to full 32 bytes
    }
}

// Helper extension for padding data
extension Data {
    func paddedToLength(_ length: Int) -> Data {
        if count >= length {
            return self
        }
        var padded = self
        padded.append(Data(repeating: 0, count: length - count))
        return padded
    }
}