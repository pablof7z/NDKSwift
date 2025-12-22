import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Explores the outbox model by showing relay selection decisions
/// Enter a NIP-05 or npub to see which relays would be used for their feed
public struct OutboxExplorerView: View {
    let ndk: NDK

    @State private var identifier = ""
    @State private var isLoading = false
    @State private var loadingStatus = ""
    @State private var resolvedUser: NDKUser?
    @State private var follows: [FollowInfo] = []
    @State private var outboxStrategy: OutboxStrategyInfo?
    @State private var relayDecisions: [RelayDecision] = []
    @State private var feedDataSource: NDKEventDataSource?
    @State private var poolSnapshot: PoolSnapshot?
    @State private var error: String?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Input section
                inputSection

                // Error display
                if let error = error {
                    errorSection(error)
                }

                // Loading indicator
                if isLoading {
                    loadingSection
                }

                // Resolved user info
                if let user = resolvedUser {
                    userSection(user)
                }

                // Outbox strategy
                if let strategy = outboxStrategy {
                    strategySection(strategy)
                }

                // Relay decisions detail
                if !relayDecisions.isEmpty {
                    relayDecisionsSection
                }

                // Pool state
                if let pool = poolSnapshot {
                    poolSection(pool)
                }

                // Feed preview
                if let ds = feedDataSource, !ds.events.isEmpty {
                    feedPreviewSection(ds)
                }
            }
            .padding()
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter NIP-05 or npub")
                .font(.headline)

            HStack {
                TextField("e.g. pablo@primal.net or npub1...", text: $identifier)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button(action: lookup) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Lookup")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(identifier.isEmpty || isLoading)
            }

            Text("This will fetch their follows and show which relays would be used")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.caption)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        HStack {
            ProgressView()
            Text(loadingStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - User Section

    private func userSection(_ user: NDKUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Resolved User")
                        .font(.headline)
                    Text(user.pubkey.prefix(16) + "...")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            if !follows.isEmpty {
                Text("\(follows.count) follows loaded")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Strategy Section

    private func strategySection(_ strategy: OutboxStrategyInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.purple)
                Text("Outbox Strategy")
                    .font(.headline)
            }

            // Summary cards
            HStack(spacing: 12) {
                strategyCard(
                    title: "Relays",
                    value: "\(strategy.relayCount)",
                    subtitle: "to query",
                    color: .blue
                )
                strategyCard(
                    title: "Known",
                    value: "\(strategy.knownAuthors)",
                    subtitle: "authors",
                    color: .green
                )
                strategyCard(
                    title: "Unknown",
                    value: "\(strategy.unknownAuthors)",
                    subtitle: "authors",
                    color: .orange
                )
            }

            if strategy.newRelaysNeeded > 0 {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.green)
                    Text("Would connect to \(strategy.newRelaysNeeded) new relays")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // Execute button
            Button(action: executeSubscription) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Execute Subscription")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
    }

    private func strategyCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Relay Decisions Section

    private var relayDecisionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.indigo)
                Text("Relay → Authors Mapping")
                    .font(.headline)
            }

            Text("Which relays would be queried for which authors:")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(relayDecisions.sorted { $0.authorCount > $1.authorCount }, id: \.relay) { decision in
                relayDecisionRow(decision)
            }
        }
        .padding()
        .background(Color.indigo.opacity(0.05))
        .cornerRadius(12)
    }

    private func relayDecisionRow(_ decision: RelayDecision) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(decision.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(decision.displayRelay)
                    .font(.subheadline.monospaced())
                    .lineLimit(1)

                Spacer()

                Text("\(decision.authorCount) authors")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }

            if !decision.isConnected {
                Text("Not connected - would need to connect")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Pool Section

    private func poolSection(_ pool: PoolSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.teal)
                Text("Relay Pool Status")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                poolStat(title: "Connected", value: pool.connected, color: .green)
                poolStat(title: "Persistent", value: pool.persistent, color: .blue)
                poolStat(title: "Dynamic", value: pool.dynamic, color: .orange)
            }

            if pool.dynamic > 0 {
                Text("Dynamic relays were added by outbox model!")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.teal.opacity(0.05))
        .cornerRadius(12)
    }

    private func poolStat(title: String, value: Int, color: Color) -> some View {
        VStack {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feed Preview Section

    private func feedPreviewSection(_ ds: NDKEventDataSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.cyan)
                Text("Feed Preview (\(ds.events.count) notes)")
                    .font(.headline)
            }

            ForEach(ds.events.prefix(5), id: \.id) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.pubkey.prefix(12) + "...")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Text(event.content.prefix(100) + (event.content.count > 100 ? "..." : ""))
                        .font(.caption)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }

            if ds.events.count > 5 {
                Text("... and \(ds.events.count - 5) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.cyan.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func lookup() {
        Task {
            await performLookup()
        }
    }

    @MainActor
    private func performLookup() async {
        isLoading = true
        error = nil
        resolvedUser = nil
        follows = []
        outboxStrategy = nil
        relayDecisions = []
        feedDataSource = nil

        defer { isLoading = false }

        // Step 1: Resolve identifier
        loadingStatus = "Resolving identifier..."
        let (user, pubkey) = resolveIdentifier(identifier)
        guard let resolvedPubkey = pubkey else {
            error = "Could not resolve identifier"
            return
        }
        resolvedUser = user

        // Step 2: Fetch follows by getting kind 3 contact list
        loadingStatus = "Fetching follows..."
        let followPubkeys = await fetchFollowPubkeys(for: resolvedPubkey)
        follows = followPubkeys.map { FollowInfo(pubkey: $0) }

        if follows.isEmpty {
            error = "User has no follows"
            return
        }

        // Step 3: Get outbox strategy
        loadingStatus = "Computing outbox strategy..."
        await computeOutboxStrategy()

        // Step 4: Snapshot pool state
        await snapshotPool()
    }

    private func resolveIdentifier(_ id: String) -> (NDKUser?, String?) {
        // Try as npub first
        if id.hasPrefix("npub") {
            let user = ndk.getUser(id)
            return (user, user?.pubkey)
        }

        // Try as NIP-05 (not yet supported)
        if id.contains("@") {
            return (nil, nil)
        }

        // Try as hex pubkey
        if id.count == 64 {
            let user = ndk.getUser(id)
            return (user, id)
        }

        return (nil, nil)
    }

    private func fetchFollowPubkeys(for pubkey: String) async -> [String] {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [3]
        )

        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 10 * 60
        )

        let events = await dataSource.collect(timeout: 5.0)
        guard let event = events.mostRecent else {
            return []
        }

        return event.tags
            .filter { $0.first == "p" }
            .compactMap { $0.dropFirst().first }
            .map { String($0) }
    }

    private func computeOutboxStrategy() async {
        let followPubkeys = follows.map { $0.pubkey }

        // Create filter for follows' notes
        let filter = NDKFilter(
            authors: followPubkeys,
            kinds: [1],
            limit: 50
        )

        // Get outbox strategy and extract data in one async context
        let (decisions, strategyInfo) = await extractOutboxStrategyData(filter: filter)

        relayDecisions = decisions
        outboxStrategy = strategyInfo
    }

    private func extractOutboxStrategyData(filter: NDKFilter) async -> ([RelayDecision], OutboxStrategyInfo) {
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)
        let connectedRelays = await ndk.pool.connectedRelayURLs

        var decisions: [RelayDecision] = []
        var newRelaysNeeded = 0

        for (relay, relayFilter) in strategy.filtersByRelay {
            let authorCount = relayFilter.authors?.count ?? 0
            let isConnected = connectedRelays.contains(relay)
            if !isConnected {
                newRelaysNeeded += 1
            }

            decisions.append(RelayDecision(
                relay: relay,
                authorCount: authorCount,
                isConnected: isConnected
            ))
        }

        let info = OutboxStrategyInfo(
            relayCount: strategy.filtersByRelay.count,
            knownAuthors: strategy.totalAuthors,
            unknownAuthors: strategy.unknownAuthors.count,
            newRelaysNeeded: newRelaysNeeded
        )

        return (decisions, info)
    }

    private func snapshotPool() async {
        let relays = await ndk.pool.relays
        var connected = 0
        var persistent = 0
        var dynamic = 0

        for relay in relays {
            let state = await relay.connectionState
            let isPersistent = await relay.isPersistent

            if case .connected = state { connected += 1 }
            else if case .authenticated = state { connected += 1 }

            if isPersistent {
                persistent += 1
            } else {
                dynamic += 1
            }
        }

        poolSnapshot = PoolSnapshot(
            total: relays.count,
            connected: connected,
            persistent: persistent,
            dynamic: dynamic
        )
    }

    private func executeSubscription() {
        Task {
            await performSubscription()
        }
    }

    @MainActor
    private func performSubscription() async {
        isLoading = true
        loadingStatus = "Executing subscription with outbox model..."

        let followPubkeys = follows.map { $0.pubkey }

        // Create and execute subscription
        feedDataSource = NDKEventDataSource(
            ndk: ndk,
            filter: NDKFilter(
                authors: followPubkeys,
                kinds: [1],
                limit: 50
            ),
            sortDescending: true
        )

        // Wait a bit for events to come in
        try? await Task.sleep(for: .seconds(3))

        // Re-snapshot pool to see new connections
        await snapshotPool()

        // Recompute strategy to see updated state
        await computeOutboxStrategy()

        isLoading = false
    }
}

// MARK: - Supporting Types

struct FollowInfo: Identifiable {
    let id = UUID()
    let pubkey: String
}

struct OutboxStrategyInfo {
    let relayCount: Int
    let knownAuthors: Int
    let unknownAuthors: Int
    let newRelaysNeeded: Int
}

struct RelayDecision: Identifiable {
    var id: String { relay }
    let relay: String
    let authorCount: Int
    let isConnected: Bool

    var displayRelay: String {
        relay.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}

struct PoolSnapshot {
    let total: Int
    let connected: Int
    let persistent: Int
    let dynamic: Int
}

// MARK: - Preview

#if DEBUG
struct OutboxExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        OutboxExplorerView(ndk: NDK())
    }
}
#endif
