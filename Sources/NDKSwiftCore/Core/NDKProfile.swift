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

    /// Bio/about text
    public var about: String? {
        metadata?.about
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
    // Task for profile subscription - nonisolated(unsafe) is required for accessing in deinit
    nonisolated(unsafe) private var subscriptionTask: Task<Void, Never>?

    init(pubkey: PublicKey, ndk: NDK) {
        self.pubkey = pubkey
        self.ndk = ndk
        startObservation()
    }

    deinit {
        subscriptionTask?.cancel()
    }

    private func startObservation() {
        guard let ndk else { return }

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            let filter = NDKFilter(
                authors: [self.pubkey],
                kinds: [EventKind.metadata]
            )

            let subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

            for await event in subscription.events {
                guard !Task.isCancelled else { break }
                let newMetadata = NDKUserMetadata(event: event, ndk: ndk)

                // Only update if newer
                if self.metadata == nil || newMetadata.updatedAt > self.metadata!.updatedAt {
                    self.metadata = newMetadata
                }
            }
        }
    }
}
