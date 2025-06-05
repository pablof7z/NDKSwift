import Foundation

/// Intelligently selects relays for publishing and fetching based on the outbox model
public actor NDKRelaySelector {
    private let ndk: NDK
    private let tracker: NDKOutboxTracker
    private let ranker: NDKRelayRanker

    public init(ndk: NDK, tracker: NDKOutboxTracker, ranker: NDKRelayRanker) {
        self.ndk = ndk
        self.tracker = tracker
        self.ranker = ranker
    }

    /// Select relays for publishing an event
    public func selectRelaysForPublishing(
        event: NDKEvent,
        config: PublishingConfig = .default
    ) async -> RelaySelectionResult {
        var targetRelays = Set<String>()
        var missingRelayPubkeys = Set<String>()

        // 1. Add user's primary write relays
        if let userItem = await tracker.getRelaysSyncFor(pubkey: event.pubkey, type: .write) {
            targetRelays.formUnion(userItem.writeRelays.map { $0.url })
        } else if config.includeUserReadRelays,
                  let userItem = await tracker.getRelaysSyncFor(pubkey: event.pubkey, type: .read)
        {
            // Fallback to read relays if no write relays
            targetRelays.formUnion(userItem.readRelays.map { $0.url })
        }

        // 2. Add contextual relays from event tags
        let contextualRelays = await extractContextualRelays(from: event, for: .publishing)
        targetRelays.formUnion(contextualRelays.relays)
        missingRelayPubkeys.formUnion(contextualRelays.missingPubkeys)

        // 3. Special handling for NIP-65 relay lists
        if event.kind == NDKRelayList.kind {
            // For relay lists, also publish to read relays
            if let userItem = await tracker.getRelaysSyncFor(pubkey: event.pubkey, type: .read) {
                targetRelays.formUnion(userItem.readRelays.map { $0.url })
            }
        }

        // 4. Apply fallback if needed
        if targetRelays.count < config.minRelayCount {
            let fallbackRelays = await selectFallbackRelays(
                currentCount: targetRelays.count,
                targetCount: config.minRelayCount,
                excludeRelays: targetRelays
            )
            targetRelays.formUnion(fallbackRelays)
        }

        // 5. Rank and limit relays
        let rankedRelays = await ranker.rankRelays(
            Array(targetRelays),
            for: [event.pubkey] + event.pTags,
            preferences: config.rankingPreferences
        )

        let selectedRelays = Array(rankedRelays.prefix(config.maxRelayCount))
            .map { $0.url }

        return RelaySelectionResult(
            relays: Set(selectedRelays),
            missingRelayInfoPubkeys: missingRelayPubkeys,
            selectionMethod: determineSelectionMethod(targetRelays)
        )
    }

    /// Select relays for fetching events
    public func selectRelaysForFetching(
        filter: NDKFilter,
        config: FetchingConfig = .default
    ) async -> RelaySelectionResult {
        var sourceRelays = Set<String>()
        var missingRelayPubkeys = Set<String>()

        // 1. Add user's primary read relays
        let userPubkey = try? await ndk.signer?.pubkey
        if let userPubkey = userPubkey,
           let userItem = await tracker.getRelaysSyncFor(pubkey: userPubkey, type: .read)
        {
            sourceRelays.formUnion(userItem.readRelays.map { $0.url })
        }

        // 2. Add author-specific relays
        if let authors = filter.authors, !authors.isEmpty {
            let authorRelays = await selectRelaysForAuthors(
                authors,
                type: .read,
                preferWriteRelaysIfNoRead: config.preferWriteRelaysIfNoRead
            )
            sourceRelays.formUnion(authorRelays.relays)
            missingRelayPubkeys.formUnion(authorRelays.missingPubkeys)
        }

        // 3. Add contextual relays from filter tags
        let contextualRelays = await extractContextualRelaysFromFilter(filter)
        sourceRelays.formUnion(contextualRelays.relays)
        missingRelayPubkeys.formUnion(contextualRelays.missingPubkeys)

        // 4. Apply fallback if needed
        if sourceRelays.count < config.minRelayCount {
            let fallbackRelays = await selectFallbackRelays(
                currentCount: sourceRelays.count,
                targetCount: config.minRelayCount,
                excludeRelays: sourceRelays
            )
            sourceRelays.formUnion(fallbackRelays)
        }

        // 5. Rank and limit relays
        let authors = filter.authors ?? []
        let taggedPubkeys = extractPubkeysFromFilter(filter)
        let allRelevantPubkeys = authors + taggedPubkeys + (userPubkey.map { [$0] } ?? [])

        let rankedRelays = await ranker.rankRelays(
            Array(sourceRelays),
            for: allRelevantPubkeys,
            preferences: config.rankingPreferences
        )

        let selectedRelays = Array(rankedRelays.prefix(config.maxRelayCount))
            .map { $0.url }

        return RelaySelectionResult(
            relays: Set(selectedRelays),
            missingRelayInfoPubkeys: missingRelayPubkeys,
            selectionMethod: determineSelectionMethod(sourceRelays)
        )
    }

    /// Choose relay combination for multiple pubkeys (optimized for minimal connections)
    public func chooseRelayCombinationForPubkeys(
        _ pubkeys: [String],
        type: RelayListType,
        config: CombinationConfig = .default
    ) async -> RelayToPubkeysMap {
        var relayToPubkeys = RelayToPubkeysMap()
        let connectedRelays = ndk.relayPool.connectedRelays()

        // Track how many relays each pubkey has been assigned to
        var pubkeyRelayCount: [String: Int] = [:]

        // Get relay info for all pubkeys
        let pubkeyRelayInfo = await getAllRelaysForPubkeys(pubkeys, type: type)

        // First pass: Use connected relays
        for relay in connectedRelays {
            let pubkeysInRelay = pubkeyRelayInfo.pubkeysToRelays
                .filter { $0.value.contains(relay.url) }
                .map { $0.key }

            if !pubkeysInRelay.isEmpty {
                relayToPubkeys[relay.url] = pubkeysInRelay
                for pubkey in pubkeysInRelay {
                    pubkeyRelayCount[pubkey, default: 0] += 1
                }
            }
        }

        // Second pass: Add relays for pubkeys that need more coverage
        let sortedRelays = await ranker.getTopRelaysForAuthors(pubkeys)

        for pubkey in pubkeys {
            let currentCount = pubkeyRelayCount[pubkey, default: 0]
            if currentCount >= config.relaysPerAuthor { continue }

            guard let relays = pubkeyRelayInfo.pubkeysToRelays[pubkey] else { continue }

            // Add relays until we reach the target
            for relayURL in sortedRelays {
                if currentCount >= config.relaysPerAuthor { break }
                if !relays.contains(relayURL) { continue }

                var pubkeysInRelay = relayToPubkeys[relayURL, default: []]
                if !pubkeysInRelay.contains(pubkey) {
                    pubkeysInRelay.append(pubkey)
                    relayToPubkeys[relayURL] = pubkeysInRelay
                    pubkeyRelayCount[pubkey, default: 0] += 1
                }
            }
        }

        // Third pass: Add fallback relays for pubkeys with no relays
        let fallbackRelays = await selectFallbackRelays(currentCount: 0, targetCount: 2)
        for pubkey in pubkeyRelayInfo.authorsMissingRelays {
            for relayURL in fallbackRelays.prefix(config.relaysPerAuthor) {
                var pubkeysInRelay = relayToPubkeys[relayURL, default: []]
                if !pubkeysInRelay.contains(pubkey) {
                    pubkeysInRelay.append(pubkey)
                    relayToPubkeys[relayURL] = pubkeysInRelay
                }
            }
        }

        return relayToPubkeys
    }

    // MARK: - Private Methods

    private func extractContextualRelays(
        from event: NDKEvent,
        for purpose: RelayPurpose
    ) async -> (relays: Set<String>, missingPubkeys: Set<String>) {
        var relays = Set<String>()
        var missingPubkeys = Set<String>()

        // Extract from e tags (reply/quote context)
        for eTag in event.eTags {
            if let recommendedRelay = eTag.recommendedRelay {
                relays.insert(recommendedRelay)
            }
        }

        // Extract from p tags (mentioned users)
        for pubkey in event.pTags {
            if let item = await tracker.getRelaysSyncFor(pubkey: pubkey) {
                switch purpose {
                case .publishing:
                    // Publish to where mentioned users write and read
                    relays.formUnion(item.writeRelays.map { $0.url })
                    if item.writeRelays.isEmpty {
                        relays.formUnion(item.readRelays.map { $0.url })
                    }
                case .fetching:
                    // Fetch from where mentioned users read
                    relays.formUnion(item.readRelays.map { $0.url })
                    if item.readRelays.isEmpty {
                        relays.formUnion(item.writeRelays.map { $0.url })
                    }
                }
            } else {
                missingPubkeys.insert(pubkey)
            }
        }

        return (relays, missingPubkeys)
    }

    private func extractContextualRelaysFromFilter(
        _ filter: NDKFilter
    ) async -> (relays: Set<String>, missingPubkeys: Set<String>) {
        var relays = Set<String>()
        var missingPubkeys = Set<String>()

        // Extract from #p tags
        if let pTags = filter.tags?["p"] {
            for pubkey in pTags {
                if let item = await tracker.getRelaysSyncFor(pubkey: pubkey) {
                    relays.formUnion(item.readRelays.map { $0.url })
                    if item.readRelays.isEmpty {
                        relays.formUnion(item.writeRelays.map { $0.url })
                    }
                } else {
                    missingPubkeys.insert(pubkey)
                }
            }
        }

        return (relays, missingPubkeys)
    }

    private func selectRelaysForAuthors(
        _ authors: [String],
        type: RelayListType,
        preferWriteRelaysIfNoRead: Bool
    ) async -> (relays: Set<String>, missingPubkeys: Set<String>) {
        var relays = Set<String>()
        var missingPubkeys = Set<String>()

        for author in authors {
            if let item = await tracker.getRelaysSyncFor(pubkey: author, type: type) {
                switch type {
                case .read:
                    relays.formUnion(item.readRelays.map { $0.url })
                    if item.readRelays.isEmpty, preferWriteRelaysIfNoRead {
                        relays.formUnion(item.writeRelays.map { $0.url })
                    }
                case .write:
                    relays.formUnion(item.writeRelays.map { $0.url })
                case .both:
                    relays.formUnion(item.allRelayURLs)
                }
            } else {
                missingPubkeys.insert(author)
            }
        }

        return (relays, missingPubkeys)
    }

    private func selectFallbackRelays(
        currentCount: Int,
        targetCount: Int,
        excludeRelays: Set<String> = []
    ) async -> Set<String> {
        let neededCount = targetCount - currentCount
        guard neededCount > 0 else { return [] }

        // Get default relays from pool
        let poolRelays = ndk.relayPool.relays
            .filter { !excludeRelays.contains($0.url) }
            .prefix(neededCount)
            .map { $0.url }

        return Set(poolRelays)
    }

    private func getAllRelaysForPubkeys(
        _ pubkeys: [String],
        type: RelayListType
    ) async -> (pubkeysToRelays: [String: Set<String>], authorsMissingRelays: Set<String>) {
        var pubkeysToRelays: [String: Set<String>] = [:]
        var authorsMissingRelays = Set<String>()

        for pubkey in pubkeys {
            if let item = await tracker.getRelaysSyncFor(pubkey: pubkey, type: type) {
                let relays: Set<String>
                switch type {
                case .read:
                    relays = Set(item.readRelays.map { $0.url })
                case .write:
                    relays = Set(item.writeRelays.map { $0.url })
                case .both:
                    relays = item.allRelayURLs
                }

                if !relays.isEmpty {
                    pubkeysToRelays[pubkey] = relays
                } else {
                    authorsMissingRelays.insert(pubkey)
                }
            } else {
                authorsMissingRelays.insert(pubkey)
            }
        }

        return (pubkeysToRelays, authorsMissingRelays)
    }

    private func extractPubkeysFromFilter(_ filter: NDKFilter) -> [String] {
        var pubkeys: [String] = []

        if let pTags = filter.tags?["p"] {
            pubkeys.append(contentsOf: pTags)
        }

        return pubkeys
    }

    private func determineSelectionMethod(_ relays: Set<String>) -> SelectionMethod {
        // Simple heuristic - could be expanded
        if relays.isEmpty {
            return .fallback
        } else if relays.count <= 3 {
            return .contextual
        } else {
            return .outbox
        }
    }
}

// MARK: - Configuration Types

/// Configuration for publishing events
public struct PublishingConfig {
    public let minRelayCount: Int
    public let maxRelayCount: Int
    public let includeUserReadRelays: Bool
    public let rankingPreferences: RelayPreferences

    public init(
        minRelayCount: Int = 2,
        maxRelayCount: Int = 10,
        includeUserReadRelays: Bool = true,
        rankingPreferences: RelayPreferences = .default
    ) {
        self.minRelayCount = minRelayCount
        self.maxRelayCount = maxRelayCount
        self.includeUserReadRelays = includeUserReadRelays
        self.rankingPreferences = rankingPreferences
    }

    public static let `default` = PublishingConfig()
}

/// Configuration for fetching events
public struct FetchingConfig {
    public let minRelayCount: Int
    public let maxRelayCount: Int
    public let preferWriteRelaysIfNoRead: Bool
    public let rankingPreferences: RelayPreferences

    public init(
        minRelayCount: Int = 2,
        maxRelayCount: Int = 15,
        preferWriteRelaysIfNoRead: Bool = true,
        rankingPreferences: RelayPreferences = .default
    ) {
        self.minRelayCount = minRelayCount
        self.maxRelayCount = maxRelayCount
        self.preferWriteRelaysIfNoRead = preferWriteRelaysIfNoRead
        self.rankingPreferences = rankingPreferences
    }

    public static let `default` = FetchingConfig()
}

/// Configuration for relay combination selection
public struct CombinationConfig {
    public let relaysPerAuthor: Int

    public init(relaysPerAuthor: Int = 2) {
        self.relaysPerAuthor = relaysPerAuthor
    }

    public static let `default` = CombinationConfig()
}

// MARK: - Result Types

/// Result of relay selection
public struct RelaySelectionResult {
    public let relays: Set<String>
    public let missingRelayInfoPubkeys: Set<String>
    public let selectionMethod: SelectionMethod
}

/// Map of relay URLs to pubkeys
public typealias RelayToPubkeysMap = [String: [String]]

/// Purpose of relay selection
private enum RelayPurpose {
    case publishing
    case fetching
}

/// Method used for relay selection
public enum SelectionMethod {
    case outbox
    case contextual
    case fallback
}
