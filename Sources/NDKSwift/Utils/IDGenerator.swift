/// Simple ID generator for Nostr subscriptions and requests
/// Uses connection-scoped counters for efficiency
public actor IDGenerator {
    private var subscriptionCounter: Int64 = 0
    private var requestCounter: Int64 = 0

    /// Generate a unique subscription ID
    public func nextSubscriptionId() -> String {
        subscriptionCounter += 1
        return "sub\(subscriptionCounter)"
    }

    /// Generate a unique request ID (for RPC and other uses)
    public func nextRequestId() -> String {
        requestCounter += 1
        return "req\(requestCounter)"
    }

    /// Generate a random ID (for cases where sequential IDs are not suitable)
    public static func randomId(prefix: String = "", length: Int = 8) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomString = String((0..<length).map { _ in characters.randomElement()! })
        return prefix.isEmpty ? randomString : "\(prefix)_\(randomString)"
    }
}

/// Global shared ID generator for convenience
public let sharedIDGenerator = IDGenerator()
