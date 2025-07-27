// MARK: - NDKBlockedMintsEvent

/// NIP-60 Blocked Mints Event (kind: 10020)
/// Public event that contains blacklisted mint URLs that the user wants to avoid
public struct NDKBlockedMintsEvent: NDKPublishableEvent {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create and publish a blocked mints event
    @discardableResult
    public static func createAndPublish(
        ndk: NDK,
        blockedMints: [String],
        signer: NDKSigner
    ) async throws -> NDKBlockedMintsEvent {
        return try await EventPublishingHelper.createAndPublish(
            type: NDKBlockedMintsEvent.self,
            ndk: ndk,
            logPrefix: "NDKBlockedMintsEvent"
        ) {
            try await create(
                ndk: ndk,
                blockedMints: blockedMints,
                signer: signer
            )
        }
    }

    /// Create without publishing
    public static func create(
        ndk: NDK,
        blockedMints: [String],
        signer: NDKSigner
    ) async throws -> NDKBlockedMintsEvent {
        let builder = NDKEventBuilder(ndk: ndk)
            .kind(EventKind.blockedMints)  // NIP-60 blocked mints kind

        // Add blocked mint tags
        for mintURL in blockedMints {
            _ = builder.tag([NostrConstants.TagName.url, mintURL])
        }

        let blockedMintsEvent = try await builder.build(signer: signer)

        return NDKBlockedMintsEvent(event: blockedMintsEvent)
    }

    /// The blocked mint URLs in this event
    public var blockedMints: [String] {
        event.tags.tagValues(named: NostrConstants.TagName.url)
    }

    /// Check if a specific mint URL is blocked
    public func isBlocked(_ mintURL: String) -> Bool {
        blockedMints.contains(mintURL)
    }
}

// MARK: - Convenience Extension for NDKEvent

extension NDKEvent {
    /// Convert to NDKBlockedMintsEvent if this is a kind 10020 event
    public var asBlockedMintsEvent: NDKBlockedMintsEvent? {
        guard kind == EventKind.blockedMints else { return nil }
        return NDKBlockedMintsEvent(event: self)
    }
}