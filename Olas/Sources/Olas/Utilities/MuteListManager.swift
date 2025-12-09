// MuteListManager.swift
import SwiftUI
import NDKSwift
import Combine

@MainActor
public final class MuteListManager: ObservableObject {
    @Published public private(set) var mutedPubkeys: Set<String> = []

    private let ndk: NDK
    private var subscriptionTask: Task<Void, Never>?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public func startSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = Task {
            guard let currentUser = await ndk.currentUser else { return }

            let filter = NDKFilter(
                authors: [currentUser.pubkey],
                kinds: [OlasConstants.EventKinds.muteList],
                limit: 1
            )

            let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

            for await event in subscription.events {
                guard !Task.isCancelled else { break }
                parseMuteList(from: event)
            }
        }
    }

    public func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func parseMuteList(from event: NDKEvent) {
        var pubkeys = Set<String>()
        for tag in event.tags {
            if tag.first == "p", tag.count > 1 {
                pubkeys.insert(tag[1])
            }
        }
        mutedPubkeys = pubkeys
    }

    public func mute(_ pubkey: String) async throws {
        mutedPubkeys.insert(pubkey)
        try await publishMuteList()
    }

    public func unmute(_ pubkey: String) async throws {
        mutedPubkeys.remove(pubkey)
        try await publishMuteList()
    }

    public func isMuted(_ pubkey: String) -> Bool {
        mutedPubkeys.contains(pubkey)
    }

    private func publishMuteList() async throws {
        _ = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.muteList)
                .content("")

            for pubkey in self.mutedPubkeys {
                b = b.tag(["p", pubkey])
            }

            return b
        }
    }
}
