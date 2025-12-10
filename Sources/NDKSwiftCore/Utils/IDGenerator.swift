/// Thread-safe ID generator for Nostr subscriptions and requests
///
/// This actor provides a centralized way to generate unique identifiers for various
/// Nostr protocol operations. It uses connection-scoped counters for efficiency
/// and ensures thread safety through Swift's actor model.
///
/// ## Usage
///
/// ```swift
/// // Using the shared instance
/// let subId = await sharedIDGenerator.nextSubscriptionId() // "sub1"
/// let reqId = await sharedIDGenerator.nextRequestId()       // "req1"
///
/// // Creating a custom instance for isolated contexts
/// let generator = IDGenerator()
/// let id = await generator.nextSubscriptionId()
/// ```
///
/// ## ID Formats
///
/// - Subscription IDs: `sub{counter}` (e.g., "sub1", "sub2", ...)
/// - Request IDs: `req{counter}` (e.g., "req1", "req2", ...)
/// - Random IDs: `{prefix}_{random}` or just `{random}` if no prefix
///
/// The sequential IDs are preferred for most use cases as they are shorter
/// and more efficient. Random IDs should only be used when sequential IDs
/// might cause collisions across different contexts.
public actor IDGenerator {
    private var subscriptionCounter: Int64 = 0
    private var requestCounter: Int64 = 0

    /// Generate a unique subscription ID
    ///
    /// Returns a sequential ID in the format "sub{n}" where n is an incrementing counter.
    /// These IDs are connection-scoped and reset when the generator is recreated.
    ///
    /// - Returns: A unique subscription identifier
    public func nextSubscriptionId() -> String {
        subscriptionCounter += 1
        return "sub\(subscriptionCounter)"
    }

    /// Generate a unique request ID for RPC and other uses
    ///
    /// Returns a sequential ID in the format "req{n}" where n is an incrementing counter.
    /// These IDs are connection-scoped and reset when the generator is recreated.
    ///
    /// - Returns: A unique request identifier
    public func nextRequestId() -> String {
        requestCounter += 1
        return "req\(requestCounter)"
    }

    /// Generate a random ID for cases where sequential IDs are not suitable
    ///
    /// Creates a random alphanumeric string of the specified length, optionally
    /// prefixed with a custom string. This is useful when IDs need to be globally
    /// unique across different connections or contexts.
    ///
    /// - Parameters:
    ///   - prefix: Optional prefix to prepend to the random string (separated by underscore)
    ///   - length: Length of the random portion (default: 8 characters)
    /// - Returns: A random identifier string
    ///
    /// ## Example
    /// ```swift
    /// let id1 = IDGenerator.randomId()                    // "x7k9m2p5"
    /// let id2 = IDGenerator.randomId(prefix: "auth")      // "auth_j3n8q1w6"
    /// let id3 = IDGenerator.randomId(prefix: "req", length: 12) // "req_a5b8c2d9e1f4"
    /// ```
    public static func randomId(prefix: String = "", length: Int = 8) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomString = String((0..<length).compactMap { _ in characters.randomElement() })
        return prefix.isEmpty ? randomString : "\(prefix)_\(randomString)"
    }
}

/// Global shared ID generator for convenience
///
/// This shared instance can be used throughout the application for generating
/// IDs without needing to manage separate generator instances. It's particularly
/// useful for single-connection scenarios.
///
/// For multi-connection scenarios where ID isolation is important, create
/// separate IDGenerator instances for each connection.
public let sharedIDGenerator = IDGenerator()
