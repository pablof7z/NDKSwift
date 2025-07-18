import Foundation

/// The main Negentropy reconciler that implements the set reconciliation protocol
public actor NegentropyReconciler {
    private let storage: NegentropyStorage
    private let frameSizeLimit: Int
    
    /// Current reconciliation state
    private var pendingRanges: [NegentropyRange] = []
    private var isInitiator: Bool = false
    
    public init(storage: NegentropyStorage, frameSizeLimit: Int = 60_000) {
        self.storage = storage
        self.frameSizeLimit = frameSizeLimit
    }
    
    /// Initialize reconciliation as initiator
    public func initiate() async throws -> Data {
        isInitiator = true
        
        // Start with full range
        let fullRange = NegentropyRange(
            lower: nil,
            upper: nil,
            fingerprint: Data(),
            count: 0
        )
        
        let (fingerprint, count) = try await storage.getRangeInfo(fullRange)
        let rangeWithInfo = NegentropyRange(
            lower: nil,
            upper: nil,
            fingerprint: fingerprint,
            count: count
        )
        
        pendingRanges = [rangeWithInfo]
        
        return try NegentropyEncoder.encodeInitialMessage(fingerprint: fingerprint, count: count)
    }
    
    /// Process a message and generate response
    public func processMessage(_ data: Data) async throws -> NegentropyResponse {
        let message = try NegentropyDecoder.decode(data)
        
        switch message {
        case .initial(let theirFingerprint, let theirCount):
            return try await handleInitialMessage(theirFingerprint: theirFingerprint, theirCount: theirCount)
            
        case .reconciliation(let ranges, let haveIds, let needIds):
            return try await handleReconciliationMessage(ranges: ranges, haveIds: haveIds, needIds: needIds)
            
        case .termination(let haveIds, let needIds):
            return handleTerminationMessage(haveIds: haveIds, needIds: needIds)
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleInitialMessage(theirFingerprint: Data, theirCount: Int) async throws -> NegentropyResponse {
        let fullRange = NegentropyRange(lower: nil, upper: nil, fingerprint: Data(), count: 0)
        let (ourFingerprint, ourCount) = try await storage.getRangeInfo(fullRange)
        
        // If fingerprints match, we're in sync
        if ourFingerprint == theirFingerprint {
            return .terminated(haveIds: [], needIds: [], isDone: true)
        }
        
        // Otherwise, start reconciliation
        let rangeWithInfo = NegentropyRange(
            lower: nil,
            upper: nil,
            fingerprint: ourFingerprint,
            count: ourCount
        )
        
        pendingRanges = [rangeWithInfo]
        
        // Split the range and send our side
        let response = try await splitAndEncodeRanges()
        return .continuing(data: response, haveIds: [], needIds: [])
    }
    
    private func handleReconciliationMessage(
        ranges: [NegentropyRange],
        haveIds: [Data],
        needIds: [Data]
    ) async throws -> NegentropyResponse {
        var newPendingRanges: [NegentropyRange] = []
        var responseRanges: [NegentropyRange] = []
        var ourHaveIds: [Data] = []
        var ourNeedIds: [Data] = []
        
        // Process each range they sent
        for theirRange in ranges {
            // Find our corresponding range
            guard let ourRange = pendingRanges.first(where: { range in
                rangesOverlap(range, theirRange)
            }) else {
                throw NegentropyError.protocolError("Range mismatch")
            }
            
            let (ourFingerprint, ourCount) = try await storage.getRangeInfo(theirRange)
            
            // If fingerprints match, this range is in sync
            if ourFingerprint == theirRange.fingerprint {
                continue
            }
            
            // If the range is small enough, just send the items
            if ourCount < 10 || theirRange.count < 10 {
                let items = try await storage.getItems(in: theirRange)
                for item in items {
                    ourHaveIds.append(item.id)
                }
            } else {
                // Split the range further
                let midpoint = try await findMidpoint(in: theirRange)
                let (lowerRange, upperRange) = theirRange.split(at: midpoint)
                
                let (lowerFingerprint, lowerCount) = try await storage.getRangeInfo(lowerRange)
                let (upperFingerprint, upperCount) = try await storage.getRangeInfo(upperRange)
                
                responseRanges.append(NegentropyRange(
                    lower: lowerRange.lower,
                    upper: lowerRange.upper,
                    fingerprint: lowerFingerprint,
                    count: lowerCount
                ))
                
                responseRanges.append(NegentropyRange(
                    lower: upperRange.lower,
                    upper: upperRange.upper,
                    fingerprint: upperFingerprint,
                    count: upperCount
                ))
                
                newPendingRanges.append(lowerRange)
                newPendingRanges.append(upperRange)
            }
        }
        
        // Update pending ranges
        pendingRanges = newPendingRanges
        
        // Check if we're done
        if responseRanges.isEmpty && ourHaveIds.isEmpty && ourNeedIds.isEmpty {
            return .terminated(haveIds: haveIds, needIds: needIds, isDone: true)
        }
        
        // Encode response
        let responseData = try NegentropyEncoder.encodeReconciliationMessage(
            ranges: responseRanges,
            haveIds: ourHaveIds,
            needIds: ourNeedIds,
            frameSizeLimit: frameSizeLimit
        )
        
        return .continuing(data: responseData, haveIds: haveIds, needIds: needIds)
    }
    
    private func handleTerminationMessage(haveIds: [Data], needIds: [Data]) -> NegentropyResponse {
        return .terminated(haveIds: haveIds, needIds: needIds, isDone: true)
    }
    
    // MARK: - Helper Methods
    
    private func splitAndEncodeRanges() async throws -> Data {
        var responseRanges: [NegentropyRange] = []
        var newPendingRanges: [NegentropyRange] = []
        
        for range in pendingRanges {
            let (_, count) = try await storage.getRangeInfo(range)
            
            if count <= 10 {
                // Small range, will send items directly later
                responseRanges.append(range)
            } else {
                // Split the range
                let midpoint = try await findMidpoint(in: range)
                let (lowerRange, upperRange) = range.split(at: midpoint)
                
                let (lowerFingerprint, lowerCount) = try await storage.getRangeInfo(lowerRange)
                let (upperFingerprint, upperCount) = try await storage.getRangeInfo(upperRange)
                
                let lowerWithInfo = NegentropyRange(
                    lower: lowerRange.lower,
                    upper: lowerRange.upper,
                    fingerprint: lowerFingerprint,
                    count: lowerCount
                )
                
                let upperWithInfo = NegentropyRange(
                    lower: upperRange.lower,
                    upper: upperRange.upper,
                    fingerprint: upperFingerprint,
                    count: upperCount
                )
                
                responseRanges.append(lowerWithInfo)
                responseRanges.append(upperWithInfo)
                newPendingRanges.append(lowerWithInfo)
                newPendingRanges.append(upperWithInfo)
            }
        }
        
        pendingRanges = newPendingRanges
        
        return try NegentropyEncoder.encodeReconciliationMessage(
            ranges: responseRanges,
            haveIds: [],
            needIds: [],
            frameSizeLimit: frameSizeLimit
        )
    }
    
    private func findMidpoint(in range: NegentropyRange) async throws -> NegentropyItem {
        let items = try await storage.getItems(in: range)
        guard !items.isEmpty else {
            throw NegentropyError.protocolError("Cannot find midpoint in empty range")
        }
        
        let midIndex = items.count / 2
        return items[midIndex]
    }
    
    private func rangesOverlap(_ a: NegentropyRange, _ b: NegentropyRange) -> Bool {
        // Check if ranges overlap
        if let aUpper = a.upper, let bLower = b.lower, aUpper <= bLower {
            return false
        }
        if let bUpper = b.upper, let aLower = a.lower, bUpper <= aLower {
            return false
        }
        return true
    }
}

/// Response from the reconciler
public enum NegentropyResponse {
    case continuing(data: Data, haveIds: [Data], needIds: [Data])
    case terminated(haveIds: [Data], needIds: [Data], isDone: Bool)
}

/// Message types for Negentropy protocol
enum NegentropyMessage {
    case initial(fingerprint: Data, count: Int)
    case reconciliation(ranges: [NegentropyRange], haveIds: [Data], needIds: [Data])
    case termination(haveIds: [Data], needIds: [Data])
}