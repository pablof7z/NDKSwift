import Foundation
import CryptoKit

// Protocol constants
let PROTOCOL_VERSION: UInt8 = 0x61
let ID_SIZE = 32
let FINGERPRINT_SIZE = 16

// Modes
enum NegentropyMode {
    static let skip: UInt8 = 0
    static let fingerprint: UInt8 = 1
    static let idList: UInt8 = 2
}

// Bound structure
struct NegentropyBound {
    let timestamp: UInt64
    let id: Data
    
    init(timestamp: UInt64, id: Data = Data()) {
        self.timestamp = timestamp
        self.id = id
    }
}

/// Main Negentropy implementation for efficient set reconciliation.
///
/// Negentropy is a protocol that allows two parties to efficiently synchronize
/// their data sets by identifying and exchanging only the differences. This implementation
/// follows the protocol specification at https://github.com/hoytech/negentropy
///
/// ## Overview
///
/// The protocol works by:
/// 1. Each party maintains a sorted list of items (ID + timestamp)
/// 2. Items are grouped into ranges with fingerprints
/// 3. Parties exchange fingerprints to identify differences
/// 4. Differing ranges are subdivided until individual items are identified
/// 5. Missing items are exchanged to achieve synchronization
///
/// ## Usage
///
/// ```swift
/// // Setup storage for your events
/// let storage = NDKCacheNegentropyStorage(cache: yourCache)
///
/// // Create Negentropy instance
/// let negentropy = Negentropy(
///     storage: storage,
///     frameSizeLimit: 60_000 // 60KB for mobile networks
/// )
///
/// // Initiate reconciliation
/// let initMessage = try await negentropy.initiate()
/// // Send initMessage to peer...
///
/// // Process responses
/// let (response, haveIds, needIds) = try await negentropy.reconcile(peerMessage)
/// // Handle the results...
/// ```
///
/// ## Performance Considerations
///
/// - **Frame Size**: Larger frames reduce round trips but use more memory
/// - **Storage**: Ensure your storage implementation is optimized for range queries
/// - **Network**: Consider connection quality when setting frame size limits
///
/// ## Thread Safety
///
/// This class is an `actor` and provides thread-safe access to reconciliation state.
/// All public methods are `async` and properly serialize access.
public actor Negentropy {
    private let storage: NegentropyStorage
    private let frameSizeLimit: Int
    
    private var isInitiator = false
    private var lastTimestampIn: UInt64 = 0
    private var lastTimestampOut: UInt64 = 0
    
    /// Creates a new Negentropy instance for set reconciliation.
    ///
    /// - Parameters:
    ///   - storage: Storage implementation providing access to your data set
    ///   - frameSizeLimit: Maximum size in bytes for protocol messages (0 = unlimited)
    ///
    /// ## Frame Size Guidelines
    ///
    /// - **0 (unlimited)**: For high-bandwidth, reliable connections
    /// - **30,000**: Conservative for mobile/cellular networks
    /// - **60,000**: Balanced for most internet connections
    /// - **500,000**: Aggressive for LAN or high-speed connections
    public init(storage: NegentropyStorage, frameSizeLimit: Int = 0) {
        self.storage = storage
        self.frameSizeLimit = frameSizeLimit
    }
    
    /// Initiates a new reconciliation session as the initiator.
    ///
    /// This method starts the reconciliation protocol by analyzing the local storage
    /// and generating an initial message to send to the peer.
    ///
    /// - Returns: Binary message to send to the peer
    /// - Throws: `NegentropyError.protocolError` if already initiated
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let negentropy = Negentropy(storage: storage)
    /// let initMessage = try await negentropy.initiate()
    /// // Send initMessage to peer via your transport layer
    /// ```
    ///
    /// - Important: Can only be called once per Negentropy instance
    public func initiate() async throws -> Data {
        guard !isInitiator else { throw NegentropyError.protocolError("already initiated") }
        isInitiator = true
        
        var output = Data()
        output.append(PROTOCOL_VERSION)
        
        let storageSize = try await storage.size()
        try await splitRange(
            lower: 0,
            upper: storageSize,
            upperBound: NegentropyBound(timestamp: .max),
            output: &output
        )
        
        return output
    }
    
    /// Processes a peer message and generates the appropriate response.
    ///
    /// This method handles incoming reconciliation messages and produces the next
    /// message in the protocol flow, along with lists of items that need to be
    /// exchanged.
    ///
    /// - Parameter query: Binary message received from the peer
    /// - Returns: A tuple containing:
    ///   - `output`: Next message to send to peer (nil if reconciliation complete)
    ///   - `haveIds`: List of item IDs we have that the peer needs
    ///   - `needIds`: List of item IDs we need from the peer
    ///
    /// - Throws:
    ///   - `NegentropyError.protocolError`: For protocol violations
    ///   - `NegentropyError.decodingError`: For malformed messages
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Process peer message
    /// let (response, haveIds, needIds) = try await negentropy.reconcile(peerMessage)
    ///
    /// // Send our items that peer needs
    /// for id in haveIds {
    ///     let item = await storage.getItem(id: id)
    ///     await sendToPeer(item)
    /// }
    ///
    /// // Request items we need
    /// for id in needIds {
    ///     await requestFromPeer(id: id)
    /// }
    ///
    /// // Continue protocol if response is not nil
    /// if let response = response {
    ///     await sendToPeer(response)
    /// }
    /// ```
    ///
    /// ## Protocol States
    ///
    /// - **First call**: Peer processes our initial message
    /// - **Intermediate calls**: Exchange fingerprints and subdivide ranges
    /// - **Final call**: Returns `nil` output when reconciliation is complete
    public func reconcile(_ query: Data) async throws -> (output: Data?, haveIds: [String], needIds: [String]) {
        var input = DataReader(query)
        var haveIds: [String] = []
        var needIds: [String] = []
        
        // Reset timestamp tracking for each message
        lastTimestampIn = 0
        lastTimestampOut = 0
        
        var fullOutput = Data()
        fullOutput.append(PROTOCOL_VERSION)
        
        // Check protocol version
        guard let protocolVersion = input.readByte() else {
            throw NegentropyError.decodingError
        }
        
        if protocolVersion < 0x60 || protocolVersion > 0x6F {
            throw NegentropyError.protocolError("invalid protocol version")
        }
        
        if protocolVersion != PROTOCOL_VERSION {
            if isInitiator {
                throw NegentropyError.protocolError("unsupported protocol version")
            } else {
                // Return just protocol version
                return (fullOutput, [], [])
            }
        }
        
        
        let storageSize = try await storage.size()
        var prevBound = NegentropyBound(timestamp: 0)
        var prevIndex = 0
        var skip = false
        
        while input.hasMore {
            print("[Negentropy] Processing next bound, bytes remaining: \(input.remaining)")
            var output = Data()
            
            let doSkip = { [self] in
                if skip {
                    skip = false
                    output.append(self.encodeBound(prevBound))
                    output.append(self.encodeVarint(UInt64(NegentropyMode.skip)))
                }
            }
            
            let currBound: NegentropyBound
            do {
                currBound = try decodeBound(&input)
            } catch {
                print("[Negentropy] Failed to decode bound: \(error), remaining bytes: \(input.remaining)")
                throw error
            }
            
            guard let mode = decodeVarint(&input) else {
                print("[Negentropy] Failed to decode mode, remaining bytes: \(input.remaining)")
                throw NegentropyError.decodingError
            }
            
            let lower = prevIndex
            let upper = try await storage.findLowerBound(prevIndex, storageSize, currBound)
            
            print("[Negentropy] Processing bound: timestamp=\(currBound.timestamp), id=\(currBound.id.hexEncodedString()), mode=\(mode), lower=\(lower), upper=\(upper), storageSize=\(storageSize)")
            
            if mode == NegentropyMode.skip {
                skip = true
            } else if mode == NegentropyMode.fingerprint {
                guard let theirFingerprint = input.readBytes(FINGERPRINT_SIZE) else {
                    throw NegentropyError.decodingError
                }
                
                let ourFingerprint = try await storage.fingerprint(lower, upper)
                
                if theirFingerprint != ourFingerprint {
                    doSkip()
                    try await splitRange(lower: lower, upper: upper, upperBound: currBound, output: &output)
                } else {
                    skip = true
                }
            } else if mode == NegentropyMode.idList {
                guard let numIds = decodeVarint(&input) else {
                    throw NegentropyError.decodingError
                }
                
                print("[Negentropy] Received ID list with \(numIds) IDs (isInitiator=\(isInitiator))")
                
                var theirIds = Set<Data>()
                for i in 0..<numIds {
                    guard let id = input.readBytes(ID_SIZE) else {
                        throw NegentropyError.decodingError
                    }
                    theirIds.insert(id)
                    print("[Negentropy] ID \(i): \(id.hexEncodedString())")
                }
                
                if isInitiator {
                    skip = true
                    
                    // Find what we have that they don't
                    try await storage.iterate(lower, upper) { item in
                        if !theirIds.contains(item.id) {
                            haveIds.append(item.id.hexEncodedString())
                        } else {
                            theirIds.remove(item.id)
                        }
                        return true
                    }
                    
                    // What they have that we don't
                    for id in theirIds {
                        needIds.append(id.hexEncodedString())
                    }
                    
                    print("[Negentropy] After ID list: have \(haveIds.count) to send, need \(needIds.count) to receive")
                } else {
                    doSkip()
                    
                    // Send our IDs
                    var responseIds = Data()
                    var numResponseIds = 0
                    var endBound = currBound
                    var actualUpper = upper
                    
                    try await storage.iterate(lower, upper) { item, index in
                        if exceededFrameSizeLimit(fullOutput.count + responseIds.count) {
                            endBound = NegentropyBound(timestamp: item.timestamp, id: item.id)
                            actualUpper = index
                            return false
                        }
                        
                        responseIds.append(item.id)
                        numResponseIds += 1
                        return true
                    }
                    
                    output.append(encodeBound(endBound))
                    output.append(encodeVarint(UInt64(NegentropyMode.idList)))
                    output.append(encodeVarint(UInt64(numResponseIds)))
                    output.append(responseIds)
                    
                    fullOutput.append(output)
                    output = Data()
                }
            } else {
                throw NegentropyError.protocolError("unexpected mode")
            }
            
            if exceededFrameSizeLimit(fullOutput.count + output.count) {
                // Frame size exceeded - send fingerprint for remaining range
                let remainingFingerprint = try await storage.fingerprint(upper, storageSize)
                
                fullOutput.append(encodeBound(NegentropyBound(timestamp: .max)))
                fullOutput.append(encodeVarint(UInt64(NegentropyMode.fingerprint)))
                fullOutput.append(remainingFingerprint)
                break
            } else {
                fullOutput.append(output)
            }
            
            prevIndex = upper
            prevBound = currBound
        }
        
        // If we only have the protocol version byte and nothing was processed, we're done
        // But if we have needs or haves, we should still return the response
        let finalOutput = (fullOutput.count == 1 && haveIds.isEmpty && needIds.isEmpty) ? nil : fullOutput
        
        if let output = finalOutput {
            print("[Negentropy] Sending response: \(output.hexEncodedString())")
        } else {
            print("[Negentropy] No response to send (reconciliation complete)")
        }
        
        return (finalOutput, haveIds, needIds)
    }
    
    // MARK: - Range Splitting
    
    private func splitRange(lower: Int, upper: Int, upperBound: NegentropyBound, output: inout Data) async throws {
        let numElems = upper - lower
        let buckets = 16
        
        // Always send ID list for small ranges or empty sets
        if numElems == 0 || numElems < buckets * 2 {
            // Small range or empty - send ID list
            output.append(encodeBound(upperBound))
            output.append(encodeVarint(UInt64(NegentropyMode.idList)))
            output.append(encodeVarint(UInt64(numElems)))
            
            // Only iterate if we have items
            if numElems > 0 {
                try await storage.iterate(lower, upper) { item in
                    output.append(item.id)
                    return true
                }
            }
        } else {
            // Large range - split into buckets
            let itemsPerBucket = numElems / buckets
            let bucketsWithExtra = numElems % buckets
            var curr = lower
            
            for i in 0..<buckets {
                let bucketSize = itemsPerBucket + (i < bucketsWithExtra ? 1 : 0)
                let ourFingerprint = try await storage.fingerprint(curr, curr + bucketSize)
                curr += bucketSize
                
                let nextBound: NegentropyBound
                if curr == upper {
                    nextBound = upperBound
                } else {
                    var prevItem: NegentropyItem?
                    var currItem: NegentropyItem?
                    
                    try await storage.iterate(curr - 1, curr + 1) { item, index in
                        if index == curr - 1 {
                            prevItem = item
                        } else {
                            currItem = item
                        }
                        return true
                    }
                    
                    guard let prev = prevItem, let curr = currItem else {
                        throw NegentropyError.protocolError("missing items")
                    }
                    
                    nextBound = getMinimalBound(prev: prev, curr: curr)
                }
                
                output.append(encodeBound(nextBound))
                output.append(encodeVarint(UInt64(NegentropyMode.fingerprint)))
                output.append(ourFingerprint)
            }
        }
    }
    
    private func getMinimalBound(prev: NegentropyItem, curr: NegentropyItem) -> NegentropyBound {
        if curr.timestamp != prev.timestamp {
            return NegentropyBound(timestamp: curr.timestamp)
        } else {
            var sharedPrefixBytes = 0
            for i in 0..<min(prev.id.count, curr.id.count) {
                if prev.id[i] != curr.id[i] { break }
                sharedPrefixBytes += 1
            }
            
            return NegentropyBound(
                timestamp: curr.timestamp,
                id: curr.id.prefix(sharedPrefixBytes + 1)
            )
        }
    }
    
    // MARK: - Encoding
    
    private func encodeTimestampOut(_ timestamp: UInt64) -> Data {
        if timestamp == .max {
            lastTimestampOut = .max
            return encodeVarint(0)
        }
        
        let temp = timestamp
        let delta = timestamp &- lastTimestampOut
        lastTimestampOut = temp
        return encodeVarint(delta &+ 1)
    }
    
    private func encodeBound(_ bound: NegentropyBound) -> Data {
        var output = Data()
        output.append(encodeTimestampOut(bound.timestamp))
        output.append(encodeVarint(UInt64(bound.id.count)))
        output.append(bound.id)
        return output
    }
    
    private func encodeVarint(_ value: UInt64) -> Data {
        if value == 0 { return Data([0]) }
        
        var bytes: [UInt8] = []
        var n = value
        
        while n != 0 {
            bytes.append(UInt8(n & 127))
            n >>= 7
        }
        
        bytes.reverse()
        
        for i in 0..<bytes.count - 1 {
            bytes[i] |= 128
        }
        
        return Data(bytes)
    }
    
    // MARK: - Decoding
    
    private func decodeTimestampIn(_ input: inout DataReader) throws -> UInt64 {
        guard let timestamp = decodeVarint(&input) else {
            throw NegentropyError.decodingError
        }
        
        let actualTimestamp = timestamp == 0 ? UInt64.max : timestamp - 1
        
        if lastTimestampIn == .max || actualTimestamp == .max {
            lastTimestampIn = .max
            return .max
        }
        
        let result = actualTimestamp &+ lastTimestampIn
        lastTimestampIn = result
        return result
    }
    
    private func decodeBound(_ input: inout DataReader) throws -> NegentropyBound {
        let timestamp = try decodeTimestampIn(&input)
        guard let len = decodeVarint(&input) else {
            print("[Negentropy] decodeBound: Failed to decode length")
            throw NegentropyError.decodingError
        }
        
        print("[Negentropy] decodeBound: timestamp=\(timestamp), id_length=\(len)")
        
        if len > ID_SIZE {
            print("[Negentropy] decodeBound: ID length \(len) exceeds maximum \(ID_SIZE)")
            throw NegentropyError.decodingError
        }
        
        guard let id = input.readBytes(Int(len)) else {
            print("[Negentropy] decodeBound: Failed to read \(len) bytes for ID, only \(input.remaining) bytes remaining")
            throw NegentropyError.decodingError
        }
        return NegentropyBound(timestamp: timestamp, id: id)
    }
    
    private func decodeVarint(_ input: inout DataReader) -> UInt64? {
        var result: UInt64 = 0
        
        while true {
            guard let byte = input.readByte() else { return nil }
            result = (result << 7) | UInt64(byte & 127)
            if (byte & 128) == 0 { break }
        }
        
        return result
    }
    
    private func exceededFrameSizeLimit(_ size: Int) -> Bool {
        return frameSizeLimit > 0 && size > frameSizeLimit - 200
    }
}

// MARK: - Storage Protocol Extensions

extension NegentropyStorage {
    func size() async throws -> Int {
        let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0))
        return items.count
    }
    
    func findLowerBound(_ start: Int, _ end: Int, _ bound: NegentropyBound) async throws -> Int {
        let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0))
        
        // Binary search for the first item >= bound
        var low = start
        var high = end
        
        while low < high {
            let mid = low + (high - low) / 2
            if mid >= items.count { return items.count }
            
            let item = items[mid]
            if item.timestamp < bound.timestamp ||
               (item.timestamp == bound.timestamp && compareData(item.id, bound.id) < 0) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        return low
    }
    
    func fingerprint(_ lower: Int, _ upper: Int) async throws -> Data {
        let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0))
        let rangeItems = Array(items[lower..<min(upper, items.count)])
        
        let accumulator = NegentropyAccumulator.from(rangeItems)
        return accumulator.fingerprint().prefix(FINGERPRINT_SIZE)
    }
    
    func iterate(_ lower: Int, _ upper: Int, _ callback: (NegentropyItem, Int) async throws -> Bool) async throws {
        let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0))
        
        for i in lower..<min(upper, items.count) {
            let shouldContinue = try await callback(items[i], i)
            if !shouldContinue { break }
        }
    }
    
    func iterate(_ lower: Int, _ upper: Int, _ callback: (NegentropyItem) async throws -> Bool) async throws {
        let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0))
        
        for i in lower..<min(upper, items.count) {
            let shouldContinue = try await callback(items[i])
            if !shouldContinue { break }
        }
    }
}

// MARK: - Helper Functions

func compareData(_ a: Data, _ b: Data) -> Int {
    // Handle empty data cases
    if a.isEmpty && b.isEmpty { return 0 }
    if a.isEmpty { return -1 }
    if b.isEmpty { return 1 }
    
    // Ensure we have valid data
    guard a.count > 0 && b.count > 0 else {
        return a.count - b.count
    }
    
    // Compare bytes up to the length of the shorter data
    let minLength = min(a.count, b.count)
    
    // Use safe comparison
    let aBytes = Array(a)
    let bBytes = Array(b)
    
    for i in 0..<minLength {
        if aBytes[i] < bBytes[i] { return -1 }
        if aBytes[i] > bBytes[i] { return 1 }
    }
    
    // If all compared bytes are equal, the shorter one is "less than"
    if a.count < b.count { return -1 }
    if a.count > b.count { return 1 }
    return 0
}

// MARK: - Data Reader Helper

struct DataReader {
    private var data: Data
    private var position = 0
    
    init(_ data: Data) {
        self.data = data
    }
    
    var hasMore: Bool {
        return position < data.count
    }
    
    var remaining: Int {
        return data.count - position
    }
    
    mutating func readByte() -> UInt8? {
        guard position < data.count else { return nil }
        let byte = data[position]
        position += 1
        return byte
    }
    
    mutating func readBytes(_ count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        let bytes = data[position..<position + count]
        position += count
        return bytes
    }
}