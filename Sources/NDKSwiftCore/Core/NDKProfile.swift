import Foundation

/// Observable profile that streams kind 0 metadata updates
@Observable
@MainActor
public final class NDKProfile {
    /// Current profile metadata
    public private(set) var metadata: NDKUserMetadata?

    /// Best available display name
    public var displayName: String {
        if let metadata = metadata {
            return metadata.bestDisplayName
        }
        // Fallback to npub when metadata not yet loaded
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(16)) + "..."
        }
        return String(pubkey.prefix(12)) + "..."
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
            // Start relay subscription to fetch fresh profile data
            // Events are automatically saved to cache by NDKSubscriptionRequirement
            let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.metadata])
            let subscription = ndk.subscribe(filter: filter)

            // Observe cache for profile changes (reactive updates)
            let cacheStream = await ndk.cache.observeProfile(pubkey: pubkey, includeExisting: true)

            // Consume subscription events in background (they go to cache automatically)
            Task {
                for await batch in subscription.events {
                    guard !cancellation.isCancelled else { break }
                    // Events are consumed to keep the subscription active
                    // They are automatically saved to cache by NDKSubscriptionRequirement
                    _ = batch
                }
            }

            // React to cache changes
            do {
                for try await metadata in cacheStream {
                    guard !cancellation.isCancelled else { break }
                    guard let self else { break }

                    if let metadata = metadata {
                        await MainActor.run {
                            self.metadata = metadata
                        }
                    }
                }
            } catch {
                // Stream ended or error occurred
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
