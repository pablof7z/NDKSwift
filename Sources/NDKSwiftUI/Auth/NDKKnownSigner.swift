import Foundation

/// A known iOS NIP-46 signer app that can be probed via custom URL scheme and handed off to.
///
/// This is presentation metadata for the "is signer X installed → tap to hand off" UX. It is *not*
/// a security boundary: any app on the device can claim a URL scheme. Treat the registry as a
/// convenience shortcut for users who have an installed signer; the bunker:// / nostrconnect://
/// QR-and-paste flows remain the source of truth.
///
/// To detect installed signers at runtime, the host app **must** list each `urlScheme` under
/// `LSApplicationQueriesSchemes` in its Info.plist. Otherwise `UIApplication.canOpenURL` returns
/// `false` even when the signer is installed. See ``NDKLocalSigner``.
public struct NDKKnownSigner: Sendable, Hashable, Identifiable {
    /// Stable identifier (e.g. `"amber"`, `"primal"`, `"nsec.app"`).
    public let id: String

    /// Human-readable name shown in UI.
    public let displayName: String

    /// Custom URL scheme registered by the signer app, without `://`. Used by both
    /// `UIApplication.canOpenURL` probing and the deep-link handoff.
    public let urlScheme: String

    /// SF Symbol used when the host app has no bundled asset for this signer.
    public let sfSymbolFallback: String

    /// Optional bundled image asset name. Hosts that want branded icons can ship matching assets
    /// (e.g. `"PrimalLogo"`) — the registry doesn't ship images itself.
    public let iconAssetName: String?

    /// Relay hints the signer prefers. Apps may pass these to ``NDKBunkerSigner/nostrConnect``
    /// when the user explicitly chose this signer. Empty means no hint.
    public let preferredRelays: [String]

    public init(
        id: String,
        displayName: String,
        urlScheme: String,
        sfSymbolFallback: String = "key.fill",
        iconAssetName: String? = nil,
        preferredRelays: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.urlScheme = urlScheme
        self.sfSymbolFallback = sfSymbolFallback
        self.iconAssetName = iconAssetName
        self.preferredRelays = preferredRelays
    }
}

public extension NDKKnownSigner {
    /// Amber (Android-only — included for completeness; iOS detection will always be false).
    static let amber = NDKKnownSigner(
        id: "amber",
        displayName: "Amber",
        urlScheme: "nostrsigner",
        sfSymbolFallback: "key.fill"
    )

    /// Primal iOS signer. Reads `callback=` query parameter to return to the host app.
    static let primal = NDKKnownSigner(
        id: "primal",
        displayName: "Primal",
        urlScheme: "primal",
        sfSymbolFallback: "bolt.fill",
        preferredRelays: ["wss://relay.primal.net"]
    )

    /// nsec.app — web-based signer using `auth_url` challenges over NIP-46.
    static let nsecApp = NDKKnownSigner(
        id: "nsec.app",
        displayName: "nsec.app",
        urlScheme: "nostrconnect",
        sfSymbolFallback: "globe"
    )

    /// Default seed list of known iOS-relevant signers.
    ///
    /// Seed data, not architecture: apps can supply their own array to ``NDKLocalSigner`` and the
    /// connect model. Future versions may augment this with NIP-89 `kind:31990` discovery.
    static let allKnown: [NDKKnownSigner] = [.amber, .primal, .nsecApp]
}
