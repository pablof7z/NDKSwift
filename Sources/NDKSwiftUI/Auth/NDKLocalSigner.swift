import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// Probes the device for installed NIP-46 signer apps using their custom URL schemes.
///
/// ## Required host setup
///
/// `UIApplication.canOpenURL` silently returns `false` for any scheme that is not declared in the
/// host app's `Info.plist > LSApplicationQueriesSchemes`. If you intend to detect Amber, Primal,
/// etc., add the relevant entries — otherwise detection will fail silently. ``detect(from:)`` will
/// log a one-shot diagnostic when this footgun is the most likely cause.
@MainActor
public enum NDKLocalSigner {
    private static let logger = Logger(subsystem: "NDKSwiftUI", category: "LocalSigner")
    nonisolated(unsafe) private static var didWarnAboutMissingQueriesSchemes = false

    /// Returns `true` if a signer app advertising `signer.urlScheme` is installed on the device.
    ///
    /// On platforms without UIKit (macOS, Linux) this always returns `false`.
    public static func isInstalled(_ signer: NDKKnownSigner) -> Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "\(signer.urlScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    /// Returns the first signer from `registry` whose URL scheme `canOpenURL` accepts, or `nil`.
    ///
    /// Order is significant: pass the registry sorted by user preference (most-specific first).
    /// If zero schemes resolve and there is reason to believe at least one signer should be
    /// installed, emit a one-shot warning pointing at the most common cause: missing
    /// `LSApplicationQueriesSchemes` entries in `Info.plist`.
    public static func detect(from registry: [NDKKnownSigner] = NDKKnownSigner.allKnown) -> NDKKnownSigner? {
        #if canImport(UIKit)
        for signer in registry where isInstalled(signer) {
            return signer
        }
        warnIfQueriesSchemesLikelyMissing(probed: registry)
        return nil
        #else
        return nil
        #endif
    }

    /// Returns every signer from `registry` whose URL scheme `canOpenURL` accepts. Useful when
    /// presenting a chooser of all installed signers rather than auto-picking one.
    public static func allInstalled(from registry: [NDKKnownSigner] = NDKKnownSigner.allKnown) -> [NDKKnownSigner] {
        #if canImport(UIKit)
        let installed = registry.filter(isInstalled)
        if installed.isEmpty {
            warnIfQueriesSchemesLikelyMissing(probed: registry)
        }
        return installed
        #else
        return []
        #endif
    }

    private static func warnIfQueriesSchemesLikelyMissing(probed: [NDKKnownSigner]) {
        guard !didWarnAboutMissingQueriesSchemes else { return }

        let declared = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
        let missing = probed.map(\.urlScheme).filter { !declared.contains($0) }
        guard !missing.isEmpty else { return }

        didWarnAboutMissingQueriesSchemes = true
        logger.warning("""
            No NIP-46 signer detected via canOpenURL. Likely cause: these schemes are not in your \
            Info.plist > LSApplicationQueriesSchemes — \(missing, privacy: .public). \
            Without these entries, canOpenURL returns false even when the signer is installed.
            """)
    }
}
