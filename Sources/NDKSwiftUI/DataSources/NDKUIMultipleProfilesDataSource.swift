import Foundation
import NDKSwiftCore
import SwiftUI
import Observation

// MARK: - Multiple Profiles Data Source

/// Data source for multiple user profiles (e.g., for contact lists)
@Observable
@MainActor
public class NDKUIMultipleProfilesDataSource {
    public private(set) var profiles: [String: NDKUserMetadata] = [:]
    public private(set) var isLoading = false
    public private(set) var error: Error?

    private let dataSource: NDKSubscription<NDKEvent>
    private let pubkeys: Set<String>
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(ndk: NDK, pubkeys: Set<String>) {
        self.pubkeys = pubkeys
        self.dataSource = ndk.subscribe(
            filter: NDKFilter(
                authors: Array(pubkeys),
                kinds: [EventKind.metadata]
            ),
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )

        observeProfiles()
    }

    deinit {
        observationTask?.cancel()
    }

    private func observeProfiles() {
        observationTask = Task { @MainActor in
            var latestEvents: [String: NDKEvent] = [:]

            for await event in dataSource.events {
                // Keep only the latest event per author
                if let existing = latestEvents[event.pubkey] {
                    if event.createdAt > existing.createdAt {
                        latestEvents[event.pubkey] = event
                    }
                } else {
                    latestEvents[event.pubkey] = event
                }

                // Rebuild profiles dictionary
                profiles = latestEvents.mapValues { NDKUserMetadata(event: $0) }
                    .compactMapValues { $0 }
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

    public func profile(for pubkey: String) -> NDKUserMetadata? {
        profiles[pubkey]
    }
}