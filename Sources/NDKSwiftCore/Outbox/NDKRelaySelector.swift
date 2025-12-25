import Foundation

/// Intelligently selects relays for publishing and fetching based on the outbox model
///
/// Implements NIP-65 outbox model:
/// - When publishing events with <10 p-tags: sends to read relays of each tagged user
/// - When publishing events with ≥10 p-tags: uses only author's relays to avoid relay spam
/// - When fetching: considers p-tagged users regardless of count
actor NDKRelaySelector {
    private let ndk: NDK
    let tracker: any RelayPreferenceProvider
    private let ranker: NDKRelayRanker

    /// Cache for blocked relays to avoid repeated fetches
    private var blockedRelaysCache: Set<String>?
    private var blockedRelaysCacheExpiry: Date?

    public init(ndk: NDK, tracker: any RelayPreferenceProvider, ranker: NDKRelayRanker) {
        self.ndk = ndk
        self.tracker = tracker
        self.ranker = ranker
    }

    /// Select relays for publishing an event
    public func selectRelaysForPublishing(
        event: NDKEvent
    ) async -> RelaySelectionResult {
        let correlationId = event.id.prefix(8)

        // Start telemetry span
        let span = ndk.startSpan("relay.selection.publish", category: .relaySelection)
        span.set(SpanAttributes.eventId, event.id)
        span.set(SpanAttributes.eventKind, event.kind)
        span.set(SpanAttributes.eventPubkey, event.pubkey)
        defer { span.end() }

        // Collect author and p-tagged users separately per NIP-65
        let authorPubkey = event.pubkey
        let pTags = event.pTags
        span.set(SpanAttributes.eventPTagCount, pTags.count)

        // Track p-tag threshold decision
        let useOutboxForPTags = pTags.count < ProtocolConstants.maxPTagsForOutboxModel
        span.set("outbox.ptag_threshold_exceeded", !useOutboxForPTags)
        if !useOutboxForPTags {
            span.addEvent("ptag_threshold_exceeded", attributes: [
                "ptag_count": .int(pTags.count),
                "threshold": .int(ProtocolConstants.maxPTagsForOutboxModel),
                SpanAttributes.decisionReason: .string("Too many p-tags, using author relays only")
            ])
        }

        // Start with author's write relays
        var relayToPubkeys = await chooseRelayCombinationForPublishingAuthors(
            [authorPubkey],
            preferredRelays: await getPreferredRelaysForPublishing()
        )

        // For events with <10 p-tags, include their READ relays per NIP-65
        if pTags.count < ProtocolConstants.maxPTagsForOutboxModel {
            let pTaggedRelays = await chooseRelayCombinationForPTaggedUsers(
                pTags,
                preferredRelays: await getPreferredRelaysForPublishing()
            )

            // Merge p-tagged user relays into the main map
            for (relayUrl, pubkeys) in pTaggedRelays {
                var existingPubkeys = relayToPubkeys[relayUrl, default: []]
                for pubkey in pubkeys where !existingPubkeys.contains(pubkey) {
                    existingPubkeys.append(pubkey)
                }
                relayToPubkeys[relayUrl] = existingPubkeys
            }
        }

        // Collect all pubkeys for missing relay checks
        var allPubkeys = [authorPubkey]
        if pTags.count < ProtocolConstants.maxPTagsForOutboxModel {
            allPubkeys.append(contentsOf: pTags)
        }

        // Extract missing pubkeys
        let missingRelayPubkeys = await getMissingRelayPubkeys(for: allPubkeys)

        // Special handling for NIP-65 relay lists
        if event.kind == NDKRelayList.kind {
            // For relay lists, also publish to read relays
            if let userItem = await tracker.getRelaysSyncFor(pubkey: event.pubkey, type: .read) {
                for relay in userItem.readRelays {
                    var pubkeys = relayToPubkeys[relay.url, default: []]
                    if !pubkeys.contains(event.pubkey) {
                        pubkeys.append(event.pubkey)
                        relayToPubkeys[relay.url] = pubkeys
                    }
                }
            }
        }

        // Extract relay URLs from the map
        var selectedRelays = Set(relayToPubkeys.keys)

        // Add e-tag relay hints per NIP-10
        for tag in event.tags {
            if tag.count >= 3 && tag[0] == "e" {
                let relayHint = tag[2]
                if !relayHint.isEmpty {
                    selectedRelays.insert(relayHint)
                }
            }
        }

        // Ensure minimum relays
        if selectedRelays.count < OutboxConstants.minPublishRelays {
            let fallbackRelays = await selectFallbackRelays(
                currentCount: selectedRelays.count,
                targetCount: OutboxConstants.minPublishRelays,
                excludeRelays: selectedRelays
            )
            selectedRelays.formUnion(fallbackRelays)
        }

        // Apply soft maximum limit if exceeded
        if selectedRelays.count > OutboxConstants.maxPublishRelays {
            // Rank and limit
            let rankedRelays = await ranker.rankRelays(
                Array(selectedRelays),
                for: allPubkeys,
                preferences: .default
            )
            selectedRelays = Set(rankedRelays.prefix(OutboxConstants.maxPublishRelays).map { $0.url })
        }

        NDKLogger.log(.debug, category: .outbox, "📤 Selected \(selectedRelays.count) relays for publishing (author + \(pTags.count) p-tags)", correlationId: String(correlationId))

        // Record final selection in span
        span.set(SpanAttributes.relayCount, selectedRelays.count)
        span.set(SpanAttributes.relayUrls, Array(selectedRelays))
        span.set("missing_relay_pubkeys", missingRelayPubkeys.count)

        // Trigger discovery for missing relay info
        if !missingRelayPubkeys.isEmpty {
            span.addEvent("relay_discovery_triggered", attributes: [
                "missing_count": .int(missingRelayPubkeys.count)
            ])
            NDKLogger.log(.info, category: .outbox, "🔍 Triggering relay discovery for \(missingRelayPubkeys.count) p-tagged users", correlationId: String(correlationId))
            await ndk.outbox.discoverRelaysInBackground(for: missingRelayPubkeys)
        }

        let method = determineSelectionMethod(selectedRelays)
        span.set("selection_method", method.telemetryValue)
        span.success()

        return RelaySelectionResult(
            relays: selectedRelays,
            missingRelayInfoPubkeys: missingRelayPubkeys,
            selectionMethod: method
        )
    }

    /// Select relays for fetching events
    public func selectRelaysForFetching(
        filter: NDKFilter
    ) async -> RelaySelectionResult {
        // Start telemetry span
        let span = ndk.startSpan("relay.selection.fetch", category: .relaySelection)
        defer { span.end() }

        // Record filter info
        if let authors = filter.authors {
            span.set(SpanAttributes.filterAuthors, authors)
        }
        if let kinds = filter.kinds {
            span.set(SpanAttributes.filterKinds, kinds.map { String($0) })
        }
        if let limit = filter.limit {
            span.set(SpanAttributes.filterLimit, limit)
        }

        // Collect all relevant pubkeys
        var allPubkeys: [String] = []

        // Add current user if signed in
        if let signer = ndk.signer {
            do {
                let userPubkey = try await signer.pubkey
                allPubkeys.append(userPubkey)
            } catch {
                NDKLogger.log(.warning, category: .relay, "Failed to get user pubkey for relay selection: \(error.localizedDescription)")
            }
        }

        // Add authors from filter
        if let authors = filter.authors {
            allPubkeys.append(contentsOf: authors)
        }

        // Add p-tagged pubkeys from filter
        let taggedPubkeys = extractPubkeysFromFilter(filter)
        allPubkeys.append(contentsOf: taggedPubkeys)

        // Remove duplicates
        allPubkeys = Array(Set(allPubkeys))

        // Use improved relay combination selection
        let relayToPubkeys = await chooseRelayCombinationForFetchingAuthors(
            allPubkeys,
            preferredRelays: await getPreferredRelaysForFetching()
        )

        // Extract missing pubkeys
        let missingRelayPubkeys = await getMissingRelayPubkeys(for: allPubkeys)

        // Extract relay URLs
        var selectedRelays = Set(relayToPubkeys.keys)

        // Add event ID hints from HintIndex
        if let eventIds = filter.ids {
            for eventId in eventIds {
                let eventIdHintRelays = await getRelaysFromHintIndex(forEventId: eventId)
                selectedRelays.formUnion(eventIdHintRelays)
            }
        }

        // Ensure minimum relays
        if selectedRelays.count < OutboxConstants.minFetchRelays {
            let fallbackRelays = await selectFallbackRelays(
                currentCount: selectedRelays.count,
                targetCount: OutboxConstants.minFetchRelays,
                excludeRelays: selectedRelays
            )
            selectedRelays.formUnion(fallbackRelays)
        }

        // Apply soft maximum limit if exceeded
        if selectedRelays.count > OutboxConstants.maxFetchRelays {
            // Rank and limit
            let rankedRelays = await ranker.rankRelays(
                Array(selectedRelays),
                for: allPubkeys,
                preferences: .default
            )
            selectedRelays = Set(rankedRelays.prefix(OutboxConstants.maxFetchRelays).map { $0.url })
        }

        NDKLogger.log(.debug, category: .outbox, "🔍 Selected \(selectedRelays.count) relays for fetching from \(allPubkeys.count) authors")

        // Record final selection
        span.set(SpanAttributes.relayCount, selectedRelays.count)
        span.set(SpanAttributes.relayUrls, Array(selectedRelays))
        span.set("target_pubkeys_count", allPubkeys.count)
        span.set("missing_relay_pubkeys", missingRelayPubkeys.count)

        let method = determineSelectionMethod(selectedRelays)
        span.set("selection_method", method.telemetryValue)
        span.success()

        return RelaySelectionResult(
            relays: selectedRelays,
            missingRelayInfoPubkeys: missingRelayPubkeys,
            selectionMethod: method
        )
    }

    /// Select relays for a list of public keys
    func selectRelays(for pubkey: String, count: Int = 5) async -> [String] {
        let filter = NDKFilter(authors: [pubkey])
        let result = await selectRelaysForFetching(filter: filter)
        return Array(result.relays.prefix(count))
    }

    /// Choose relay combination for multiple pubkeys (optimized for minimal connections)
    public func chooseRelayCombinationForPubkeys(
        _ pubkeys: [String],
        type: RelayListType,
        relaysPerAuthor: Int = OutboxConstants.relaysPerAuthor
    ) async -> RelayToPubkeysMap {
        var relayToPubkeys = RelayToPubkeysMap()
        let connectedRelays = await ndk.pool.connectedRelays()

        // Track how many relays each pubkey has been assigned to
        var pubkeyRelayCount: [String: Int] = [:]

        // Get relay info for all pubkeys
        let pubkeyRelayInfo = await getAllRelaysForPubkeys(pubkeys, type: type)

        // Get blocked relays
        let blockedRelays = await getBlockedRelays()

        // First pass: Prioritize connected relays (excluding blocked and invalid ones)
        for relay in connectedRelays {
            let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relay.url) ?? relay.url

            // Skip blocked relays
            if blockedRelays.contains(normalizedUrl) {
                continue
            }

            // Skip relays that are invalid for outbox (localhost and non-secure)
            if !URLNormalizer.isValidForOutbox(relay.url) {
                continue
            }

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
            var currentCount = pubkeyRelayCount[pubkey, default: 0]
            if currentCount >= relaysPerAuthor { continue }

            guard let relays = pubkeyRelayInfo.pubkeysToRelays[pubkey] else { continue }

            // Add relays until we reach the target
            for relayURL in sortedRelays {
                if currentCount >= relaysPerAuthor { break }
                if !relays.contains(relayURL) { continue }

                // Skip blocked relays
                let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
                if blockedRelays.contains(normalizedUrl) { continue }

                // Skip relays that are invalid for outbox (localhost and non-secure)
                if !URLNormalizer.isValidForOutbox(relayURL) { continue }

                var pubkeysInRelay = relayToPubkeys[relayURL, default: []]
                if !pubkeysInRelay.contains(pubkey) {
                    pubkeysInRelay.append(pubkey)
                    relayToPubkeys[relayURL] = pubkeysInRelay
                    currentCount += 1
                    pubkeyRelayCount[pubkey] = currentCount
                }
            }
        }

        // Third pass: Add hint relays directly from HintIndex for each pubkey
        for pubkey in pubkeys {
            let currentCount = pubkeyRelayCount[pubkey, default: 0]
            if currentCount >= relaysPerAuthor { continue }

            // Get hint relays from HintIndex
            guard let hintRelays = pubkeyRelayInfo.pubkeysToRelays[pubkey] else { continue }

            // Add hint relays that aren't already in the map
            for relayURL in hintRelays {
                if pubkeyRelayCount[pubkey, default: 0] >= relaysPerAuthor { break }

                // Skip blocked relays
                let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
                if blockedRelays.contains(normalizedUrl) { continue }

                // Skip relays that are invalid for outbox (localhost and non-secure)
                if !URLNormalizer.isValidForOutbox(relayURL) { continue }

                // Skip if already in the result
                if relayToPubkeys[relayURL]?.contains(pubkey) == true { continue }

                var pubkeysInRelay = relayToPubkeys[relayURL, default: []]
                pubkeysInRelay.append(pubkey)
                relayToPubkeys[relayURL] = pubkeysInRelay
                pubkeyRelayCount[pubkey, default: 0] += 1
            }
        }

        // Fourth pass: Add fallback relays for pubkeys with no relays
        let fallbackRelays = await selectFallbackRelays(currentCount: 0, targetCount: relaysPerAuthor)
        for pubkey in pubkeyRelayInfo.authorsMissingRelays {
            var assignedCount = 0
            for relayURL in fallbackRelays {
                if assignedCount >= relaysPerAuthor { break }

                // Skip blocked relays
                let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
                if blockedRelays.contains(normalizedUrl) { continue }

                // Skip relays that are invalid for outbox (localhost and non-secure)
                if !URLNormalizer.isValidForOutbox(relayURL) { continue }

                var pubkeysInRelay = relayToPubkeys[relayURL, default: []]
                if !pubkeysInRelay.contains(pubkey) {
                    pubkeysInRelay.append(pubkey)
                    relayToPubkeys[relayURL] = pubkeysInRelay
                    assignedCount += 1
                }
            }
        }

        return relayToPubkeys
    }

    // MARK: - Private Methods

    /// Get blocked relays for the current user
    private func getBlockedRelays() async -> Set<String> {
        // Check cache first
        if let cached = blockedRelaysCache,
           let expiry = blockedRelaysCacheExpiry,
           expiry > Date() {
            return cached
        }

        // Check if user is signed in
        guard let signer = ndk.signer else {
            return []
        }

        do {
            _ = try await signer.pubkey
        } catch {
            NDKLogger.log(.warning, category: .relay, "Failed to get pubkey for blocked relays check: \(error.localizedDescription)")
            return []
        }

        // IMPORTANT: Only use blocked relays from session data
        // Blocked relays should be loaded during session initialization, not during relay selection
        if let sessionData = ndk.sessionData {
            let blockedRelays = sessionData.blockedRelays

            // Cache the result
            blockedRelaysCache = blockedRelays
            blockedRelaysCacheExpiry = Date().addingTimeInterval(5 * TimeConstants.minute) // 5 minutes

            return blockedRelays
        }

        // If no session data, return empty set
        // We should NOT try to fetch blocked relays during relay selection
        // as this would create infinite recursion
        return []
    }

    /// Filter out blocked relays from a set
    private func filterBlockedRelays(_ relays: Set<String>) async -> Set<String> {
        let blockedRelays = await getBlockedRelays()
        guard !blockedRelays.isEmpty else { return relays }

        return relays.filter { relay in
            let normalizedRelay = URLNormalizer.tryNormalizeRelayUrl(relay) ?? relay
            return !blockedRelays.contains(normalizedRelay)
        }
    }

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

        // Extract from p tags (mentioned users) - NIP-65 outbox model
        let pTags = event.pTags
        if purpose == .publishing, pTags.count < ProtocolConstants.maxPTagsForOutboxModel {
            // For events with less than 10 p-tags, apply NIP-65 outbox model:
            // Send to read relays of each tagged user
            for pubkey in pTags {
                if let item = await tracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
                    // According to NIP-65: "Send the event to all read relays of each tagged user"
                    relays.formUnion(item.readRelays.map { $0.url })
                    // If no read relays available, fallback to write relays
                    if item.readRelays.isEmpty {
                        relays.formUnion(item.writeRelays.map { $0.url })
                    }
                } else {
                    missingPubkeys.insert(pubkey)
                }
            }
        } else if purpose == .publishing {
            // For events with 10+ p-tags, don't apply outbox model to avoid too many relays
            // Just use author's own relays (handled in selectRelaysForPublishing)
            NDKLogger.log(.debug, category: .outbox, "Event has \(pTags.count) p-tags, skipping outbox model for p-tagged users")
        } else {
            // For fetching, always consider p-tagged users regardless of count
            for pubkey in pTags {
                if let item = await tracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
                    // Fetch from where mentioned users read
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

    private func extractContextualRelaysFromFilter(
        _ filter: NDKFilter
    ) async -> (relays: Set<String>, missingPubkeys: Set<String>) {
        var relays = Set<String>()
        var missingPubkeys = Set<String>()

        // Extract from #p tags
        if let pTags = filter.tags?["p"] {
            for pubkey in pTags {
                if let item = await tracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
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

        var fallbackRelays = Set<String>()
        var candidateRelays: [String] = []

        // 1. First priority: App relays (developer configured)
        let appRelays = await ndk.pool.appRelays
        let availableAppRelays = appRelays
            .filter { !excludeRelays.contains($0.url) }
            .map { $0.url }
        candidateRelays.append(contentsOf: availableAppRelays)

        // 2. Second priority: Current user's relays (from their relay list)
        let currentUserRelays = await ndk.pool.getCurrentUserRelayUrls()
        let availableUserRelays = currentUserRelays
            .filter { !excludeRelays.contains($0) && !candidateRelays.contains($0) }
        candidateRelays.append(contentsOf: availableUserRelays)

        // Take only what we need from the combined candidate list
        fallbackRelays = Set(candidateRelays.prefix(neededCount))

        if !fallbackRelays.isEmpty {
            NDKLogger.log(.debug, category: .outbox, "📍 Selected \(fallbackRelays.count) fallback relays from app+user relays")
        }

        return fallbackRelays
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

                // Filter out relays that are invalid for outbox (localhost and non-secure)
                let validRelays = relays.validForOutbox

                if !validRelays.isEmpty {
                    pubkeysToRelays[pubkey] = validRelays
                } else {
                    // Tracker has no valid relays, try HintIndex as fallback
                    let hintRelays = await getRelaysFromHintIndex(for: pubkey)
                    if !hintRelays.validForOutbox.isEmpty {
                        pubkeysToRelays[pubkey] = hintRelays.validForOutbox
                    } else {
                        authorsMissingRelays.insert(pubkey)
                    }
                }
            } else {
                // No tracker info, try HintIndex as fallback
                let hintRelays = await getRelaysFromHintIndex(for: pubkey)
                if !hintRelays.validForOutbox.isEmpty {
                    pubkeysToRelays[pubkey] = hintRelays.validForOutbox
                } else {
                    authorsMissingRelays.insert(pubkey)
                }
            }
        }

        return (pubkeysToRelays, authorsMissingRelays)
    }

    /// Get relays from HintIndex for a pubkey (used as fallback when tracker has no info)
    private func getRelaysFromHintIndex(for pubkey: String) async -> Set<String> {
        let hints = await ndk.hintIndex.hints(for: pubkey)
        return Set(hints.map { $0.relay })
    }

    /// Get relays from HintIndex for an event ID
    private func getRelaysFromHintIndex(forEventId eventId: String) async -> Set<String> {
        let hints = await ndk.hintIndex.hints(forEventId: eventId)
        return Set(hints.map { $0.relay })
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
            return .appRelays
        } else if relays.count <= 3 {
            return .contextual
        } else {
            return .outbox
        }
    }

    // MARK: - New Helper Methods for Per-Author Relay Selection

    /// Choose relay combination optimized for publishing
    private func chooseRelayCombinationForPublishingAuthors(
        _ pubkeys: [String],
        preferredRelays _: Set<String>
    ) async -> RelayToPubkeysMap {
        // For publishing, we want write relays primarily
        return await chooseRelayCombinationForPubkeys(
            pubkeys,
            type: .write,
            relaysPerAuthor: OutboxConstants.relaysPerAuthor
        )
    }

    /// Choose relay combination for p-tagged users (uses READ relays per NIP-65)
    private func chooseRelayCombinationForPTaggedUsers(
        _ pubkeys: [String],
        preferredRelays _: Set<String>
    ) async -> RelayToPubkeysMap {
        // For p-tagged users, we want read relays per NIP-65
        var relayMap = await chooseRelayCombinationForPubkeys(
            pubkeys,
            type: .read,
            relaysPerAuthor: OutboxConstants.relaysPerAuthor
        )

        // Fallback: if a p-tagged user has no read relays, try their write relays
        let assignedPubkeys = Set(relayMap.values.flatMap { $0 })
        let unassignedPubkeys = pubkeys.filter { !assignedPubkeys.contains($0) }

        if !unassignedPubkeys.isEmpty {
            let fallbackRelayMap = await chooseRelayCombinationForPubkeys(
                unassignedPubkeys,
                type: .write,
                relaysPerAuthor: OutboxConstants.relaysPerAuthor
            )

            // Merge fallback relays into main map
            for (relayUrl, pubkeys) in fallbackRelayMap {
                var existingPubkeys = relayMap[relayUrl, default: []]
                for pubkey in pubkeys where !existingPubkeys.contains(pubkey) {
                    existingPubkeys.append(pubkey)
                }
                relayMap[relayUrl] = existingPubkeys
            }
        }

        return relayMap
    }

    /// Choose relay combination optimized for fetching
    private func chooseRelayCombinationForFetchingAuthors(
        _ pubkeys: [String],
        preferredRelays _: Set<String>
    ) async -> RelayToPubkeysMap {
        // For fetching, we want read relays
        return await chooseRelayCombinationForPubkeys(
            pubkeys,
            type: .read,
            relaysPerAuthor: OutboxConstants.relaysPerAuthorForFetching
        )
    }

    /// Get preferred relays for publishing
    private func getPreferredRelaysForPublishing() async -> Set<String> {
        var preferred = Set<String>()

        // Add app relays
        let appRelays = await ndk.pool.appRelays
        preferred.formUnion(appRelays.map { $0.url })

        // Add connected relays
        let connectedRelays = await ndk.pool.connectedRelays()
        preferred.formUnion(connectedRelays.map { $0.url })

        return preferred
    }

    /// Get preferred relays for fetching
    private func getPreferredRelaysForFetching() async -> Set<String> {
        var preferred = Set<String>()

        // Add connected relays first (most important for fetching)
        let connectedRelays = await ndk.pool.connectedRelays()
        preferred.formUnion(connectedRelays.map { $0.url })

        // Add app relays
        let appRelays = await ndk.pool.appRelays
        preferred.formUnion(appRelays.map { $0.url })

        return preferred
    }

    /// Get missing relay pubkeys from a list
    private func getMissingRelayPubkeys(for pubkeys: [String]) async -> Set<String> {
        var missing = Set<String>()

        for pubkey in pubkeys {
            let hasRelayInfo = await tracker.getRelaysSyncFor(pubkey: pubkey, type: .both) != nil
            if !hasRelayInfo {
                missing.insert(pubkey)
            }
        }

        return missing
    }
}

// MARK: - Configuration Types

/// Configuration for relay combination selection

// MARK: - Result Types

/// Result of relay selection
struct RelaySelectionResult: Sendable {
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
enum SelectionMethod: Sendable {
    case outbox
    case contextual
    case appRelays

    var telemetryValue: String {
        switch self {
        case .outbox: return "outbox"
        case .contextual: return "contextual"
        case .appRelays: return "app_relays"
        }
    }
}
