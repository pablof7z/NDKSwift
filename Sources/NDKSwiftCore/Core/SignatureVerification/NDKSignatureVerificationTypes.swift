/// Configuration for signature verification sampling
///
/// This configuration controls how NDK verifies event signatures from relays.
/// By default, all signatures are verified, but you can configure sampling
/// to improve performance at the cost of some security.
///
/// Example:
/// ```swift
/// let config = NDKSignatureVerificationConfig(
///     initialValidationRatio: 0.5,  // Verify 50% of events from new relays
///     lowestValidationRatio: 0.1,   // Never go below 10% verification
///     autoBlocklistInvalidRelays: true  // Auto-blocklist bad relays
/// )
/// ```
public struct NDKSignatureVerificationConfig: Sendable {
    /// The signature verification validation ratio for new relays (1.0 = verify all)
    public var initialValidationRatio: Double

    /// The lowest validation ratio any single relay can have
    public var lowestValidationRatio: Double

    /// When true, automatically blocklist relays that provide events with invalid signatures
    public var autoBlocklistInvalidRelays: Bool

    /// Custom function to calculate validation ratio
    public var validationRatioFunction: (@Sendable (RelayProtocol, Int, Int) -> Double)?

    /// Default configuration with full signature verification
    public static let `default` = NDKSignatureVerificationConfig(
        initialValidationRatio: 1.0,
        lowestValidationRatio: 0.1,
        autoBlocklistInvalidRelays: false,
        validationRatioFunction: nil
    )

    /// Configuration that disables all signature verification (use with extreme caution)
    public static let disabled = NDKSignatureVerificationConfig(
        initialValidationRatio: 0.0,
        lowestValidationRatio: 0.0,
        autoBlocklistInvalidRelays: false,
        validationRatioFunction: nil
    )
}

/// Statistics for signature verification on a relay
public struct NDKRelaySignatureStats: Sendable, Equatable {
    /// Number of events that had their signatures validated
    public private(set) var validatedCount: Int = 0

    /// Number of events that were not validated (sampling skipped them)
    public private(set) var nonValidatedCount: Int = 0

    /// Current validation ratio for this relay
    public private(set) var currentValidationRatio: Double = 1.0

    /// User-configured target validation ratio for this relay (nil = use global default)
    public var targetValidationRatio: Double?

    /// Whether signature verification is enabled for this relay
    public var verificationEnabled: Bool = true

    /// Public initializer
    public init() {}

    /// Total events processed
    public var totalEvents: Int {
        return validatedCount + nonValidatedCount
    }

    /// Effective validation ratio (uses target if set, otherwise current)
    public var effectiveValidationRatio: Double {
        if !verificationEnabled { return 0.0 }
        return targetValidationRatio ?? currentValidationRatio
    }

    /// Add a validated event
    mutating func addValidatedEvent() {
        validatedCount += 1
    }

    /// Add a non-validated event
    mutating func addNonValidatedEvent() {
        nonValidatedCount += 1
    }

    /// Update the validation ratio
    mutating func updateValidationRatio(_ ratio: Double) {
        currentValidationRatio = ratio
    }

    /// Set the target validation ratio for this relay
    public mutating func setTargetValidationRatio(_ ratio: Double?) {
        targetValidationRatio = ratio
    }

    /// Enable or disable signature verification for this relay
    public mutating func setVerificationEnabled(_ enabled: Bool) {
        verificationEnabled = enabled
    }
}

/// Result of a signature verification attempt
///
/// Indicates the outcome of verifying an event's signature.
/// Signatures may be skipped for performance reasons based on sampling configuration.
public enum NDKSignatureVerificationResult: Sendable {
    /// Signature was verified and is valid
    case valid
    /// Signature was verified and is invalid
    case invalid
    /// Signature verification was skipped due to sampling configuration
    case skipped
    /// Signature was already verified (result from cache)
    case cached
}

/// Protocol for signature verification delegate
///
/// Implement this protocol to receive notifications about signature verification
/// failures and relay blocklisting. This is useful for monitoring relay behavior
/// and taking custom actions when invalid signatures are detected.
///
/// Example implementation:
/// ```swift
/// class MyVerificationDelegate: NDKSignatureVerificationDelegate {
///     func signatureVerificationFailed(for event: NDKEvent, from relay: RelayProtocol) {
///         print("Invalid signature detected from \(relay.url)")
///         // Log to analytics, notify user, etc.
///     }
///
///     func relayBlocklisted(_ relay: RelayProtocol) {
///         print("Relay blocklisted: \(relay.url)")
///         // Update UI, save to persistent blocklist, etc.
///     }
/// }
/// ```
public protocol NDKSignatureVerificationDelegate: AnyObject, Sendable {
    /// Called when an invalid signature is detected
    ///
    /// This method is called on the main thread when signature verification fails.
    /// The event will not be processed further by NDK.
    ///
    /// - Parameters:
    ///   - event: The event with invalid signature
    ///   - relay: The relay that provided the invalid signature
    func signatureVerificationFailed(for event: NDKEvent, from relay: RelayProtocol)

    /// Called when a relay is blocklisted for providing invalid signatures
    ///
    /// This occurs when `autoBlocklistInvalidRelays` is enabled in the configuration
    /// and a relay provides an event with an invalid signature.
    ///
    /// - Parameter relay: The blocklisted relay
    func relayBlocklisted(_ relay: RelayProtocol)
}
