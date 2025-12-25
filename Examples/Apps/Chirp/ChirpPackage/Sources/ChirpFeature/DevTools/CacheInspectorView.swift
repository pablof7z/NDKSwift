import SwiftUI
import NDKSwiftCore
import NDKSwiftNostrDB

struct CacheInspectorView: View {
    @Environment(ChirpState.self) private var state
    @State private var stats: NdbStat?

    var body: some View {
        List {
            if let stats = stats {
                Section("Event Kinds") {
                    ForEach(stats.kinds.keys.sorted(), id: \.self) { kind in
                        if let kindStats = stats.kinds[kind] {
                            NavigationLink {
                                CachedEventsListView(kind: Int(kind))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Kind \(kind)")
                                            .font(.body)
                                        Text(kindDescription(Int(kind)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(kindStats.count)")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Loading cache statistics...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Cache Inspector")
        .task {
            await loadStats()
        }
        .refreshable {
            await loadStats()
        }
    }

    private func loadStats() async {
        if let cache = state.ndk.cache as? NDKNostrDBCache {
            stats = await cache.getStats()
        }
    }

    private func kindDescription(_ kind: Int) -> String {
        switch kind {
        case 0: return "Metadata"
        case 1: return "Short Text Note"
        case 2: return "Recommend Relay"
        case 3: return "Contacts"
        case 4: return "Encrypted DM"
        case 5: return "Event Deletion"
        case 6: return "Repost"
        case 7: return "Reaction"
        case 8: return "Badge Award"
        case 9: return "Group Chat Message"
        case 10: return "Group Chat Threaded Reply"
        case 40: return "Channel Creation"
        case 41: return "Channel Metadata"
        case 42: return "Channel Message"
        case 43: return "Channel Hide Message"
        case 44: return "Channel Mute User"
        case 1063: return "File Metadata"
        case 1111: return "Comment"
        case 1984: return "Reporting"
        case 1985: return "Label"
        case 9735: return "Zap"
        case 9734: return "Zap Request"
        case 10000: return "Mute List"
        case 10001: return "Pin List"
        case 10002: return "Relay List Metadata"
        case 30000: return "Categorized People List"
        case 30001: return "Categorized Bookmark List"
        case 30008: return "Profile Badges"
        case 30009: return "Badge Definition"
        case 30023: return "Long-form Content"
        case 30078: return "Application-specific Data"
        default: return "Unknown"
        }
    }
}

struct CachedEventsListView: View {
    @Environment(ChirpState.self) private var state
    let kind: Int
    @State private var events: [NDKEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No cached events of this kind")
                )
            } else {
                ForEach(events, id: \.id) { event in
                    NavigationLink {
                        CachedEventDetailView(event: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.id.prefix(16) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                            if !event.content.isEmpty {
                                Text(event.content)
                                    .font(.body)
                                    .lineLimit(2)
                            }

                            HStack {
                                Text(formatPubkey(event.pubkey))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(Date(timeIntervalSince1970: TimeInterval(event.createdAt)), style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Kind \(kind)")
        .task {
            await loadEvents()
        }
    }

    private func loadEvents() async {
        let filter = NDKFilter(kinds: [kind], limit: 100)
        // .cacheOnly is correct here - we're inspecting what's in the cache
        let dataSource = state.ndk.subscribe(filter: filter, maxAge: 0, cachePolicy: .cacheOnly)

        // Stream events as they arrive from cache
        for await batch in dataSource.events {
            await MainActor.run {
                let existingIds = Set(events.map { $0.id })
                let newEvents = batch.filter { !existingIds.contains($0.id) }
                if !newEvents.isEmpty {
                    events.append(contentsOf: newEvents)
                    events.sort { $0.createdAt > $1.createdAt }
                }
            }
            if events.count >= 100 { break }
        }
    }

    private func formatPubkey(_ pubkey: String) -> String {
        if let npub = try? Bech32.npub(from: pubkey) {
            return String(npub.prefix(12)) + "..."
        }
        return String(pubkey.prefix(8)) + "..."
    }
}

struct CachedEventDetailView: View {
    let event: NDKEvent

    var body: some View {
        List {
            Section("Event ID") {
                Text(event.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Section("Pubkey") {
                VStack(alignment: .leading, spacing: 4) {
                    if let npub = try? Bech32.npub(from: event.pubkey) {
                        Text(npub)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Text(event.pubkey)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Created At") {
                Text(Date(timeIntervalSince1970: TimeInterval(event.createdAt)), style: .date)
                Text(Date(timeIntervalSince1970: TimeInterval(event.createdAt)), style: .time)
            }

            if !event.content.isEmpty {
                Section("Content") {
                    Text(event.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            if !event.tags.isEmpty {
                Section("Tags (\(event.tags.count))") {
                    ForEach(Array(event.tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            if !event.sig.isEmpty {
                Section("Signature") {
                    Text(event.sig)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Event Details")
    }
}

#Preview {
    NavigationStack {
        CacheInspectorView()
    }
}
