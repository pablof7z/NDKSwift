// MintDiscoveryViewModel.swift
import SwiftUI
import NDKSwift

/// Discovered mint information from NIP-87
public struct DiscoveredMint: Identifiable, Hashable {
    public let id: String // mint pubkey or URL
    public let url: URL
    public let name: String?
    public let description: String?
    public let iconURL: URL?
    public let units: [String]
    public let network: String
    public var recommendationCount: Int

    public var displayName: String {
        name ?? url.host ?? url.absoluteString
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredMint, rhs: DiscoveredMint) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public class MintDiscoveryViewModel: ObservableObject {
    private let ndk: NDK

    @Published public private(set) var discoveredMints: [DiscoveredMint] = []
    @Published public private(set) var error: Error?
    @Published public private(set) var isDiscovering = false
    @Published public var selectedMints: Set<String> = []

    private var discoveryTask: Task<Void, Never>?
    private var seenMintIds: Set<String> = []

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    deinit {
        discoveryTask?.cancel()
    }

    /// Discover Cashu mints via NIP-87 - streams mints as they arrive
    public func discoverMints() async {
        discoveryTask?.cancel()
        error = nil
        discoveredMints = []
        seenMintIds = []
        isDiscovering = true

        discoveryTask = Task { [weak self] in
            guard let self = self else { return }

            // Stream mint announcements and recommendations in parallel
            async let announcementTask: () = streamMintAnnouncements()
            async let recommendationTask: () = streamRecommendations()
            _ = await (announcementTask, recommendationTask)

            await MainActor.run {
                self.isDiscovering = false
            }
        }
    }

    private func streamMintAnnouncements() async {
        // Query for Cashu mint announcements (kind 38172)
        let announcementFilter = NDKFilter(
            kinds: [EventKind.cashuMintAnnouncement],
            limit: 100
        )

        let announcementSub = ndk.subscribe(
            filter: announcementFilter,
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )

        // Stream mints as they arrive
        for await event in announcementSub.events {
            if Task.isCancelled { break }

            if let announcement = try? event.parseMintAnnouncement() {
                let mintId = announcement.mintURL.absoluteString

                // Only include mainnet mints we haven't seen
                let network = extractNetwork(from: announcement)
                guard network == "mainnet" && !seenMintIds.contains(mintId) else { continue }

                seenMintIds.insert(mintId)

                let mint = DiscoveredMint(
                    id: mintId,
                    url: announcement.mintURL,
                    name: announcement.name,
                    description: announcement.description,
                    iconURL: announcement.icon,
                    units: announcement.units ?? ["sat"],
                    network: network,
                    recommendationCount: 0
                )

                // Insert sorted by recommendation count (higher first)
                let insertIndex = discoveredMints.firstIndex { mint.recommendationCount > $0.recommendationCount } ?? discoveredMints.endIndex
                discoveredMints.insert(mint, at: insertIndex)
            }
        }
    }

    private func streamRecommendations() async {
        // Query for recommendations (kind 38000 with k=38172)
        var recommendationFilter = NDKFilter(
            kinds: [EventKind.mintAnnouncement],
            limit: 200
        )
        recommendationFilter.addTagFilter("k", values: ["38172"])

        let recommendationSub = ndk.subscribe(
            filter: recommendationFilter,
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )

        // Stream recommendations and update counts as they arrive
        for await event in recommendationSub.events {
            if Task.isCancelled { break }

            // Extract mint URL from u tag and increment count
            for tag in event.tags where tag.first == "u" && tag.count > 1 {
                let mintURL = tag[1]

                // Find and update the mint's recommendation count
                if let index = discoveredMints.firstIndex(where: { $0.id == mintURL }) {
                    discoveredMints[index].recommendationCount += 1

                    // Re-sort to maintain recommendation order
                    let mint = discoveredMints.remove(at: index)
                    let newIndex = discoveredMints.firstIndex { mint.recommendationCount > $0.recommendationCount } ?? discoveredMints.endIndex
                    discoveredMints.insert(mint, at: newIndex)
                }
            }
        }
    }

    /// Select/deselect a mint
    public func toggleMint(_ mintURL: String) {
        if selectedMints.contains(mintURL) {
            selectedMints.remove(mintURL)
        } else {
            selectedMints.insert(mintURL)
        }
    }

    /// Get selected mint URLs as array
    public var selectedMintURLs: [String] {
        Array(selectedMints)
    }

    private func extractNetwork(from announcement: NDKMintAnnouncement) -> String {
        // Check nuts for network info, default to mainnet
        // The network is typically in the event tags, but for simplicity assume mainnet
        return "mainnet"
    }
}
