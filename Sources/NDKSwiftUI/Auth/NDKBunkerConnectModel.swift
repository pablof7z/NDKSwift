import Combine
import Foundation
import NDKSwiftCore
import OSLog
import SwiftUI

/// SwiftUI-friendly orchestrator for the `nostrconnect://` (NIP-46) login flow.
///
/// This is a thin `@Observable` wrapper over ``NDKBunkerSigner/nostrConnect(ndk:relays:localSigner:options:)``.
/// Non-UI callers should prefer that async API directly; ``NDKBunkerConnectModel`` exists to bind
/// the connect lifecycle to SwiftUI state.
///
/// ## Lifecycle
///
/// 1. Construct the model with relays, app metadata, and (optionally) an iOS callback URL.
/// 2. Call `await model.start()` — typically from `.task { }`. This generates the
///    `nostrconnect://` URI, probes for installed signer apps, and begins listening on relays.
/// 3. Bind UI to `state`, `nostrConnectURI`, and `detectedSigner`.
/// 4. When the user taps the hero button, call `model.handoff(openURL: openURL)`.
/// 5. Observe `state == .connected(signer)` to retrieve the connected ``NDKBunkerSigner``.
///
/// ## iOS callback convention
///
/// `callback` is **not** standardized in NIP-46. It is, however, the de-facto convention adopted
/// by Primal-iOS and Nostrify: the signer reads `callback=<url>` from the `nostrconnect://` URI
/// and calls `UIApplication.shared.open(<url>)` after signing the connect request. That brings
/// the host app back to the foreground; the actual handshake completes over relays.
///
/// Pass `callbackURL: URL(string: "myapp://nip46")` to enable this. The host app must register
/// the scheme in its `Info.plist > CFBundleURLTypes`.
@MainActor
@Observable
public final class NDKBunkerConnectModel {
    /// Connect-flow state. The enum is intentionally narrow: `state == .connected(signer)` is the
    /// terminal success signal; everything else is intermediate or failure.
    public enum State: @unchecked Sendable {
        /// Not started.
        case idle
        /// Generating the `nostrconnect://` URI and starting the relay subscription.
        case generating
        /// URI generated, relay subscription live, awaiting the remote signer's `connect` response.
        case waitingForApproval
        /// The remote signer asked the user to authenticate at a URL (NIP-46 `auth_url`,
        /// used by nsec.app). The host should open this URL and continue listening — the
        /// connect flow resumes on its own once the user authenticates.
        case awaitingAuthChallenge(URL)
        /// The bunker acknowledged the connect request. Use this signer for subsequent operations.
        case connected(NDKBunkerSigner)
        /// Terminal failure. Inspect the associated error for the reason.
        case failed(any Error)
    }

    /// Errors raised by the model itself (the underlying signer may surface its own).
    public enum ConnectError: LocalizedError {
        case timeout
        case pubkeyMismatch(expected: String, actual: String)
        case alreadyStarted
        case missingURI

        public var errorDescription: String? {
            switch self {
            case .timeout:
                return "The signer did not respond in time."
            case let .pubkeyMismatch(expected, actual):
                return "The signer returned a different account (expected \(expected.prefix(8))…, got \(actual.prefix(8))…)."
            case .alreadyStarted:
                return "Connect flow is already in progress."
            case .missingURI:
                return "Failed to generate the nostrconnect:// URI."
            }
        }
    }

    public private(set) var state: State = .idle
    /// The generated `nostrconnect://` URI — non-nil from `.waitingForApproval` onwards.
    /// Render it as a QR code or hand it to ``handoff(openURL:)``.
    public private(set) var nostrConnectURI: String?
    /// The first installed signer found in the configured registry, if any. `nil` when no known
    /// signer is detected (the user can still scan/paste).
    public private(set) var detectedSigner: NDKKnownSigner?

    private let ndk: NDK
    private let relays: [String]
    private let options: NDKBunkerSigner.NostrConnectOptions
    private let knownSigners: [NDKKnownSigner]
    private let expectedPubkey: PublicKey?
    private let approvalTimeout: Duration
    private let logger = Logger(subsystem: "NDKSwiftUI", category: "BunkerConnect")

    private var bunkerSigner: NDKBunkerSigner?
    private var connectTask: Task<Void, Never>?
    private var authUrlCancellable: AnyCancellable?

    /// - Parameters:
    ///   - ndk: The configured NDK instance.
    ///   - relays: Relays the host listens on for the bunker's response. Typically a single
    ///     well-known relay like `wss://relay.nsec.app` or `wss://relay.primal.net`.
    ///   - options: NIP-46 metadata (name/url/image/perms) the bunker shows to the user.
    ///   - callbackURL: Optional `myapp://<path>` URL the signer will open after signing.
    ///     De-facto iOS convention — see the type-level discussion.
    ///   - knownSigners: Registry to probe for installed signer apps. Defaults to ``NDKKnownSigner/allKnown``.
    ///   - expectedPubkey: When non-nil (reconnect flow), the bunker's returned pubkey must
    ///     match this or the model lands in `.failed(.pubkeyMismatch)` without exposing a signer.
    ///   - approvalTimeout: How long to wait for the bunker's response before failing with
    ///     `.timeout`. Defaults to 120 seconds.
    public init(
        ndk: NDK,
        relays: [String],
        options: NDKBunkerSigner.NostrConnectOptions = .init(),
        callbackURL: URL? = nil,
        knownSigners: [NDKKnownSigner] = NDKKnownSigner.allKnown,
        expectedPubkey: PublicKey? = nil,
        approvalTimeout: Duration = .seconds(120)
    ) {
        self.ndk = ndk
        self.relays = relays
        self.knownSigners = knownSigners
        self.expectedPubkey = expectedPubkey
        self.approvalTimeout = approvalTimeout

        if let callbackURL {
            var extras = options.extraQueryItems ?? []
            extras.append(URLQueryItem(name: "callback", value: callbackURL.absoluteString))
            self.options = NDKBunkerSigner.NostrConnectOptions(
                name: options.name,
                url: options.url,
                image: options.image,
                perms: options.perms,
                extraQueryItems: extras
            )
        } else {
            self.options = options
        }
    }

    /// Generates the URI, probes for an installed signer, and begins listening for the bunker.
    /// Idempotent only in the sense that a second call from non-idle state fails with `.alreadyStarted`.
    public func start() async {
        guard case .idle = state else {
            state = .failed(ConnectError.alreadyStarted)
            return
        }
        state = .generating
        detectedSigner = NDKLocalSigner.detect(from: knownSigners)

        do {
            let signer = try await NDKBunkerSigner.nostrConnect(
                ndk: ndk,
                relays: relays,
                options: options
            )
            bunkerSigner = signer

            var uri: String?
            for _ in 0 ..< 20 {
                uri = await signer.nostrConnectUri
                if uri != nil { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let uri else {
                state = .failed(ConnectError.missingURI)
                return
            }
            nostrConnectURI = uri

            let publisher = await signer.authUrlPublisher
            authUrlCancellable = publisher.sink { [weak self] urlString in
                guard let url = URL(string: urlString) else { return }
                Task { @MainActor [weak self] in
                    self?.state = .awaitingAuthChallenge(url)
                }
            }

            state = .waitingForApproval
            connectTask = Task { [weak self] in
                await self?.runConnect(signer: signer)
            }
        } catch {
            state = .failed(error)
        }
    }

    private func runConnect(signer: NDKBunkerSigner) async {
        let timeout = approvalTimeout
        do {
            let connectedPubkey: PublicKey = try await withThrowingTaskGroup(of: PublicKey.self) { group in
                group.addTask { try await signer.connect() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ConnectError.timeout
                }
                let first = try await group.next()
                group.cancelAll()
                return first ?? ""
            }

            if let expected = expectedPubkey, connectedPubkey != expected {
                state = .failed(ConnectError.pubkeyMismatch(expected: expected, actual: connectedPubkey))
                return
            }
            state = .connected(signer)
        } catch {
            // If the timeout fires first the group may emit either the timeout or a cancellation
            // error; both should land as `.failed` if we're not already in a terminal state.
            if case .connected = state { return }
            state = .failed(error)
        }
    }

    /// Opens the generated `nostrconnect://` URI via the SwiftUI `OpenURLAction`.
    ///
    /// iOS routes the URI to whichever app registered the `nostrconnect` scheme (typically the
    /// installed signer). No-op if `start()` hasn't completed yet.
    ///
    /// Pass `using` from a SwiftUI view:
    /// ```swift
    /// @Environment(\.openURL) private var openURL
    /// // ...
    /// Button("Open signer") { model.handoff(using: openURL) }
    /// ```
    public func handoff(using openURL: OpenURLAction) {
        guard let uri = nostrConnectURI, let url = URL(string: uri) else { return }
        openURL(url)
    }

    /// Cancels the in-flight connect and resets the model to `.idle`. Safe to call multiple times.
    public func cancel() {
        connectTask?.cancel()
        connectTask = nil
        authUrlCancellable?.cancel()
        authUrlCancellable = nil
        let signer = bunkerSigner
        bunkerSigner = nil
        nostrConnectURI = nil
        state = .idle
        if let signer {
            Task { await signer.disconnect() }
        }
    }
}
