import Foundation
import SwiftUI
import NDKSwift
import Combine

@MainActor
public final class FeedViewModel: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public var feedMode: FeedMode = .following

    private let ndk: NDK
    private let settings = SettingsManager.shared
    private var subscription: NDKSubscription<NDKEvent>?
    private var cancellables = Set<AnyCancellable>()
    private var allPosts: [NDKEvent] = []
    private var currentMuteListManager: MuteListManager?

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

        let filter = NDKFilter(kinds: feedKinds, limit: 50)

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

        subscription?.$data
            .combineLatest(muteListManager.$mutedPubkeys)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events, mutedPubkeys in
                self?.allPosts = events
                self?.posts = events
                    .filter { !mutedPubkeys.contains($0.pubkey) }
                    .sorted { $0.createdAt > $1.createdAt }
                self?.isLoading = false
            }
            .store(in: &cancellables)

        subscription?.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }

    public func stopSubscription() {
        cancellables.removeAll()
        subscription = nil
    }

    public func switchMode(to mode: FeedMode, muteListManager: MuteListManager) {
        guard mode != feedMode else { return }
        stopSubscription()
        feedMode = mode
        startSubscription(muteListManager: muteListManager)
    }
}
