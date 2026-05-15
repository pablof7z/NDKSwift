import Foundation
import SQLite3

// MARK: - SQLite Auxiliary Store
//
// Persists the non-event cache state that commit e9925313 ("remove NDKCache
// protocol") left in memory-only:
//
//   - NIP-05 verification cache (NIP05CacheEntry by identifier)
//   - Generic key/value store (namespace, key) -> Data
//   - Decrypted content cache (key -> decrypted content text)
//   - NIP-09 deletion markers (event id -> deleted-at)
//   - Per-filter fetch timestamps (filter fingerprint -> fetched-at)
//
// The event store itself stays in NostrDB/LMDB — this layer only handles the
// auxiliary stores that NostrDB doesn't natively model.
//
// One SQLite database file lives alongside the NostrDB LMDB files
// (`<cache-path>/ndkswift-aux.sqlite`). The whole thing is wrapped in an
// actor so concurrent writes serialize cleanly; SQLite is opened with
// `SQLITE_OPEN_FULLMUTEX` for defense in depth.

internal actor NDKCacheSQLiteStore {
    enum Error: Swift.Error, CustomStringConvertible {
        case openFailed(code: Int32, message: String)
        case prepareFailed(sql: String, code: Int32, message: String)
        case stepFailed(code: Int32, message: String)

        var description: String {
            switch self {
            case let .openFailed(code, message):
                return "SQLite open failed (\(code)): \(message)"
            case let .prepareFailed(sql, code, message):
                return "SQLite prepare failed (\(code)) for `\(sql)`: \(message)"
            case let .stepFailed(code, message):
                return "SQLite step failed (\(code)): \(message)"
            }
        }
    }

    private let path: String
    private var db: OpaquePointer?

    init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "<no handle>"
            if let handle { sqlite3_close_v2(handle) }
            throw Error.openFailed(code: result, message: msg)
        }
        db = handle
        // WAL mode for better concurrency; busy_timeout so writers wait
        // briefly instead of returning SQLITE_BUSY on contention.
        try Self.initializeDatabase(handle)
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Migrations

    private static func initializeDatabase(_ db: OpaquePointer?) throws {
        _ = exec("PRAGMA journal_mode=WAL;", db: db)
        _ = exec("PRAGMA synchronous=NORMAL;", db: db)
        _ = exec("PRAGMA busy_timeout=2000;", db: db)
        try migrate(db: db)
    }

    private static func migrate(db: OpaquePointer?) throws {
        try execOrThrow("""
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        """, db: db)

        let currentVersion = currentSchemaVersion(db: db) ?? 0
        if currentVersion < 1 {
            try execOrThrow("""
            CREATE TABLE IF NOT EXISTS kv (
                namespace TEXT NOT NULL,
                key TEXT NOT NULL,
                value BLOB NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (namespace, key)
            );

            CREATE TABLE IF NOT EXISTS deleted_events (
                event_id TEXT PRIMARY KEY,
                deleted_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS decrypted_content (
                key TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                cached_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS nip05_cache (
                identifier TEXT PRIMARY KEY,
                entry_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_nip05_identifier
                ON nip05_cache(identifier);

            CREATE TABLE IF NOT EXISTS fetch_times (
                fingerprint TEXT PRIMARY KEY,
                fetched_at INTEGER NOT NULL
            );

            INSERT OR REPLACE INTO schema_version(version) VALUES (1);
            """, db: db)
        }
    }

    private static func currentSchemaVersion(db: OpaquePointer?) -> Int? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT MAX(version) FROM schema_version;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let v = sqlite3_column_int(stmt, 0)
        return Int(v)
    }

    // MARK: - KV store

    func setKV(namespace: String, key: String, value: Data) throws {
        let sql = "INSERT OR REPLACE INTO kv(namespace, key, value, updated_at) VALUES (?, ?, ?, ?);"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, namespace, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
            value.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))
        }
    }

    func getKV(namespace: String, key: String) throws -> Data? {
        let sql = "SELECT value FROM kv WHERE namespace = ? AND key = ?;"
        var result: Data?
        try query(sql, bind: { stmt in
            sqlite3_bind_text(stmt, 1, namespace, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        }) { stmt in
            guard let blob = sqlite3_column_blob(stmt, 0) else {
                result = Data()
                return
            }
            let length = Int(sqlite3_column_bytes(stmt, 0))
            result = Data(bytes: blob, count: length)
        }
        return result
    }

    func deleteKV(namespace: String, key: String) throws {
        let sql = "DELETE FROM kv WHERE namespace = ? AND key = ?;"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, namespace, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        }
    }

    func keysKV(namespace: String) throws -> [String] {
        let sql = "SELECT key FROM kv WHERE namespace = ?;"
        var keys: [String] = []
        try query(sql, bind: { stmt in
            sqlite3_bind_text(stmt, 1, namespace, -1, SQLITE_TRANSIENT)
        }) { stmt in
            if let cstr = sqlite3_column_text(stmt, 0) {
                keys.append(String(cString: cstr))
            }
        }
        return keys
    }

    func loadAllKV() throws -> [(namespace: String, key: String, value: Data)] {
        let sql = "SELECT namespace, key, value FROM kv;"
        var rows: [(namespace: String, key: String, value: Data)] = []
        try query(sql, bind: { _ in }) { stmt in
            let namespace = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let key = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let valueData: Data
            if let blob = sqlite3_column_blob(stmt, 2) {
                let length = Int(sqlite3_column_bytes(stmt, 2))
                valueData = Data(bytes: blob, count: length)
            } else {
                valueData = Data()
            }
            rows.append((namespace, key, valueData))
        }
        return rows
    }

    // MARK: - Deleted-event markers (NIP-09)

    func addDeletedEvent(_ id: String) throws {
        let sql = "INSERT OR IGNORE INTO deleted_events(event_id, deleted_at) VALUES (?, ?);"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
        }
    }

    func loadDeletedEvents() throws -> Set<String> {
        let sql = "SELECT event_id FROM deleted_events;"
        var ids: Set<String> = []
        try query(sql, bind: { _ in }) { stmt in
            if let cstr = sqlite3_column_text(stmt, 0) {
                ids.insert(String(cString: cstr))
            }
        }
        return ids
    }

    func clearDeletedEvents() throws {
        try execOrThrow("DELETE FROM deleted_events;")
    }

    // MARK: - Decrypted content cache

    func setDecrypted(key: String, content: String) throws {
        let sql = "INSERT OR REPLACE INTO decrypted_content(key, content, cached_at) VALUES (?, ?, ?);"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, content, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
        }
    }

    func getDecrypted(key: String) throws -> String? {
        let sql = "SELECT content FROM decrypted_content WHERE key = ?;"
        var result: String?
        try query(sql, bind: { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        }) { stmt in
            if let cstr = sqlite3_column_text(stmt, 0) {
                result = String(cString: cstr)
            }
        }
        return result
    }

    func deleteDecrypted(key: String) throws {
        try exec("DELETE FROM decrypted_content WHERE key = ?;") { stmt in
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        }
    }

    /// Truncate the decrypted-content table only. Used by
    /// NDKNostrDBCache.clearDecryptedContent - must NOT wipe other tables.
    func clearDecryptedContent() throws {
        try execOrThrow("DELETE FROM decrypted_content;")
    }

    func loadRecentDecrypted(limit: Int) throws -> [(key: String, content: String)] {
        let sql = "SELECT key, content FROM decrypted_content ORDER BY cached_at DESC LIMIT ?;"
        var rows: [(key: String, content: String)] = []
        try query(sql, bind: { stmt in
            sqlite3_bind_int(stmt, 1, Int32(limit))
        }) { stmt in
            let key = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let content = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            rows.append((key, content))
        }
        return rows
    }

    // MARK: - NIP-05 cache (JSON-encoded entries)

    func saveNIP05(identifier: String, entryJSON: Data) throws {
        let sql = "INSERT OR REPLACE INTO nip05_cache(identifier, entry_json, updated_at) VALUES (?, ?, ?);"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_TRANSIENT)
            if let jsonString = String(data: entryJSON, encoding: .utf8) {
                sqlite3_bind_text(stmt, 2, jsonString, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
        }
    }

    func loadAllNIP05() throws -> [(identifier: String, entryJSON: Data)] {
        let sql = "SELECT identifier, entry_json FROM nip05_cache;"
        var rows: [(identifier: String, entryJSON: Data)] = []
        try query(sql, bind: { _ in }) { stmt in
            let identifier = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let jsonString = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if let data = jsonString.data(using: .utf8) {
                rows.append((identifier, data))
            }
        }
        return rows
    }

    func deleteNIP05(identifier: String) throws {
        try exec("DELETE FROM nip05_cache WHERE identifier = ?;") { stmt in
            sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_TRANSIENT)
        }
    }

    // MARK: - Fetch times

    func setFetchTime(fingerprint: String, at date: Date) throws {
        let sql = "INSERT OR REPLACE INTO fetch_times(fingerprint, fetched_at) VALUES (?, ?);"
        try exec(sql) { stmt in
            sqlite3_bind_text(stmt, 1, fingerprint, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(date.timeIntervalSince1970))
        }
    }

    func loadAllFetchTimes() throws -> [(fingerprint: String, date: Date)] {
        let sql = "SELECT fingerprint, fetched_at FROM fetch_times;"
        var rows: [(fingerprint: String, date: Date)] = []
        try query(sql, bind: { _ in }) { stmt in
            let fp = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let ts = sqlite3_column_int64(stmt, 1)
            rows.append((fp, Date(timeIntervalSince1970: TimeInterval(ts))))
        }
        return rows
    }

    func clearFetchTimes() throws {
        try execOrThrow("DELETE FROM fetch_times;")
    }

    // MARK: - Maintenance

    func vacuum() throws {
        try execOrThrow("VACUUM;")
    }

    func clearAll() throws {
        try execOrThrow("""
        DELETE FROM kv;
        DELETE FROM deleted_events;
        DELETE FROM decrypted_content;
        DELETE FROM nip05_cache;
        DELETE FROM fetch_times;
        """)
    }

    // MARK: - Helpers

    private static func exec(_ sql: String, db: OpaquePointer?) -> Bool {
        guard let db else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let r = sqlite3_exec(db, sql, nil, nil, &err)
        if let err {
            NDKLogger.log(.warning, category: .cache, "SQLite exec failed: \(String(cString: err)) for `\(sql)`")
            sqlite3_free(err)
        }
        return r == SQLITE_OK
    }

    private static func execOrThrow(_ sql: String, db: OpaquePointer?) throws {
        guard let db else { throw Error.stepFailed(code: -1, message: "db handle nil") }
        var err: UnsafeMutablePointer<CChar>?
        let r = sqlite3_exec(db, sql, nil, nil, &err)
        if r != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "<no message>"
            if let err { sqlite3_free(err) }
            throw Error.stepFailed(code: r, message: message)
        }
        if let err { sqlite3_free(err) }
    }

    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let r = sqlite3_exec(db, sql, nil, nil, &err)
        if let err {
            NDKLogger.log(.warning, category: .cache, "SQLite exec failed: \(String(cString: err)) for `\(sql)`")
            sqlite3_free(err)
        }
        return r == SQLITE_OK
    }

    private func execOrThrow(_ sql: String) throws {
        guard let db else { throw Error.stepFailed(code: -1, message: "db handle nil") }
        var err: UnsafeMutablePointer<CChar>?
        let r = sqlite3_exec(db, sql, nil, nil, &err)
        if r != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "<no message>"
            if let err { sqlite3_free(err) }
            throw Error.stepFailed(code: r, message: message)
        }
        if let err { sqlite3_free(err) }
    }

    /// Run a parameterized non-row-returning statement.
    private func exec(_ sql: String, bind: (OpaquePointer?) -> Void) throws {
        guard let db else { throw Error.stepFailed(code: -1, message: "db handle nil") }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let prep = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK else {
            throw Error.prepareFailed(sql: sql, code: prep, message: String(cString: sqlite3_errmsg(db)))
        }
        bind(stmt)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE else {
            throw Error.stepFailed(code: step, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Run a parameterized SELECT, calling `row` for each result row.
    private func query(
        _ sql: String,
        bind: (OpaquePointer?) -> Void,
        row: (OpaquePointer?) -> Void
    ) throws {
        guard let db else { throw Error.stepFailed(code: -1, message: "db handle nil") }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let prep = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prep == SQLITE_OK else {
            throw Error.prepareFailed(sql: sql, code: prep, message: String(cString: sqlite3_errmsg(db)))
        }
        bind(stmt)
        while true {
            let r = sqlite3_step(stmt)
            if r == SQLITE_ROW {
                row(stmt)
            } else if r == SQLITE_DONE {
                break
            } else {
                throw Error.stepFailed(code: r, message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}

// SQLite's binding helpers need a destructor pointer for TEXT/BLOB values
// passed by transient pointer. `SQLITE_TRANSIENT` tells SQLite to copy the
// buffer before returning so the caller can free it immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
