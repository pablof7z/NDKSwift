import Foundation
import SwiftUI
import NDKSwift
import Combine

@MainActor
public final class FeedViewModel: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    public let filter: NDKFilter

    private let ndk: NDK
    private var subscription: NDKSubscription<NDKEvent>?
    private var cancellables = Set<AnyCancellable>()

    public init(ndk: NDK) {
        self.ndk = ndk
        self.filter = NDKFilter(kinds: [OlasConstants.EventKinds.image], limit: 50)
    }

    public func startSubscription() {
        isLoading = true

        subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )

        subscription?.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.posts = events.sorted { $0.createdAt > $1.createdAt }
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
}
