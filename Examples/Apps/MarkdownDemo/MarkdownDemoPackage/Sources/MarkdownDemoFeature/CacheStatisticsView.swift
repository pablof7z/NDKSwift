import SwiftUI
import NDKSwiftCore
import NDKSwiftSQLite
import NDKSwiftNostrDB

struct CacheStatisticsView: View {
    let cache: NDKCache
    let cacheType: CacheType

    @State private var isLoading = true
    @State private var statistics: CacheStatisticsData?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading statistics...")
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error Loading Statistics",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let stats = statistics {
                statisticsContent(stats)
            }
        }
        .task {
            await loadStatistics()
        }
    }

    @ViewBuilder
    private func statisticsContent(_ stats: CacheStatisticsData) -> some View {
        List {
            Section("Overview") {
                LabeledContent("Cache Type", value: cacheType.displayName)
                LabeledContent("Total Events", value: "\(stats.totalEvents)")

                if let storageSize = stats.storageSize {
                    LabeledContent("Storage Size", value: formatBytes(storageSize))
                }
            }

            if !stats.eventsByKind.isEmpty {
                Section("Events by Kind") {
                    ForEach(stats.eventsByKind.sorted(by: { $0.value > $1.value }), id: \.key) { kind, count in
                        LabeledContent("Kind \(kind)", value: "\(count)")
                    }
                }
            }

            if let profileCount = stats.profileCount {
                Section("Profiles") {
                    LabeledContent("Total Profiles", value: "\(profileCount)")
                }
            }

            if let kvEntries = stats.kvEntries {
                Section("Key-Value Store") {
                    LabeledContent("Total Entries", value: "\(kvEntries)")
                }
            }

            if let cachePath = stats.cachePath {
                Section("Database") {
                    LabeledContent("Path", value: cachePath)
                        .font(.caption)
                }
            }

            if let nostrDBStats = stats.nostrDBStats {
                nostrDBStatisticsSection(nostrDBStats)
            }
        }
    }

    @ViewBuilder
    private func nostrDBStatisticsSection(_ ndbStats: NdbStat) -> some View {
        Section("NostrDB Details") {
            LabeledContent("Total Storage", value: formatBytes(Int64(ndbStats.totalStorageSize)))

            ForEach(Array(ndbStats.databases.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { db in
                if let counts = ndbStats.databases[db] {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(db.description)
                            .font(.headline)
                        HStack {
                            Text("Count: \(counts.count)")
                            Spacer()
                            Text("Size: \(formatBytes(Int64(counts.totalSize)))")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func loadStatistics() async {
        isLoading = true
        errorMessage = nil

        do {
            statistics = try await fetchStatistics()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchStatistics() async throws -> CacheStatisticsData {
        switch cacheType {
        case .sqlite:
            guard let sqlCache = cache as? NDKSQLiteCache else {
                throw CacheError.platformNotSupported
            }

            async let statsResult = sqlCache.getStatistics()
            async let cacheStatsResult = sqlCache.getCacheStats()

            let stats = try await statsResult
            let cacheStats = await cacheStatsResult

            let totalEvents = stats.totalEvents
            let eventsByKind = stats.eventsByKind

            return CacheStatisticsData(
                totalEvents: totalEvents,
                eventsByKind: eventsByKind,
                profileCount: cacheStats.profiles,
                kvEntries: cacheStats.kvEntries,
                storageSize: nil,
                cachePath: nil,
                nostrDBStats: nil
            )

        case .nostrdb:
            guard let ndbCache = cache as? NDKNostrDBCache else {
                throw CacheError.platformNotSupported
            }

            let ndbStats = await ndbCache.getStats()
            let dbSize = await ndbCache.getDatabaseSize()
            let cachePath = await ndbCache.getCachePath()

            var eventsByKind: [Int: Int] = [:]
            if let stats = ndbStats {
                for (kind, counts) in stats.kinds {
                    eventsByKind[Int(kind)] = counts.count
                }
            }

            return CacheStatisticsData(
                totalEvents: ndbStats?.totalEvents ?? 0,
                eventsByKind: eventsByKind,
                profileCount: nil,
                kvEntries: nil,
                storageSize: dbSize,
                cachePath: cachePath,
                nostrDBStats: ndbStats
            )
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct CacheStatisticsData {
    let totalEvents: Int
    let eventsByKind: [Int: Int]
    let profileCount: Int?
    let kvEntries: Int?
    let storageSize: Int64?
    let cachePath: String?
    let nostrDBStats: NdbStat?
}

extension NdbDatabase {
    var description: String {
        return self.name
    }
}
