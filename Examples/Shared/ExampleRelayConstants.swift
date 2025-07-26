import Foundation
import NDKSwift

/// Shared relay constants for use in examples and apps
public struct ExampleRelayConstants {
    
    /// Default set of relays commonly used in examples
    public static let defaultRelays = [
        RelayConstants.damus,
        RelayConstants.primal,
        RelayConstants.nosLol,
        RelayConstants.nostrWine
    ]
    
    /// Minimal set for testing (2 relays)
    public static let minimalRelays = [
        RelayConstants.damus,
        RelayConstants.nosLol
    ]
    
    /// Extended set including specialized relays
    public static let extendedRelays = [
        RelayConstants.damus,
        RelayConstants.primal,
        RelayConstants.nosLol,
        RelayConstants.nostrWine,
        RelayConstants.nostrBand,
        RelayConstants.snort
    ]
    
    /// Relays optimized for media content
    public static let mediaRelays = [
        RelayConstants.primal,
        RelayConstants.damus,
        RelayConstants.nosLol,
        RelayConstants.nostrBand
    ]
    
    /// Test relays for E2E tests
    public static let testRelays = [
        RelayConstants.damus,
        RelayConstants.nostrBand,
        RelayConstants.nosLol
    ]
}