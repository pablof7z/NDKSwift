import Foundation
import NDKSwift
import SwiftUI
import Observation

// MARK: - Follow List Data Source

/// Data source for user's follow list (kind:3 events)
@Observable
@MainActor
public class NDKUIFollowListDataSource {
    public private(set) var followList: Set<String> = []
    public private(set) var isLoading = false
    public private(set) var error: Error?
    public private(set) var lastUpdate: Date?

    private let dataSource: NDKSubscription<NDKEvent>
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(ndk: NDK, pubkey: String) {
        self.dataSource = ndk.subscribe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.contacts]
            ),
            maxAge: 0,
            cachePolicy: .cacheWithNetwork
        )

        observeFollowList()
    }

    deinit {
        observationTask?.cancel()
    }

    private func observeFollowList() {
        observationTask = Task { @MainActor in
            var latestEvent: NDKEvent?

            for await event in dataSource.events {
                // Keep only the most recent event
                if latestEvent == nil || event.createdAt > latestEvent!.createdAt {
                    latestEvent = event

                    // Extract follow list from event
                    let pubkeys = event.tags
                        .filter { tag in
                            tag.count >= 2 && tag[0] == "p"
                        }
                        .map { tag in
                            tag[1]
                        }
                    followList = Set(pubkeys)
                    lastUpdate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
                }
            }
        }

        // Observe loading and error states
        Task { @MainActor in
            while !Task.isCancelled {
                isLoading = dataSource.isLoading
                error = dataSource.error
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
    }

    public func isFollowing(_ pubkey: String) -> Bool {
        followList.contains(pubkey)
    }
}