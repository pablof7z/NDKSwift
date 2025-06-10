import Foundation

/// Configuration for signature verification sampling
public struct NDKSignatureVerificationConfig {
    /// The signature verification validation ratio for new relays (1.0 = verify all)
    public var initialValidationRatio: Double

    /// The lowest validation ratio any single relay can have
    public var lowestValidationRatio: Double

    /// When true, automatically blacklist relays that provide events with invalid signatures
    public var autoBlacklistInvalidRelays: Bool

    /// Custom function to calculate validation ratio
    public var validationRatioFunction: ((RelayProtocol, Int, Int) -> Double)?

    /// Default configuration with full signature verification
    public static let `default` = NDKSignatureVerificationConfig(
        initialValidationRatio: 1.0,
        lowestValidationRatio: 0.1,
        autoBlacklistInvalidRelays: false,
        validationRatioFunction: nil
    )

    /// Configuration that disables all signature verification (use with extreme caution)
    public static let disabled = NDKSignatureVerificationConfig(
        initialValidationRatio: 0.0,
        lowestValidationRatio: 0.0,
        autoBlacklistInvalidRelays: false,
        validationRatioFunction: nil
    )
}

/// Statistics for signature verification on a relay
public struct NDKRelaySignatureStats {
    /// Number of events that had their signatures validated
    public private(set) var validatedCount: Int = 0

    /// Number of events that were not validated (sampling skipped them)
    public private(set) var nonValidatedCount: Int = 0

    /// Current validation ratio for this relay
    public private(set) var currentValidationRatio: Double = 1.0

    /// Total events processed
    public var totalEvents: Int {
        return validatedCount + nonValidatedCount
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
}

/// Result of a signature verification attempt
public enum NDKSignatureVerificationResult {
    case valid
    case invalid
    case skipped // Skipped due to sampling
    case cached // Already verified (cached result)
}

/// Protocol for signature verification delegate
public protocol NDKSignatureVerificationDelegate: AnyObject {
    /// Called when an invalid signature is detected
    /// - Parameters:
    ///   - event: The event with invalid signature
    ///   - relay: The relay that provided the invalid signature
    func signatureVerificationFailed(for event: NDKEvent, from relay: RelayProtocol)

    /// Called when a relay is blacklisted for providing invalid signatures
    /// - Parameter relay: The blacklisted relay
    func relayBlacklisted(_ relay: RelayProtocol)
}
