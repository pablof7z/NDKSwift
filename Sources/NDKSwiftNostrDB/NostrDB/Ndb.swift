//
//  Ndb.swift
//  NostrDB
//
//  Created by William Casarin on 2023-08-25.
//

import Foundation
import NDKSwiftCore
import NostrDB

typealias NoteKey = UInt64
typealias ProfileKey = UInt64

// Stub for Damus Log
enum Log {
    enum LogCategory { case storage, ndb }
    static func error(_: String, for _: LogCategory, _: CVarArg...) {}
    static func debug(_: String, for _: LogCategory, _: CVarArg...) {}
    static func info(_: String, for _: LogCategory, _: CVarArg...) {}
}

enum NdbSearchOrder {
    case oldest_first
    case newest_first
}

// MARK: - NostrDB Statistics

/// Database index names for stats reporting
public enum NdbDatabase: Int, CaseIterable, Sendable {
    case note = 0
    case meta = 1
    case profile = 2
    case noteId = 3
    case profilePk = 4
    case ndbMeta = 5
    case profileSearch = 6
    case profileLastFetch = 7
    case noteKind = 8
    case noteText = 9
    case noteBlocks = 10
    case noteTags = 11
    case notePubkey = 12
    case notePubkeyKind = 13
    case noteRelayKind = 14
    case noteRelays = 15

    public var name: String {
        switch self {
        case .note: return "Notes"
        case .meta: return "Metadata"
        case .profile: return "Profiles"
        case .noteId: return "Note ID Index"
        case .profilePk: return "Profile PK Index"
        case .ndbMeta: return "NDB Meta"
        case .profileSearch: return "Profile Search"
        case .profileLastFetch: return "Profile Last Fetch"
        case .noteKind: return "Note Kind Index"
        case .noteText: return "Full-Text Index"
        case .noteBlocks: return "Note Blocks"
        case .noteTags: return "Note Tags Index"
        case .notePubkey: return "Note Pubkey Index"
        case .notePubkeyKind: return "Note Pubkey+Kind"
        case .noteRelayKind: return "Relay+Kind Index"
        case .noteRelays: return "Note Relays"
        }
    }
}

/// Common event kinds tracked by NostrDB stats
public enum NdbCommonKind: Int, CaseIterable, Sendable {
    case profile = 0
    case text = 1
    case contacts = 2
    case dm = 3
    case delete = 4
    case repost = 5
    case reaction = 6
    case zap = 7
    case zapRequest = 8
    case nwcRequest = 9
    case nwcResponse = 10
    case httpAuth = 11
    case list = 12
    case longform = 13
    case status = 14

    public var name: String {
        switch self {
        case .profile: return "Profile (0)"
        case .text: return "Text (1)"
        case .contacts: return "Contacts (3)"
        case .dm: return "DM (4)"
        case .delete: return "Delete (5)"
        case .repost: return "Repost (6)"
        case .reaction: return "Reaction (7)"
        case .zap: return "Zap (9735)"
        case .zapRequest: return "Zap Request (9734)"
        case .nwcRequest: return "NWC Request"
        case .nwcResponse: return "NWC Response"
        case .httpAuth: return "HTTP Auth"
        case .list: return "List (30000)"
        case .longform: return "Longform (30023)"
        case .status: return "Status (30315)"
        }
    }
}

/// Statistics counts for a single database or kind
public struct NdbStatCounts: Sendable {
    public let keySize: Int
    public let valueSize: Int
    public let count: Int

    public var totalSize: Int { keySize + valueSize }
}

/// Complete NostrDB statistics
public struct NdbStat: Sendable {
    /// Per-database statistics
    public let databases: [NdbDatabase: NdbStatCounts]
    /// Per-kind statistics for common event kinds
    public let commonKinds: [NdbCommonKind: NdbStatCounts]
    /// Statistics for all other (uncommon) kinds
    public let otherKinds: NdbStatCounts

    /// Total number of events across all kinds
    public var totalEvents: Int {
        let commonTotal = commonKinds.values.reduce(0) { $0 + $1.count }
        return commonTotal + otherKinds.count
    }

    /// Total storage size in bytes
    public var totalStorageSize: Int {
        databases.values.reduce(0) { $0 + $1.totalSize }
    }
}

enum DatabaseError: Error {
    case failed_open

    var errorDescription: String? {
        switch self {
        case .failed_open:
            return "Failed to open database"
        }
    }
}

/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - Underlying ndb pointer is thread-safe C library (LMDB)
/// - CallbackHandler actor protects subscription state and continuations
/// - Typical usage: singleton-style object created once then used read-only
/// - Mutable properties (generation, closed) are not hotly contended in normal usage
class Ndb: @unchecked Sendable {
    var ndb: ndb_t
    let path: String?
    let owns_db: Bool
    var generation: Int
    private var closed: Bool
    private var callbackHandler: Ndb.CallbackHandler

    private static let DEFAULT_WRITER_SCRATCH_SIZE: Int32 = 2_097_152 // 2mb scratch size for the writer thread, it should match with the one specified in nostrdb.c

    var is_closed: Bool {
        closed || ndb.ndb == nil
    }

    static func safemode() -> Ndb? {
        guard let path = db_path() ?? old_db_path else { return nil }

        // delete the database and start fresh
        if Self.db_files_exist(path: path) {
            let file_manager = FileManager.default
            for db_file in db_files {
                try? file_manager.removeItem(atPath: "\(path)/\(db_file)")
            }
        }

        guard let ndb = Ndb(path: path) else {
            return nil
        }

        return ndb
    }

    // NostrDB used to be stored on the app container's document directory
    private static var old_db_path: String? {
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.absoluteString else {
            return nil
        }
        return remove_file_prefix(path)
    }

    static func db_path(appGroupIdentifier: String? = nil) -> String? {
        // Use app group container if available, otherwise fall back to documents directory
        if let appGroup = appGroupIdentifier,
           let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        {
            return remove_file_prefix(containerURL.absoluteString)
        }
        // Fallback to documents directory
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.absoluteString else {
            return nil
        }
        return remove_file_prefix(path)
    }

    private static var db_files: [String] = ["data.mdb", "lock.mdb"]

    static var empty: Ndb {
        print("txn: NOSTRDB EMPTY")
        return Ndb(ndb: ndb_t(ndb: nil))
    }

    static func open(path: String? = nil, owns_db_file: Bool = true, callbackHandler: Ndb.CallbackHandler) -> ndb_t? {
        var ndb_p: OpaquePointer?

        let ingest_threads: Int32 = 4
        var mapsize = 1024 * 1024 * 1024 * 32

        // Determine the effective path to use
        let effectivePath: String
        if let customPath = path {
            // Use the custom path provided
            effectivePath = remove_file_prefix(customPath)
        } else {
            // Use default path - migrate if needed
            if owns_db_file {
                do {
                    try Self.migrate_db_location_if_needed()
                } catch {
                    Log.error("Error migrating NostrDB to new file container", for: .storage)
                }
            }

            guard let defaultPath = Self.db_path() else {
                return nil
            }

            // If caller doesn't own DB, files must already exist
            if !owns_db_file, !Self.db_files_exist(path: defaultPath) {
                return nil
            }

            effectivePath = defaultPath
        }

        let ok = effectivePath.withCString { testdir in
            var ok = false
            while !ok, mapsize > 1024 * 1024 * 700 {
                var cfg = ndb_config(flags: 0, ingester_threads: ingest_threads, writer_scratch_buffer_size: DEFAULT_WRITER_SCRATCH_SIZE, mapsize: mapsize, filter_context: nil, ingest_filter: nil, sub_cb_ctx: nil, sub_cb: nil)

                // Here we hook up the global callback function for subscription callbacks.
                // We do an "unretained" pass here because the lifetime of the callback handler is larger than the lifetime of the nostrdb monitor in the C code.
                // The NostrDB monitor that makes the callbacks should in theory _never_ outlive the callback handler.
                //
                // This means that:
                // - for as long as nostrdb is running, its parent Ndb instance will be alive, keeping the callback handler alive.
                // - when the Ndb instance is deinitialized — and the callback handler comes down with it — the `deinit` function will destroy the nostrdb monitor, preventing it from accessing freed memory.
                //
                // Therefore, we do not need to increase reference count to callbackHandler. The tightly coupled lifetimes will ensure that it is always alive when the ndb_monitor is alive.
                let ctx: UnsafeMutableRawPointer = Unmanaged.passUnretained(callbackHandler).toOpaque()
                ndb_config_set_subscription_callback(&cfg, subscription_callback, ctx)

                let res = ndb_init(&ndb_p, testdir, &cfg)
                ok = res != 0
                if !ok {
                    Log.error("ndb_init failed: %d, reducing mapsize from %d to %d", for: .storage, res, mapsize, mapsize / 2)
                    mapsize /= 2
                }
            }
            return ok
        }

        if !ok {
            return nil
        }

        let ndb_instance = ndb_t(ndb: ndb_p)
        Task { await callbackHandler.set(ndb: ndb_instance) }
        return ndb_instance
    }

    init?(path: String? = nil, owns_db_file: Bool = true) {
        let callbackHandler = Ndb.CallbackHandler()
        guard let db = Self.open(path: path, owns_db_file: owns_db_file, callbackHandler: callbackHandler) else {
            return nil
        }

        generation = 0
        self.path = path
        owns_db = owns_db_file
        ndb = db
        closed = false
        self.callbackHandler = callbackHandler
    }

    private static func migrate_db_location_if_needed() throws {
        guard let old_db_path, let db_path = db_path() else {
            throw Errors.cannot_find_db_path
        }

        let file_manager = FileManager.default

        let old_db_files_exist = Self.db_files_exist(path: old_db_path)
        let new_db_files_exist = Self.db_files_exist(path: db_path)

        // Migration rules:
        // 1. If DB files exist in the old path but not the new one, move files to the new path
        // 2. If files do not exist anywhere, do nothing (let new DB be initialized)
        // 3. If files exist in the new path, but not the old one, nothing needs to be done
        // 4. If files exist on both, do nothing.
        // Scenario 4 likely means that user has downgraded and re-upgraded.
        // Although it might make sense to get the most recent DB, it might lead to data loss.
        // If we leave both intact, it makes it easier to fix later, as no data loss would occur.
        if old_db_files_exist, !new_db_files_exist {
            Log.info("Migrating NostrDB to new file location…", for: .storage)
            do {
                try db_files.forEach { db_file in
                    let old_path = "\(old_db_path)/\(db_file)"
                    let new_path = "\(db_path)/\(db_file)"
                    try file_manager.moveItem(atPath: old_path, toPath: new_path)
                }
                Log.info("NostrDB files successfully migrated to the new location", for: .storage)
            } catch {
                throw Errors.db_file_migration_error
            }
        }
    }

    private static func db_files_exist(path: String) -> Bool {
        return db_files.allSatisfy { FileManager.default.fileExists(atPath: "\(path)/\($0)") }
    }

    init(ndb: ndb_t) {
        self.ndb = ndb
        generation = 0
        path = nil
        owns_db = true
        closed = false
        // This simple initialization will cause subscriptions not to be ever called. Probably fine because this initializer is used only for empty example ndb instances.
        callbackHandler = Ndb.CallbackHandler()
    }

    func close() {
        guard !is_closed else { return }
        closed = true
        print("txn: CLOSING NOSTRDB")
        ndb_destroy(ndb.ndb)
        generation += 1
        print("txn: NOSTRDB CLOSED")
    }

    func reopen() -> Bool {
        guard is_closed,
              let db = Self.open(path: path, owns_db_file: owns_db, callbackHandler: callbackHandler)
        else {
            return false
        }

        print("txn: NOSTRDB REOPENED (gen \(generation))")

        closed = false
        ndb = db
        return true
    }

    func lookup_blocks_by_key_with_txn(_ key: NoteKey, txn: RawNdbTxnAccessible) -> NdbBlockGroup.BlocksMetadata? {
        guard let blocks = ndb_get_blocks_by_key(ndb.ndb, &txn.txn, key) else {
            return nil
        }

        return NdbBlockGroup.BlocksMetadata(ptr: ndb_blocks_ptr(ptr: blocks))
    }

    func lookup_blocks_by_key(_ key: NoteKey) -> SafeNdbTxn<NdbBlockGroup.BlocksMetadata?>? {
        SafeNdbTxn<NdbBlockGroup.BlocksMetadata?>.new(on: self) { txn in
            lookup_blocks_by_key_with_txn(key, txn: txn)
        }
    }

    func lookup_note_by_key_with_txn<Y>(_ key: NoteKey, txn: NdbTxn<Y>) -> NdbNote? {
        var size = 0
        guard let note_p = ndb_get_note_by_key(&txn.txn, key, &size) else {
            return nil
        }
        let ptr = ndb_note_ptr(ptr: note_p)
        return NdbNote(note: ptr, size: size, owned: false, key: key)
    }

    func text_search(query: String, limit: Int = 128, order: NdbSearchOrder = .newest_first) -> [NoteKey] {
        guard let txn = NdbTxn(ndb: self) else { return [] }
        var results = ndb_text_search_results()
        let res = query.withCString { q in
            let order = order == .newest_first ? NDB_ORDER_DESCENDING : NDB_ORDER_ASCENDING
            var config = ndb_text_search_config(order: order, limit: Int32(limit))
            return ndb_text_search(&txn.txn, q, &results, &config)
        }

        if res == 0 {
            return []
        }

        var note_ids = [NoteKey]()
        for i in 0 ..< results.num_results {
            // seriously wtf
            switch i {
            case 0: note_ids.append(results.results.0.key.note_id)
            case 1: note_ids.append(results.results.1.key.note_id)
            case 2: note_ids.append(results.results.2.key.note_id)
            case 3: note_ids.append(results.results.3.key.note_id)
            case 4: note_ids.append(results.results.4.key.note_id)
            case 5: note_ids.append(results.results.5.key.note_id)
            case 6: note_ids.append(results.results.6.key.note_id)
            case 7: note_ids.append(results.results.7.key.note_id)
            case 8: note_ids.append(results.results.8.key.note_id)
            case 9: note_ids.append(results.results.9.key.note_id)
            case 10: note_ids.append(results.results.10.key.note_id)
            case 11: note_ids.append(results.results.11.key.note_id)
            case 12: note_ids.append(results.results.12.key.note_id)
            case 13: note_ids.append(results.results.13.key.note_id)
            case 14: note_ids.append(results.results.14.key.note_id)
            case 15: note_ids.append(results.results.15.key.note_id)
            case 16: note_ids.append(results.results.16.key.note_id)
            case 17: note_ids.append(results.results.17.key.note_id)
            case 18: note_ids.append(results.results.18.key.note_id)
            case 19: note_ids.append(results.results.19.key.note_id)
            case 20: note_ids.append(results.results.20.key.note_id)
            case 21: note_ids.append(results.results.21.key.note_id)
            case 22: note_ids.append(results.results.22.key.note_id)
            case 23: note_ids.append(results.results.23.key.note_id)
            case 24: note_ids.append(results.results.24.key.note_id)
            case 25: note_ids.append(results.results.25.key.note_id)
            case 26: note_ids.append(results.results.26.key.note_id)
            case 27: note_ids.append(results.results.27.key.note_id)
            case 28: note_ids.append(results.results.28.key.note_id)
            case 29: note_ids.append(results.results.29.key.note_id)
            case 30: note_ids.append(results.results.30.key.note_id)
            case 31: note_ids.append(results.results.31.key.note_id)
            case 32: note_ids.append(results.results.32.key.note_id)
            case 33: note_ids.append(results.results.33.key.note_id)
            case 34: note_ids.append(results.results.34.key.note_id)
            case 35: note_ids.append(results.results.35.key.note_id)
            case 36: note_ids.append(results.results.36.key.note_id)
            case 37: note_ids.append(results.results.37.key.note_id)
            case 38: note_ids.append(results.results.38.key.note_id)
            case 39: note_ids.append(results.results.39.key.note_id)
            case 40: note_ids.append(results.results.40.key.note_id)
            case 41: note_ids.append(results.results.41.key.note_id)
            case 42: note_ids.append(results.results.42.key.note_id)
            case 43: note_ids.append(results.results.43.key.note_id)
            case 44: note_ids.append(results.results.44.key.note_id)
            case 45: note_ids.append(results.results.45.key.note_id)
            case 46: note_ids.append(results.results.46.key.note_id)
            case 47: note_ids.append(results.results.47.key.note_id)
            case 48: note_ids.append(results.results.48.key.note_id)
            case 49: note_ids.append(results.results.49.key.note_id)
            case 50: note_ids.append(results.results.50.key.note_id)
            case 51: note_ids.append(results.results.51.key.note_id)
            case 52: note_ids.append(results.results.52.key.note_id)
            case 53: note_ids.append(results.results.53.key.note_id)
            case 54: note_ids.append(results.results.54.key.note_id)
            case 55: note_ids.append(results.results.55.key.note_id)
            case 56: note_ids.append(results.results.56.key.note_id)
            case 57: note_ids.append(results.results.57.key.note_id)
            case 58: note_ids.append(results.results.58.key.note_id)
            case 59: note_ids.append(results.results.59.key.note_id)
            case 60: note_ids.append(results.results.60.key.note_id)
            case 61: note_ids.append(results.results.61.key.note_id)
            case 62: note_ids.append(results.results.62.key.note_id)
            case 63: note_ids.append(results.results.63.key.note_id)
            case 64: note_ids.append(results.results.64.key.note_id)
            case 65: note_ids.append(results.results.65.key.note_id)
            case 66: note_ids.append(results.results.66.key.note_id)
            case 67: note_ids.append(results.results.67.key.note_id)
            case 68: note_ids.append(results.results.68.key.note_id)
            case 69: note_ids.append(results.results.69.key.note_id)
            case 70: note_ids.append(results.results.70.key.note_id)
            case 71: note_ids.append(results.results.71.key.note_id)
            case 72: note_ids.append(results.results.72.key.note_id)
            case 73: note_ids.append(results.results.73.key.note_id)
            case 74: note_ids.append(results.results.74.key.note_id)
            case 75: note_ids.append(results.results.75.key.note_id)
            case 76: note_ids.append(results.results.76.key.note_id)
            case 77: note_ids.append(results.results.77.key.note_id)
            case 78: note_ids.append(results.results.78.key.note_id)
            case 79: note_ids.append(results.results.79.key.note_id)
            case 80: note_ids.append(results.results.80.key.note_id)
            case 81: note_ids.append(results.results.81.key.note_id)
            case 82: note_ids.append(results.results.82.key.note_id)
            case 83: note_ids.append(results.results.83.key.note_id)
            case 84: note_ids.append(results.results.84.key.note_id)
            case 85: note_ids.append(results.results.85.key.note_id)
            case 86: note_ids.append(results.results.86.key.note_id)
            case 87: note_ids.append(results.results.87.key.note_id)
            case 88: note_ids.append(results.results.88.key.note_id)
            case 89: note_ids.append(results.results.89.key.note_id)
            case 90: note_ids.append(results.results.90.key.note_id)
            case 91: note_ids.append(results.results.91.key.note_id)
            case 92: note_ids.append(results.results.92.key.note_id)
            case 93: note_ids.append(results.results.93.key.note_id)
            case 94: note_ids.append(results.results.94.key.note_id)
            case 95: note_ids.append(results.results.95.key.note_id)
            case 96: note_ids.append(results.results.96.key.note_id)
            case 97: note_ids.append(results.results.97.key.note_id)
            case 98: note_ids.append(results.results.98.key.note_id)
            case 99: note_ids.append(results.results.99.key.note_id)
            case 100: note_ids.append(results.results.100.key.note_id)
            case 101: note_ids.append(results.results.101.key.note_id)
            case 102: note_ids.append(results.results.102.key.note_id)
            case 103: note_ids.append(results.results.103.key.note_id)
            case 104: note_ids.append(results.results.104.key.note_id)
            case 105: note_ids.append(results.results.105.key.note_id)
            case 106: note_ids.append(results.results.106.key.note_id)
            case 107: note_ids.append(results.results.107.key.note_id)
            case 108: note_ids.append(results.results.108.key.note_id)
            case 109: note_ids.append(results.results.109.key.note_id)
            case 110: note_ids.append(results.results.110.key.note_id)
            case 111: note_ids.append(results.results.111.key.note_id)
            case 112: note_ids.append(results.results.112.key.note_id)
            case 113: note_ids.append(results.results.113.key.note_id)
            case 114: note_ids.append(results.results.114.key.note_id)
            case 115: note_ids.append(results.results.115.key.note_id)
            case 116: note_ids.append(results.results.116.key.note_id)
            case 117: note_ids.append(results.results.117.key.note_id)
            case 118: note_ids.append(results.results.118.key.note_id)
            case 119: note_ids.append(results.results.119.key.note_id)
            case 120: note_ids.append(results.results.120.key.note_id)
            case 121: note_ids.append(results.results.121.key.note_id)
            case 122: note_ids.append(results.results.122.key.note_id)
            case 123: note_ids.append(results.results.123.key.note_id)
            case 124: note_ids.append(results.results.124.key.note_id)
            case 125: note_ids.append(results.results.125.key.note_id)
            case 126: note_ids.append(results.results.126.key.note_id)
            case 127: note_ids.append(results.results.127.key.note_id)
            default:
                break
            }
        }

        return note_ids
    }

    // MARK: - Query API

    /// Execute a nostrdb query using filters and return matching note keys
    /// - Parameters:
    ///   - filters: Array of NdbFilter to query with
    ///   - maxResults: Maximum number of results to return (default: 500)
    /// - Returns: Array of NoteKey references for matching events
    /// - Throws: NdbStreamError if transaction or query fails
    func query(filters: [NdbFilter], maxResults: Int = 500) throws -> [NoteKey] {
        guard let txn = NdbTxn<Void>(ndb: self) else {
            throw NdbStreamError.ndbClosed
        }

        return try query(with: txn, filters: filters, maxResults: maxResults)
    }

    func lookup_note_by_key(_ key: NoteKey) -> NdbTxn<NdbNote?>? {
        return NdbTxn(ndb: self) { txn in
            lookup_note_by_key_with_txn(key, txn: txn)
        }
    }

    private func lookup_profile_by_key_inner<Y>(_ key: ProfileKey, txn: NdbTxn<Y>) -> NdbCachedProfile? {
        var size = 0
        guard let profile_p = ndb_get_profile_by_key(&txn.txn, key, &size) else {
            return nil
        }

        return profile_flatbuf_to_record(ptr: profile_p, size: size, key: key)
    }

    private func profile_flatbuf_to_record(ptr: UnsafeMutableRawPointer, size: Int, key _: UInt64) -> NdbCachedProfile? {
        do {
            var buf = ByteBuffer(assumingMemoryBound: ptr, capacity: size)
            let rec: NdbProfile = try getDebugCheckedRoot(byteBuffer: &buf)
            return NdbCachedProfile(profile: rec, lastFetch: Date(), receivedAt: Date())
        } catch {
            // Handle error appropriately
            print("UNUSUAL: \(error)")
            return nil
        }
    }

    private func lookup_note_with_txn_inner<Y>(id: NdbNoteId, txn: NdbTxn<Y>) -> NdbNote? {
        return id.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NdbNote? in
            var key: UInt64 = 0
            var size = 0
            guard let baseAddress = ptr.baseAddress,
                  let note_p = ndb_get_note_by_id(&txn.txn, baseAddress, &size, &key)
            else {
                return nil
            }
            let ptr = ndb_note_ptr(ptr: note_p)
            return NdbNote(note: ptr, size: size, owned: false, key: key)
        }
    }

    private func lookup_profile_with_txn_inner<Y>(pubkey: NdbPubkey, txn: NdbTxn<Y>) -> NdbCachedProfile? {
        return pubkey.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NdbCachedProfile? in
            var size = 0
            var key: UInt64 = 0

            guard let baseAddress = ptr.baseAddress,
                  let profile_p = ndb_get_profile_by_pubkey(&txn.txn, baseAddress, &size, &key)
            else {
                return nil
            }

            return profile_flatbuf_to_record(ptr: profile_p, size: size, key: key)
        }
    }

    func lookup_profile_by_key_with_txn<Y>(key: ProfileKey, txn: NdbTxn<Y>) -> NdbCachedProfile? {
        lookup_profile_by_key_inner(key, txn: txn)
    }

    func lookup_profile_by_key(key: ProfileKey) -> NdbTxn<NdbCachedProfile?>? {
        return NdbTxn(ndb: self) { txn in
            lookup_profile_by_key_inner(key, txn: txn)
        }
    }

    func lookup_note_with_txn<Y>(id: NdbNoteId, txn: NdbTxn<Y>) -> NdbNote? {
        lookup_note_with_txn_inner(id: id, txn: txn)
    }

    func lookup_profile_key(_ pubkey: Pubkey) -> ProfileKey? {
        guard let txn = NdbTxn(ndb: self, with: { txn in
            lookup_profile_key_with_txn(pubkey, txn: txn)
        }) else {
            return nil
        }

        return txn.value
    }

    func lookup_profile_key_with_txn<Y>(_ pubkey: Pubkey, txn: NdbTxn<Y>) -> ProfileKey? {
        return pubkey.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NoteKey? in
            guard let p = ptr.baseAddress else { return nil }
            let r = ndb_get_profilekey_by_pubkey(&txn.txn, p)
            if r == 0 {
                return nil
            }
            return r
        }
    }

    func lookup_note_key_with_txn(_ id: NdbNoteId, txn: some RawNdbTxnAccessible) -> NoteKey? {
        guard !closed else { return nil }
        return id.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> NoteKey? in
            guard let p = ptr.baseAddress else {
                return nil
            }
            let r = ndb_get_notekey_by_id(&txn.txn, p)
            if r == 0 {
                return nil
            }
            return r
        }
    }

    func lookup_note_key(_ id: NdbNoteId) -> NoteKey? {
        guard let txn = NdbTxn(ndb: self, with: { txn in
            lookup_note_key_with_txn(id, txn: txn)
        }) else {
            return nil
        }

        return txn.value
    }

    func lookup_note(_ id: NdbNoteId, txn_name: String? = nil) -> NdbTxn<NdbNote?>? {
        NdbTxn(ndb: self, with: { txn in
            lookup_note_with_txn_inner(id: id, txn: txn)
        }, name: txn_name)
    }

    func lookup_profile(_ pubkey: NdbPubkey, txn_name: String? = nil) -> NdbTxn<NdbCachedProfile?>? {
        NdbTxn(ndb: self, with: { txn in
            lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
        }, name: txn_name)
    }

    func lookup_profile_with_txn<Y>(_ pubkey: NdbPubkey, txn: NdbTxn<Y>) -> NdbCachedProfile? {
        lookup_profile_with_txn_inner(pubkey: pubkey, txn: txn)
    }

    func process_client_event(_ str: String) -> Bool {
        guard !is_closed else { return false }
        return str.withCString { cstr in
            ndb_process_client_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
        }
    }

    func write_profile_last_fetched(pubkey: Pubkey, fetched_at: UInt64) {
        guard !closed else { return }
        pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let p = ptr.baseAddress else { return }
            ndb_write_last_profile_fetch(ndb.ndb, p, fetched_at)
        }
    }

    func read_profile_last_fetched<Y>(txn: NdbTxn<Y>, pubkey: Pubkey) -> UInt64? {
        guard !closed else { return nil }
        return pubkey.id.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt64? in
            guard let p = ptr.baseAddress else { return nil }
            let res = ndb_read_last_profile_fetch(&txn.txn, p)
            if res == 0 {
                return nil
            }

            return res
        }
    }

    func process_event(_ str: String, originRelayURL: String? = nil) -> Bool {
        guard !is_closed else { return false }
        guard let originRelayURL else {
            return str.withCString { cstr in
                ndb_process_event(ndb.ndb, cstr, Int32(str.utf8.count)) != 0
            }
        }
        return str.withCString { cstr in
            originRelayURL.withCString { originRelayCString in
                let meta = UnsafeMutablePointer<ndb_ingest_meta>.allocate(capacity: 1)
                defer { meta.deallocate() }
                ndb_ingest_meta_init(meta, 0, originRelayCString)
                return ndb_process_event_with(ndb.ndb, cstr, Int32(str.utf8.count), meta) != 0
            }
        }
    }

    func process_events(_ str: String) -> Bool {
        guard !is_closed else { return false }
        return str.withCString { cstr in
            ndb_process_events(ndb.ndb, cstr, str.utf8.count) != 0
        }
    }

    // MARK: - Statistics

    /// Get comprehensive statistics about the NostrDB database
    /// - Returns: NdbStat containing per-database and per-kind statistics, or nil if stats cannot be retrieved
    func stat() -> NdbStat? {
        guard !is_closed else { return nil }

        var cStat = ndb_stat()
        let result = ndb_stat(ndb.ndb, &cStat)
        guard result == 1 else { return nil }

        // Convert C struct to Swift types
        var databases: [NdbDatabase: NdbStatCounts] = [:]
        for db in NdbDatabase.allCases {
            let dbIndex = db.rawValue
            // Access the tuple elements using withUnsafePointer
            let counts = withUnsafePointer(to: &cStat.dbs) { ptr -> ndb_stat_counts in
                ptr.withMemoryRebound(to: ndb_stat_counts.self, capacity: 16) { arrayPtr in
                    arrayPtr[dbIndex]
                }
            }
            databases[db] = NdbStatCounts(
                keySize: counts.key_size,
                valueSize: counts.value_size,
                count: counts.count
            )
        }

        var commonKinds: [NdbCommonKind: NdbStatCounts] = [:]
        for kind in NdbCommonKind.allCases {
            let kindIndex = kind.rawValue
            let counts = withUnsafePointer(to: &cStat.common_kinds) { ptr -> ndb_stat_counts in
                ptr.withMemoryRebound(to: ndb_stat_counts.self, capacity: 15) { arrayPtr in
                    arrayPtr[kindIndex]
                }
            }
            commonKinds[kind] = NdbStatCounts(
                keySize: counts.key_size,
                valueSize: counts.value_size,
                count: counts.count
            )
        }

        let otherKinds = NdbStatCounts(
            keySize: cStat.other_kinds.key_size,
            valueSize: cStat.other_kinds.value_size,
            count: cStat.other_kinds.count
        )

        return NdbStat(
            databases: databases,
            commonKinds: commonKinds,
            otherKinds: otherKinds
        )
    }

    func search_profile<Y>(_ search: String, limit: Int, txn: NdbTxn<Y>) -> [Pubkey] {
        var pks = [Pubkey]()

        return search.withCString { q in
            var s = ndb_search()
            guard ndb_search_profile(&txn.txn, &s, q) != 0 else {
                return pks
            }

            defer { ndb_search_profile_end(&s) }
            pks.append(Pubkey(Data(bytes: &s.key.pointee.id.0, count: 32)))

            var n = limit
            while n > 0 {
                guard ndb_search_profile_next(&s) != 0 else {
                    return pks
                }
                pks.append(Pubkey(Data(bytes: &s.key.pointee.id.0, count: 32)))

                n -= 1
            }

            return pks
        }
    }

    // MARK: NdbFilter queries and subscriptions

    /// Safe wrapper around the `ndb_query` C function
    /// - Parameters:
    ///   - txn: Database transaction
    ///   - filters: Array of NdbFilter objects
    ///   - maxResults: Maximum number of results to return
    /// - Returns: Array of note keys matching the filters
    /// - Throws: NdbStreamError if the query fails
    func query<Y>(with txn: NdbTxn<Y>, filters: [NdbFilter], maxResults: Int) throws(NdbStreamError) -> [NoteKey] {
        guard !is_closed else { throw .ndbClosed }
        let filtersPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: filters.count)
        defer { filtersPointer.deallocate() }

        for (index, ndbFilter) in filters.enumerated() {
            filtersPointer.advanced(by: index).pointee = ndbFilter.ndbFilter
        }

        let count = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        defer { count.deallocate() }

        let results = UnsafeMutablePointer<ndb_query_result>.allocate(capacity: maxResults)
        defer { results.deallocate() }

        guard !is_closed else { throw .ndbClosed }
        guard ndb_query(&txn.txn, filtersPointer, Int32(filters.count), results, Int32(maxResults), count) == 1 else {
            throw NdbStreamError.initialQueryFailed
        }

        var noteIds: [NoteKey] = []
        for i in 0 ..< count.pointee {
            noteIds.append(results.advanced(by: Int(i)).pointee.note_id)
        }

        return noteIds
    }

    /// Actor to manage subscription state for concurrent access
    private actor SubscriptionState {
        var streaming: Bool = true
        var terminationStarted: Bool = false
        var subid: UInt64 = 0
        var filtersPointer: UnsafeMutablePointer<ndb_filter>?

        func setSubid(_ id: UInt64) {
            subid = id
        }

        func setFiltersPointer(_ pointer: UnsafeMutablePointer<ndb_filter>) {
            filtersPointer = pointer
        }

        func markTerminated() -> Bool {
            if terminationStarted {
                return false // Already terminated
            }
            terminationStarted = true
            streaming = false
            return true // First termination
        }

        func getSubid() -> UInt64 {
            return subid
        }

        func deallocateFilters() {
            if let pointer = filtersPointer {
                pointer.deallocate()
                filtersPointer = nil
            }
        }
    }

    /// Safe wrapper around `ndb_subscribe` that handles all pointer management
    /// - Parameters:
    ///   - filters: Array of NdbFilter objects
    /// - Returns: AsyncStream of NoteKey events for new matches only
    private func ndbSubscribe(filters: [NdbFilter]) -> AsyncStream<NoteKey> {
        return AsyncStream<NoteKey> { continuation in
            // Allocate filters pointer - will be deallocated when subscription ends
            // Cannot use `defer` to deallocate `filtersPointer` because it needs to remain valid for the lifetime of the subscription, which extends beyond this block's scope.
            let filtersPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: filters.count)
            for (index, ndbFilter) in filters.enumerated() {
                filtersPointer.advanced(by: index).pointee = ndbFilter.ndbFilter
            }

            let state = SubscriptionState()

            // Store the pointer in the actor to avoid capturing non-Sendable type in @Sendable closure
            Task {
                await state.setFiltersPointer(filtersPointer)
            }

            // Set up termination handler
            continuation.onTermination = { @Sendable _ in
                Task {
                    guard await state.markTerminated() else { return }
                    Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
                    let currentSubid = await state.getSubid()
                    if currentSubid != 0 {
                        ndb_unsubscribe(self.ndb.ndb, currentSubid)
                        await self.unsetContinuation(subscriptionId: currentSubid)
                    }
                    await state.deallocateFilters()
                }
            }

            Task {
                if !(await state.streaming) {
                    return
                }

                // Set up subscription
                let newSubid = ndb_subscribe(self.ndb.ndb, filtersPointer, Int32(filters.count))
                await state.setSubid(newSubid)

                // We are setting the continuation after issuing the subscription call.
                // This won't cause lost notes because if any notes get issued before registering
                // the continuation they will get queued by `Ndb.CallbackHandler`
                let continuationSetupTask = Task {
                    let currentSubid = await state.getSubid()
                    await self.setContinuation(for: currentSubid, continuation: continuation)
                }

                // Update termination handler to include subscription cleanup
                continuation.onTermination = { @Sendable _ in
                    Task {
                        guard await state.markTerminated() else { return }
                        Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
                        continuationSetupTask.cancel()
                        let currentSubid = await state.getSubid()
                        await self.unsetContinuation(subscriptionId: currentSubid)
                        await state.deallocateFilters()
                        guard !self.is_closed else { return }
                        ndb_unsubscribe(self.ndb.ndb, currentSubid)
                    }
                }
            }
        }
    }

    func subscribe(filters: [NdbFilter], maxSimultaneousResults: Int = 1000) throws(NdbStreamError) -> AsyncStream<StreamItem> {
        guard !is_closed else { throw .ndbClosed }

        do { try Task.checkCancellation() } catch { throw .cancelled }

        // CRITICAL: Create the subscription FIRST before querying to avoid race condition
        // This ensures that any events indexed after subscription but before query won't be missed
        let newEventsStream = ndbSubscribe(filters: filters)

        // Now fetch initial results after subscription is registered
        guard let txn = NdbTxn(ndb: self) else { throw .cannotOpenTransaction }

        // Use our safe wrapper instead of direct C function call
        let noteIds = try query(with: txn, filters: filters, maxResults: maxSimultaneousResults)

        do { try Task.checkCancellation() } catch { throw .cancelled }

        // Create a cascading stream that combines initial results with new events
        return AsyncStream<StreamItem> { continuation in
            // Stream all results already present in the database
            for noteId in noteIds {
                if Task.isCancelled { return }
                continuation.yield(.event(noteId))
            }

            // Indicate this is the end of the results currently present in the database
            continuation.yield(.eose)

            // Create a task to forward events from the subscription stream
            let forwardingTask = Task {
                for await noteKey in newEventsStream {
                    if Task.isCancelled { break }
                    continuation.yield(.event(noteKey))
                }
                continuation.finish()
            }

            // Handle termination by canceling the forwarding task
            continuation.onTermination = { @Sendable _ in
                forwardingTask.cancel()
            }
        }
    }

    /// Determines if a given note was seen on a specific relay URL
    func was(noteKey: NoteKey, seenOn relayUrl: String, txn: SafeNdbTxn<Void>? = nil) throws -> Bool {
        guard let txn = txn ?? SafeNdbTxn.new(on: self) else { throw NdbLookupError.cannotOpenTransaction }
        return relayUrl.withCString { relayCString in
            ndb_note_seen_on_relay(&txn.txn, noteKey, relayCString) == 1
        }
    }

    /// Determines if a given note was seen on any of the listed relay URLs
    func was(noteKey: NoteKey, seenOnAnyOf relayURLs: [String], txn: SafeNdbTxn<Void>? = nil) throws -> Bool {
        guard let txn = txn ?? SafeNdbTxn.new(on: self) else { throw NdbLookupError.cannotOpenTransaction }
        for relayUrl in relayURLs {
            if try was(noteKey: noteKey, seenOn: relayUrl, txn: txn) {
                return true
            }
        }
        return false
    }

    // MARK: Internal ndb callback interfaces

    func setContinuation(for subscriptionId: UInt64, continuation: AsyncStream<NoteKey>.Continuation) async {
        await callbackHandler.set(continuation: continuation, for: subscriptionId)
    }

    func unsetContinuation(subscriptionId: UInt64) async {
        await callbackHandler.unset(subid: subscriptionId)
    }

    // MARK: Helpers

    enum Errors: Error {
        case cannot_find_db_path
        case db_file_migration_error
    }

    // MARK: Deinitialization

    deinit {
        print("txn: Ndb de-init")
        self.close()
    }
}

// MARK: - Extensions and helper structures and functions

extension Ndb {
    /// A class that is used to handle callbacks from nostrdb
    ///
    /// This is a separate class from `Ndb` because it simplifies the initialization logic
    actor CallbackHandler {
        /// Holds the ndb instance in the C codebase. Should be shared with `Ndb`
        var ndb: ndb_t?
        /// A map from nostrdb subscription ids to stream continuations, which allows publishing note keys to active listeners
        var subscriptionContinuationMap: [UInt64: AsyncStream<NoteKey>.Continuation] = [:]
        /// A map from nostrdb subscription ids to queued note keys (for when there are no active listeners)
        var subscriptionQueueMap: [UInt64: [NoteKey]] = [:]
        /// Maximum number of items to queue per subscription when no one is listening
        let maxQueueItemsPerSubscription: Int = 2000

        func set(continuation: AsyncStream<NoteKey>.Continuation, for subid: UInt64) {
            // Flush any queued items to the new continuation
            if let queuedItems = subscriptionQueueMap[subid] {
                for noteKey in queuedItems {
                    continuation.yield(noteKey)
                }
                subscriptionQueueMap[subid] = nil
            }

            subscriptionContinuationMap[subid] = continuation
        }

        func unset(subid: UInt64) {
            subscriptionContinuationMap[subid] = nil
            subscriptionQueueMap[subid] = nil
        }

        func set(ndb: ndb_t?) {
            self.ndb = ndb
        }

        /// Handles callbacks from nostrdb subscriptions, and routes them to the correct continuation or queue
        func handleSubscriptionCallback(subId: UInt64, maxCapacity: Int32 = 1000) {
            let result = UnsafeMutablePointer<UInt64>.allocate(capacity: Int(maxCapacity))
            defer { result.deallocate() } // Ensure we deallocate memory before leaving the function to avoid memory leaks

            guard let ndb else { return }

            let numberOfNotes = ndb_poll_for_notes(ndb.ndb, subId, result, maxCapacity)

            for i in 0 ..< numberOfNotes {
                let noteKey = result.advanced(by: Int(i)).pointee

                if let continuation = subscriptionContinuationMap[subId] {
                    // Send directly to the active listener stream
                    continuation.yield(noteKey)
                } else {
                    // No one is listening, queue it for later
                    var queue = subscriptionQueueMap[subId] ?? []

                    // Ensure queue stays within the desired size
                    while queue.count >= maxQueueItemsPerSubscription {
                        queue.removeFirst()
                    }

                    queue.append(noteKey)
                    subscriptionQueueMap[subId] = queue
                }
            }
        }
    }

    /// An item that comes out of a subscription stream
    enum StreamItem {
        /// End of currently stored events
        case eose
        /// An event in NostrDB available at the given note key
        case event(NoteKey)
    }

    /// An error that may happen during nostrdb streaming
    enum NdbStreamError: Error {
        case cannotOpenTransaction
        case cannotConvertFilter(any Error)
        case initialQueryFailed
        case timeout
        case cancelled
        case ndbClosed
    }

    /// An error that may happen when looking something up
    enum NdbLookupError: Error {
        case cannotOpenTransaction
        case streamError(NdbStreamError)
        case internalInconsistency
        case timeout
        case notFound
    }

    enum OperationError: Error {
        case genericError
    }
}

/// This callback "trampoline" function will be called when new notes arrive for NostrDB subscriptions.
///
/// This is needed as a separate global function in order to allow us to pass it to the C code as a callback (We can't pass native Swift fuctions directly as callbacks).
///
/// - Parameters:
///   - ctx: A pointer to a context object setup during initialization. This allows this function to "find" the correct place to call. MUST be a pointer to a `CallbackHandler`, otherwise this will trigger a crash
///   - subid: The NostrDB subscription ID, which identifies the subscription that is being called back
@_cdecl("subscription_callback")
public func subscription_callback(ctx: UnsafeMutableRawPointer?, subid: UInt64) {
    guard let ctx else { return }
    let handler = Unmanaged<Ndb.CallbackHandler>.fromOpaque(ctx).takeUnretainedValue()
    Task {
        await handler.handleSubscriptionCallback(subId: subid)
    }
}

#if DEBUG
    func getDebugCheckedRoot<T: FlatBufferObject>(byteBuffer: inout ByteBuffer) throws -> T {
        return getRoot(byteBuffer: &byteBuffer)
    }
#else
    func getDebugCheckedRoot<T: FlatBufferObject>(byteBuffer: inout ByteBuffer) throws -> T {
        return getRoot(byteBuffer: &byteBuffer)
    }
#endif

func remove_file_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "file://", with: "")
}
