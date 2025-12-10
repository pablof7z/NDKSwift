import Foundation
import SwiftUI
import NDKSwift

@MainActor
@Observable
final class FeedViewModel {
    public private(set) var posts: [NDKEvent] = []
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public var feedMode: FeedMode = .following

    @ObservationIgnored
    private let ndk: NDK
    @ObservationIgnored
    private let settings = SettingsManager.shared
    @ObservationIgnored
    private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored
    private var allPosts: [NDKEvent] = []
    @ObservationIgnored
    private weak var currentMuteListManager: MuteListManager?

    /// Dynamic kinds based on video settings
    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if settings.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public func startSubscription(muteListManager: MuteListManager) {
        currentMuteListManager = muteListManager
        isLoading = true
        error = nil
        posts = []
        allPosts = []

        subscriptionTask?.cancel()
        subscriptionTask = Task {
            let filter = NDKFilter(kinds: feedKinds, limit: 50)

            let subscription: NDKSubscription<NDKEvent>
            switch feedMode {
            case .following:
                subscription = ndk.subscribe(
                    filter: filter,
                    cachePolicy: .cacheWithNetwork
                )

            case .relay(let url):
                subscription = ndk.subscribe(
                    filter: filter,
                    cachePolicy: .networkOnly,
                    relays: [url],
                    exclusiveRelays: true
                )
            }

            for await event in subscription.events {
                guard !Task.isCancelled else { break }

                allPosts.append(event)
                updateFilteredPosts()
                isLoading = false
            }
        }
    }

    private func updateFilteredPosts() {
        let mutedPubkeys = currentMuteListManager?.mutedPubkeys ?? []
        posts = allPosts
            .filter { !mutedPubkeys.contains($0.pubkey) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
