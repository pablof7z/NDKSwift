import SwiftUI
import NDKSwift

struct NostrDBStatsView: View {
    let ndk: NDK

    @State private var stats: NdbStat?
    @State private var databaseSize: Int64 = 0
    @State private var cachePath: String?
    @State private var inMemoryCount: Int = 0
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading statistics...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let stats = stats {
                // Overview Section
                Section("Overview") {
                    StatRow(label: "Total Events", value: formatNumber(stats.totalEvents))
                    StatRow(label: "Total Storage", value: formatBytes(Int64(stats.totalStorageSize)))
                    StatRow(label: "Database Files", value: formatBytes(databaseSize))
                    StatRow(label: "In-Memory Cache", value: "\(inMemoryCount) events")
                }

                // Event Kinds Section
                Section("Events by Kind") {
                    ForEach(NdbCommonKind.allCases, id: \.self) { kind in
                        if let counts = stats.commonKinds[kind], counts.count > 0 {
                            KindStatRow(kind: kind, counts: counts)
                        }
                    }

                    if stats.otherKinds.count > 0 {
                        HStack {
                            Text("Other Kinds")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(stats.otherKinds.count)")
                                    .font(.system(.body, design: .monospaced))
                                Text(formatBytes(Int64(stats.otherKinds.totalSize)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Database Indexes Section
                Section("Database Indexes") {
                    ForEach(NdbDatabase.allCases, id: \.self) { db in
                        if let counts = stats.databases[db], counts.count > 0 {
                            DatabaseStatRow(database: db, counts: counts)
                        }
                    }
                }

                // Storage Breakdown
                Section("Storage Details") {
                    if let cachePath = cachePath {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cache Path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cachePath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Section {
                    Text("Unable to load statistics")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("NostrDB Stats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadStats()
        }
        .refreshable {
            await loadStats()
        }
    }

    private func loadStats() async {
        isLoading = true
        if let cache = ndk.cache as? NDKNostrDBCache {
            stats = await cache.getStats()
            databaseSize = await cache.getDatabaseSize()
            cachePath = await cache.getCachePath()
            inMemoryCount = await cache.inMemoryEventCount
        }
        isLoading = false
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Views

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct KindStatRow: View {
    let kind: NdbCommonKind
    let counts: NdbStatCounts

    var body: some View {
        HStack {
            Text(kind.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(counts.count)")
                    .font(.system(.body, design: .monospaced))
                Text(formatBytes(Int64(counts.totalSize)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct DatabaseStatRow: View {
    let database: NdbDatabase
    let counts: NdbStatCounts

    var body: some View {
        HStack {
            Text(database.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(counts.count) entries")
                    .font(.system(.caption, design: .monospaced))
                HStack(spacing: 8) {
                    Text("K: \(formatBytes(Int64(counts.keySize)))")
                    Text("V: \(formatBytes(Int64(counts.valueSize)))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
