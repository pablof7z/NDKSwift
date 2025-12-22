import Foundation

/// Observable profile that streams kind 0 metadata updates
@Observable
@MainActor
public final class NDKProfile {
    /// Current profile metadata
    public private(set) var metadata: NDKUserMetadata?

    /// Best available display name
    public var displayName: String {
        metadata?.bestDisplayName ?? String(pubkey.prefix(12)) + "..."
    }

    /// Profile picture URL
    public var pictureURL: URL? {
        metadata?.picture.flatMap(URL.init(string:))
    }

    /// Banner image URL
    public var bannerURL: URL? {
        metadata?.banner.flatMap(URL.init(string:))
    }

    /// User's name
    public var name: String {
        metadata?.name ?? ""
    }

    /// Bio/about text
    public var about: String {
        metadata?.about ?? ""
    }

    /// NIP-05 identifier
    public var nip05: String? {
        metadata?.nip05
    }

    /// Lightning address
    public var lud16: String? {
        metadata?.lud16
    }

    /// The pubkey this profile belongs to
    public let pubkey: PublicKey

    private weak var ndk: NDK?

    /// Cancellation handle for the subscription task
    /// Using a class wrapper to allow nonisolated access in deinit
    private let cancellation = CancellationHandle()

    init(pubkey: PublicKey, ndk: NDK) {
        self.pubkey = pubkey
        self.ndk = ndk
        startObservation()
    }

    deinit {
        cancellation.cancel()
    }

    private func startObservation() {
        guard let ndk else { return }
        let cancellation = self.cancellation
        let pubkey = self.pubkey

        Task { [weak self] in
            // Delegate to ProfileManager for caching and subscription management
            for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 0) {
                guard !cancellation.isCancelled else { break }
                guard let self else { break }

                await MainActor.run {
                    self.metadata = metadata
                }
            }
        }
    }
}

/// Thread-safe cancellation handle that can be accessed from deinit
private final class CancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = true
    }
}
