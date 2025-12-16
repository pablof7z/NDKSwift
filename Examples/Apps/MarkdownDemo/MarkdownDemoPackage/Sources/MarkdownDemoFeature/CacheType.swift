import Foundation
import NDKSwiftCore
import NDKSwiftSQLite
import NDKSwiftNostrDB

enum CacheType: String, CaseIterable, Identifiable {
    case sqlite = "SQLite"
    case nostrdb = "NostrDB"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .sqlite:
            return "Full-featured SQL cache with GRDB. 13 migrations, reactive observations."
        case .nostrdb:
            return "High-performance LMDB cache with full-text search. Not supported on iOS Simulator."
        }
    }

    var isAvailableOnCurrentPlatform: Bool {
        #if targetEnvironment(simulator)
        if self == .nostrdb {
            return false
        }
        #endif
        return true
    }

    static var availableCases: [CacheType] {
        allCases.filter { $0.isAvailableOnCurrentPlatform }
    }

    func createCache() async throws -> NDKCache {
        switch self {
        case .sqlite:
            return try await NDKSQLiteCache(path: nil, debugMode: true)
        case .nostrdb:
            guard isAvailableOnCurrentPlatform else {
                throw CacheError.platformNotSupported
            }
            return try await NDKNostrDBCache(path: nil)
        }
    }
}

enum CacheError: Error, LocalizedError {
    case platformNotSupported

    var errorDescription: String? {
        switch self {
        case .platformNotSupported:
            return "NostrDB cache is not supported on iOS Simulator"
        }
    }
}
