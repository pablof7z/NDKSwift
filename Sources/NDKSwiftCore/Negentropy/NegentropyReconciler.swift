import Foundation

/// High-level reconciler for Negentropy set synchronization.
///
/// `NegentropyReconciler` provides a simplified, stateful interface for performing
/// set reconciliation using the Negentropy protocol. Each instance represents a single
/// reconciliation session and maintains protocol state throughout the exchange.
///
/// ## Usage
///
/// ```swift
/// // Create a new reconciler for each reconciliation session
/// let reconciler = NegentropyReconciler(
///     storage: NDKCacheNegentropyStorage(cache: cache),
///     frameSizeLimit: 60_000
/// )
///
/// // As initiator:
/// let initData = try await reconciler.initiate()
/// // Send to peer...
///
/// // Or as responder, directly process first message:
/// let response = try await reconciler.processMessage(peerData)
///
/// // Continue processing messages until terminated
/// while case .continuing(let data, _, _) = response {
///     // Send data to peer and get their response
///     let peerResponse = await sendToPeer(data)
///     response = try await reconciler.processMessage(peerResponse)
/// }
/// ```
///
/// ## Important
///
/// - Each `NegentropyReconciler` instance is for a **single reconciliation session**
/// - Create a new instance for each new reconciliation
/// - The instance maintains state throughout the message exchange
/// - Can be used as either initiator or responder
///
/// ## Compared to Raw Negentropy
///
/// - **Simplified API**: Higher-level methods with cleaner error handling
/// - **State Management**: Automatically manages protocol state between calls
/// - **Type Safety**: Strongly-typed responses instead of tuples
/// - **Role Flexibility**: Can act as initiator or responder
///
/// ## Thread Safety
///
/// This is an `actor` that provides thread-safe access to reconciliation state.
public actor NegentropyReconciler {
    private let negentropy: Negentropy
    private var isInitiated = false

    /// Creates a new reconciler instance for a single reconciliation session.
    ///
    /// - Parameters:
    ///   - storage: Storage implementation providing access to your data set
    ///   - frameSizeLimit: Maximum message size in bytes (default: 60KB)
    ///
    /// - Important: Create a new instance for each reconciliation session
    public init(storage: NegentropyStorage, frameSizeLimit: Int = 60000) {
        negentropy = Negentropy(storage: storage, frameSizeLimit: frameSizeLimit)
    }

    /// Initiates reconciliation as the initiator.
    ///
    /// - Returns: Initial message data to send to the peer
    /// - Throws: `NegentropyError.protocolError` if already initiated or used as responder
    ///
    /// - Important: Can only be called once per instance. Creates a new reconciler for each session.
    public func initiate() async throws -> Data {
        guard !isInitiated else {
            throw NegentropyError.protocolError("Reconciler already initiated. Create a new instance for each reconciliation session.")
        }
        isInitiated = true
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
    ///
    /// ## Usage Patterns
    ///
    /// As initiator:
    /// 1. Call `initiate()` first
    /// 2. Send the result to peer
    /// 3. Process peer's response with this method
    ///
    /// As responder:
    /// 1. Directly call this method with peer's initial message
    /// 2. Continue the exchange until terminated
    public func processMessage(_ data: Data) async throws -> NegentropyResponse {
        // Mark as initiated if this is the first call (responder role)
        if !isInitiated {
            isInitiated = true
        }

        let (responseData, haveIds, needIds) = try await negentropy.reconcile(data)

        if let data = responseData {
            return .continuing(
                data: data,
                haveIds: haveIds.compactMap { Data(hexString: $0) },
                needIds: needIds.compactMap { Data(hexString: $0) }
            )
        } else {
            return .terminated(
                haveIds: haveIds.compactMap { Data(hexString: $0) },
                needIds: needIds.compactMap { Data(hexString: $0) },
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
    case protocolVersion // Just 0x61
    case initial(fingerprint: Data, count: Int)
    case reconciliation(ranges: [NegentropyRange], haveIds: [Data], needIds: [Data])
    case termination(haveIds: [Data], needIds: [Data])
}
