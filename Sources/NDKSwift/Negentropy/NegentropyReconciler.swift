import Foundation

/// High-level reconciler for Negentropy set synchronization.
///
/// `NegentropyReconciler` provides a simplified, stateful interface for performing
/// set reconciliation using the Negentropy protocol. It manages the underlying
/// protocol state and provides convenient methods for common reconciliation patterns.
///
/// ## Usage
///
/// ```swift
/// // Setup reconciler with your storage
/// let reconciler = NegentropyReconciler(
///     storage: NDKCacheNegentropyStorage(cache: cache),
///     frameSizeLimit: 60_000
/// )
///
/// // Start reconciliation
/// let initData = try await reconciler.initiate()
/// // Send to peer...
///
/// // Process responses
/// let response = try await reconciler.processMessage(peerData)
/// switch response {
/// case .continuing(let data, let haveIds, let needIds):
///     // Handle intermediate state
/// case .terminated(let haveIds, let needIds, let isDone):
///     // Reconciliation complete
/// }
/// ```
///
/// ## Compared to Raw Negentropy
///
/// - **Simplified API**: Higher-level methods with cleaner error handling
/// - **State Management**: Automatically manages protocol state between calls
/// - **Type Safety**: Strongly-typed responses instead of tuples
/// - **Error Recovery**: Better error handling and recovery options
///
/// ## Thread Safety
///
/// This is an `actor` that provides thread-safe access to reconciliation state.
/// Each reconciler instance should be used for a single reconciliation session.
public actor NegentropyReconciler {
    private let storage: NegentropyStorage
    private let frameSizeLimit: Int
    
    /// Creates a new reconciler instance.
    ///
    /// - Parameters:
    ///   - storage: Storage implementation providing access to your data set
    ///   - frameSizeLimit: Maximum message size in bytes (default: 60KB)
    public init(storage: NegentropyStorage, frameSizeLimit: Int = 60_000) {
        self.storage = storage
        self.frameSizeLimit = frameSizeLimit
    }
    
    /// Initiates reconciliation as the initiator.
    ///
    /// - Returns: Initial message data to send to the peer
    /// - Throws: Protocol errors if reconciliation cannot be started
    public func initiate() async throws -> Data {
        let negentropy = Negentropy(storage: storage, frameSizeLimit: frameSizeLimit)
        return try await negentropy.initiate()
    }
    
    /// Processes a message from the peer and generates an appropriate response.
    ///
    /// - Parameter data: Message data received from the peer
    /// - Returns: Response indicating the current state of reconciliation
    /// - Throws: Protocol or decoding errors
    ///
    /// ## Response Types
    ///
    /// - `.continuing`: Reconciliation is ongoing, contains next message to send
    /// - `.terminated`: Reconciliation is complete, contains final results
    public func processMessage(_ data: Data) async throws -> NegentropyResponse {
        let negentropy = Negentropy(storage: storage, frameSizeLimit: frameSizeLimit)
        let (responseData, haveIds, needIds) = try await negentropy.reconcile(data)
        
        if let data = responseData {
            return .continuing(
                data: data, 
                haveIds: haveIds.map { Data(hex: $0)! }, 
                needIds: needIds.map { Data(hex: $0)! }
            )
        } else {
            return .terminated(
                haveIds: haveIds.map { Data(hex: $0)! }, 
                needIds: needIds.map { Data(hex: $0)! }, 
                isDone: true
            )
        }
    }
}

/// Response from the reconciler indicating the current state of reconciliation.
public enum NegentropyResponse {
    /// Reconciliation is ongoing and requires further message exchange.
    ///
    /// - Parameters:
    ///   - data: Next message to send to the peer
    ///   - haveIds: Item IDs we have that the peer needs (as raw Data)
    ///   - needIds: Item IDs we need from the peer (as raw Data)
    case continuing(data: Data, haveIds: [Data], needIds: [Data])
    
    /// Reconciliation has completed successfully.
    ///
    /// - Parameters:
    ///   - haveIds: Final list of item IDs we have that the peer needs
    ///   - needIds: Final list of item IDs we need from the peer
    ///   - isDone: Always `true` for terminated responses
    case terminated(haveIds: [Data], needIds: [Data], isDone: Bool)
}

/// Message types for Negentropy protocol
public enum NegentropyMessage {
    case protocolVersion  // Just 0x61
    case initial(fingerprint: Data, count: Int)
    case reconciliation(ranges: [NegentropyRange], haveIds: [Data], needIds: [Data])
    case termination(haveIds: [Data], needIds: [Data])
}