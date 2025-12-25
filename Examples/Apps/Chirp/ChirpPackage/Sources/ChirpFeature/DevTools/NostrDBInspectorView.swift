import SwiftUI
import NDKSwiftCore
import NDKSwiftNostrDB

struct NostrDBInspectorView: View {
    @Environment(ChirpState.self) private var state
    @State private var cacheStats: NdbStat?
    @State private var databaseSize: Int64 = 0
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let stats = cacheStats {
                Section("Overview") {
                    LabeledContent("Total Events", value: "\(stats.totalEvents)")
                    LabeledContent("Database Size") {
                        Text(formatBytes(databaseSize))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Storage Size") {
                        Text(formatBytes(Int64(stats.totalStorageSize)))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Databases") {
                    ForEach(Array(stats.databases.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.rawValue) { db in
                        if let dbStats = stats.databases[db] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(db)")
                                    .font(.headline)
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Events")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(dbStats.count)")
                                            .font(.subheadline)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("Size")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(formatBytes(Int64(dbStats.totalSize)))
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Events by Kind") {
                    ForEach(stats.kinds.keys.sorted(), id: \.self) { kind in
                        if let kindStats = stats.kinds[kind] {
                            HStack {
                                VStack(alignment: .leading) {
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
            } else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("NostrDB cache not available")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("NostrDB Inspector")
        .task {
            await loadStats()
        }
        .refreshable {
            await loadStats()
        }
    }

    private func loadStats() async {
        isLoading = true
        if let cache = state.ndk.cache as? NDKNostrDBCache {
            cacheStats = await cache.getStats()
            databaseSize = await cache.getDatabaseSize()
        }
        isLoading = false
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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

#Preview {
    NavigationStack {
        NostrDBInspectorView()
    }
}
