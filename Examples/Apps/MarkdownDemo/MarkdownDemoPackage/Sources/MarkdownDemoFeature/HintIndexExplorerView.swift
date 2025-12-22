import SwiftUI
import NDKSwiftCore

/// Browsable view into the HintIndex data
/// Shows most known relays and allows browsing pubkey/event hints
public struct HintIndexExplorerView: View {
    let ndk: NDK

    @State private var selectedTab = ExplorerTab.relays
    @State private var mostKnownRelays: [RelayMention] = []
    @State private var pubkeyHints: [String: [HintEntry]] = [:]
    @State private var eventIdHints: [String: [HintEntry]] = [:]
    @State private var searchText = ""
    @State private var expandedPubkeys: Set<String> = []
    @State private var expandedEvents: Set<String> = []
    @State private var isLoading = true

    enum ExplorerTab: String, CaseIterable {
        case relays = "Top Relays"
        case pubkeys = "Pubkeys"
        case events = "Events"
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(ExplorerTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Search bar (for pubkeys/events tabs)
            if selectedTab != .relays {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Content
            if isLoading {
                ProgressView("Loading hints...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .relays:
                    relaysTab
                case .pubkeys:
                    pubkeysTab
                case .events:
                    eventsTab
                }
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Top Relays Tab

    private var relaysTab: some View {
        List {
            if mostKnownRelays.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No relay data yet")
                            .foregroundColor(.secondary)
                        Text("Hints will appear as you browse content")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section("Relays by Mention Count") {
                    ForEach(Array(mostKnownRelays.enumerated()), id: \.offset) { index, mention in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatRelayURL(mention.relay))
                                    .font(.body)
                                Text(mention.relay)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text("\(mention.mentionCount)")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Pubkeys Tab

    private var pubkeysTab: some View {
        let filteredPubkeys = filteredPubkeyList

        return List {
            if filteredPubkeys.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No pubkey hints yet" : "No matches found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section("\(filteredPubkeys.count) Pubkeys with Hints") {
                    ForEach(filteredPubkeys, id: \.key) { pubkey, hints in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedPubkeys.contains(pubkey) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedPubkeys.insert(pubkey)
                                    } else {
                                        expandedPubkeys.remove(pubkey)
                                    }
                                }
                            )
                        ) {
                            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                                HintEntryRow(hint: hint)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(truncatePubkey(pubkey))
                                        .font(.system(.body, design: .monospaced))
                                    if let npub = try? String.toNpub(pubkey) {
                                        Text(npub.prefix(20) + "...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Text("\(hints.count)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filteredPubkeyList: [(key: String, value: [HintEntry])] {
        let items = pubkeyHints.sorted { $0.value.count > $1.value.count }
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Events Tab

    private var eventsTab: some View {
        let filteredEvents = filteredEventList

        return List {
            if filteredEvents.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No event hints yet" : "No matches found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section("\(filteredEvents.count) Events with Hints") {
                    ForEach(filteredEvents, id: \.key) { eventId, hints in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedEvents.contains(eventId) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedEvents.insert(eventId)
                                    } else {
                                        expandedEvents.remove(eventId)
                                    }
                                }
                            )
                        ) {
                            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                                HintEntryRow(hint: hint)
                            }
                        } label: {
                            HStack {
                                Text(truncateEventId(eventId))
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                Text("\(hints.count)")
                                    .font(.caption.monospacedDigit())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filteredEventList: [(key: String, value: [HintEntry])] {
        let items = eventIdHints.sorted { $0.value.count > $1.value.count }
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true

        mostKnownRelays = await ndk.hintIndex.mostKnownRelays(limit: 20)
        pubkeyHints = await ndk.hintIndex.allPubkeyHints
        eventIdHints = await ndk.hintIndex.allEventIdHints

        isLoading = false
    }

    // MARK: - Helpers

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
           .replacingOccurrences(of: "ws://", with: "")
    }

    private func truncatePubkey(_ pubkey: String) -> String {
        if pubkey.count > 16 {
            return String(pubkey.prefix(8)) + "..." + String(pubkey.suffix(8))
        }
        return pubkey
    }

    private func truncateEventId(_ eventId: String) -> String {
        if eventId.count > 16 {
            return String(eventId.prefix(8)) + "..." + String(eventId.suffix(8))
        }
        return eventId
    }
}

// MARK: - Hint Entry Row

struct HintEntryRow: View {
    let hint: HintEntry

    private var timeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }

    var body: some View {
        HStack {
            // Source badge
            Text(sourceLabel)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sourceColor.opacity(0.2))
                .foregroundColor(sourceColor)
                .cornerRadius(4)

            // Relay
            Text(formatRelayURL(hint.relay))
                .font(.caption)
                .lineLimit(1)

            Spacer()

            // Time
            Text(timeFormatter.localizedString(for: hint.recordedAt, relativeTo: Date()))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var sourceLabel: String {
        switch hint.source {
        case .nip19: return "NIP-19"
        case .eventObserved: return "Observed"
        case .userRelayList: return "Relay List"
        case .explicit: return "Explicit"
        }
    }

    private var sourceColor: Color {
        switch hint.source {
        case .nip19: return .blue
        case .eventObserved: return .green
        case .userRelayList: return .orange
        case .explicit: return .purple
        }
    }

    private func formatRelayURL(_ url: String) -> String {
        url.replacingOccurrences(of: "wss://", with: "")
           .replacingOccurrences(of: "ws://", with: "")
    }
}

// MARK: - Preview

#if DEBUG
struct HintIndexExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        HintIndexExplorerView(ndk: NDK())
    }
}
#endif
