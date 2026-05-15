import Foundation
import NDKSwiftCore
import Observation
import SwiftUI

// MARK: - Follow List Data Source

/// Data source for user's follow list (kind:3 events)
@Observable
@MainActor
public class NDKUIFollowListDataSource {
    public private(set) var followList: Set<String> = []
    public private(set) var lastUpdate: Date?

    private let dataSource: NDKSubscription<NDKEvent>
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(ndk: NDK, pubkey: String) {
        dataSource = ndk.subscribe(
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
        // Hold the stream locally so the Task does not capture self.dataSource,
        // and weak-capture self so deinit can run and cancel observationTask.
        let stream = dataSource.events
        observationTask = Task { @MainActor [weak self] in
            var latestEvent: NDKEvent?

            for await batch in stream {
                guard let self else { return }
                for event in batch {
                    // Keep only the most recent event
                    if latestEvent == nil || event.createdAt > (latestEvent?.createdAt ?? 0) {
                        latestEvent = event

                        let pubkeys = event.tags
                            .filter { tag in tag.count >= 2 && tag[0] == "p" }
                            .map { tag in tag[1] }
                        self.followList = Set(pubkeys)
                        self.lastUpdate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
                    }
                }
            }
        }
    }

    public func isFollowing(_ pubkey: String) -> Bool {
        followList.contains(pubkey)
    }
}
