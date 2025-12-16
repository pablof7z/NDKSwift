import Foundation
import NDKSwiftCore
import NDKSwiftSQLite
import NDKSwiftNostrDB

public enum CacheType: String, CaseIterable, Identifiable {
    case sqlite = "SQLite"
    case nostrdb = "NostrDB"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var description: String {
        switch self {
        case .sqlite:
            return "Full-featured SQL cache with GRDB. 13 migrations, reactive observations."
        case .nostrdb:
            return "High-performance LMDB cache with full-text search. Not supported on iOS Simulator."
        }
    }

    public var isAvailableOnCurrentPlatform: Bool {
        #if targetEnvironment(simulator)
        if self == .nostrdb {
            return false
        }
        #endif
        return true
    }

    public static var availableCases: [CacheType] {
        allCases.filter { $0.isAvailableOnCurrentPlatform }
    }

    public func createCache() async throws -> NDKCache {
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

public enum CacheError: Error, LocalizedError {
    case platformNotSupported

    public var errorDescription: String? {
        switch self {
        case .platformNotSupported:
            return "NostrDB cache is not supported on iOS Simulator"
        }
    }
}
