//
//  NdbNote.swift
//  NostrDB
//
//  Created by William Casarin on 2023-07-21.
//

import CommonCrypto
import CryptoKit
import Foundation
import NaturalLanguage

import NostrDB

// Stub types for Damus dependencies - will be replaced by NDK layer
// These are internal to avoid conflicts with NDKSwift types
struct NdbPubkey: Equatable, Hashable, Codable {
    let data: Data
    init(_ data: Data) { self.data = data }

    var id: Data { data }
    var bytes: [UInt8] { [UInt8](data) }

    func withUnsafePointer<T>(_ body: (UnsafeRawPointer) throws -> T) rethrows -> T {
        try data.withUnsafeBytes { try body($0.baseAddress!) }
    }
}

struct NdbNoteId: Equatable, Hashable, Codable {
    let data: Data
    init(_ data: Data) { self.data = data }

    var id: Data { data }

    func withUnsafePointer<T>(_ body: (UnsafeRawPointer) throws -> T) rethrows -> T {
        try data.withUnsafeBytes { try body($0.baseAddress!) }
    }
}

struct NdbSignature: Codable {
    let data: Data
    init(_ data: Data) { self.data = data }
}

// NdbProfileRecord is defined in NdbProfile.swift as a FlatBuffer type
// We'll use a different name for our wrapper to avoid conflicts
struct NdbCachedProfile {
    let profile: NdbProfile
    let lastFetch: Date
    let receivedAt: Date
}

struct NdbKeypair {
    let pubkey: NdbPubkey
    let privkey: NdbPrivkey?
}

struct NdbPrivkey {
    let id: Data
    var bytes: [UInt8] { Array(id) }
}

struct NostrKind: Equatable {
    let rawValue: UInt32
    static let text = NostrKind(rawValue: 1)
    static let chat = NostrKind(rawValue: 42)
    static let longform = NostrKind(rawValue: 30023)
    static let highlight = NostrKind(rawValue: 9802)
    static let live = NostrKind(rawValue: 30311)
    static let live_chat = NostrKind(rawValue: 1311)
    static let dm = NostrKind(rawValue: 4)
    static let boost = NostrKind(rawValue: 6)
    static let like = NostrKind(rawValue: 7)
    static let zap = NostrKind(rawValue: 9735)
    init?(rawValue: UInt32) { self.rawValue = rawValue }
}

struct NdbInvoice {
    let description: NdbInvoiceDescription
    let amount: NdbAmount
}

struct NdbInvoiceDescription {
    let description: String
}

struct NdbAmount {
    let amount: UInt64
}

// Typealiases for backward compatibility within NostrDB files
// Note: Signature is NOT aliased to avoid conflicts with NDKSwift's Signature type
typealias Pubkey = NdbPubkey
typealias NoteId = NdbNoteId
typealias ProfileRecord = NdbCachedProfile
typealias Keypair = NdbKeypair
typealias Privkey = NdbPrivkey
typealias Invoice = NdbInvoice
typealias InvoiceDescription = NdbInvoiceDescription
typealias Amount = NdbAmount
struct ThreadReply {
    let reply: ReplyRef
    let root: ReplyRef?
    init?(tags _: TagsSequence) { return nil }
}

struct ReplyRef {
    let note_id: NoteId
}

/// Protocol for types that can be extracted from nostr event tags
protocol TagConvertible {
    static func from_tag(tag: TagSequence) -> Self?
}

struct References<T: TagConvertible>: Sequence, IteratorProtocol {
    let tags: TagsSequence
    var tags_iter: TagsIterator

    init(tags: TagsSequence) {
        self.tags = tags
        tags_iter = tags.makeIterator()
    }

    mutating func next() -> T? {
        while let tag = tags_iter.next() {
            guard let evref = T.from_tag(tag: tag) else { continue }
            return evref
        }
        return nil
    }
}

extension References {
    var first: T? {
        let copy = self
        return copy.first(where: { _ in true })
    }

    var last: T? {
        var copy = self
        var last: T?
        while let t = copy.next() {
            last = t
        }
        return last
    }
}

// TagConvertible conformance for Pubkey - matches "p" tags
extension NdbPubkey: TagConvertible {
    static func from_tag(tag: TagSequence) -> NdbPubkey? {
        var i = tag.makeIterator()
        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == AsciiCharacter("p"),
              let t1 = i.next(),
              let id = t1.id()
        else { return nil }
        return NdbPubkey(id)
    }
}

// TagConvertible conformance for NoteId - matches "e" tags
extension NdbNoteId: TagConvertible {
    static func from_tag(tag: TagSequence) -> NdbNoteId? {
        var i = tag.makeIterator()
        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == AsciiCharacter("e"),
              let t1 = i.next(),
              let id = t1.id()
        else { return nil }
        return NdbNoteId(id)
    }
}

struct QuoteId: TagConvertible {
    let id: Data
    var note_id: NoteId { NoteId(id) }

    static func from_tag(tag: TagSequence) -> QuoteId? {
        var i = tag.makeIterator()
        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == AsciiCharacter("q"),
              let t1 = i.next(),
              let id = t1.id()
        else { return nil }
        return QuoteId(id: id)
    }
}

struct NoteRef: TagConvertible {
    static func from_tag(tag _: TagSequence) -> NoteRef? { nil }
}

struct FollowRef: TagConvertible {
    static func from_tag(tag _: TagSequence) -> FollowRef? { nil }
}

struct Hashtag: TagConvertible {
    static func from_tag(tag _: TagSequence) -> Hashtag? { nil }
}

struct ReplaceableParam: TagConvertible {
    static func from_tag(tag _: TagSequence) -> ReplaceableParam? { nil }
}

struct MuteItem: TagConvertible {
    static func from_tag(tag _: TagSequence) -> MuteItem? { nil }
}

struct RefId: TagConvertible {
    static func from_tag(tag _: TagSequence) -> RefId? { nil }
}

struct CommentItemRef: TagConvertible {
    let content: String
    static func from_tag(tag _: TagSequence) -> CommentItemRef? { nil }
}

enum DmEncoding {
    case base64
    case utf8
}

func decrypt_dm(_: Privkey?, pubkey _: Pubkey, content _: String, encoding _: DmEncoding) -> String? {
    return nil
}

func hexchar(_ val: UInt8) -> UInt8 {
    if val < 10 {
        return 48 + val // '0' + val
    } else {
        return 97 + val - 10 // 'a' + (val - 10)
    }
}

func hex_decode(_ str: String) -> [UInt8]? {
    guard str.count % 2 == 0 else { return nil }
    var bytes: [UInt8] = []
    var index = str.startIndex
    while index < str.endIndex {
        let nextIndex = str.index(index, offsetBy: 2)
        let byteString = String(str[index ..< nextIndex])
        guard let byte = UInt8(byteString, radix: 16) else { return nil }
        bytes.append(byte)
        index = nextIndex
    }
    return bytes
}

func localeToLanguage(_ locale: String) -> String {
    return locale
}

extension Data {
    var byteArray: [UInt8] {
        return [UInt8](self)
    }
}

// Stub secp256k1 constants - will be replaced by NDK layer
let SECP256K1_CONTEXT_VERIFY: UInt32 = 0x0101

let MAX_NOTE_SIZE: Int = 2 << 18

// Default threshold of the hellthread pubkey tag count setting if it is not set.
let DEFAULT_HELLTHREAD_MAX_PUBKEYS: Int = 10

struct NdbStr {
    let note: NdbNote
    let str: UnsafePointer<CChar>
}

struct NdbId {
    let note: NdbNote
    let id: Data
}

enum NdbData {
    case id(NdbId)
    case str(NdbStr)

    init(note: NdbNote, str: ndb_str) {
        guard str.flag == NDB_PACKED_ID else {
            self = .str(NdbStr(note: note, str: str.str))
            return
        }

        let buffer = UnsafeBufferPointer(start: str.id, count: 32)
        self = .id(NdbId(note: note, id: Data(buffer: buffer)))
    }
}

/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - Wraps immutable note data from C library
/// - All read operations are safe across isolation boundaries
/// - Internal mutable state (owned flag) is not exposed or contended
class NdbNote: Codable, Equatable, Hashable, @unchecked Sendable {
    // we can have owned notes, but we can also have lmdb virtual-memory mapped notes so its optional
    private(set) var owned: Bool
    let count: Int
    let key: NoteKey?
    let note: ndb_note_ptr

    private var inner_event: NdbNote? {
        return NdbNote.owned_from_json_cstr(json: content_raw, json_len: content_len)
    }

    init(note: ndb_note_ptr, size: Int, owned: Bool, key: NoteKey?) {
        self.note = note
        self.owned = owned
        count = size
        self.key = key

        #if DEBUG_NOTE_SIZE
            if let owned_size {
                NdbNote.total_ndb_size += Int(owned_size)
                NdbNote.notes_created += 1

                print("\(NdbNote.notes_created) ndb_notes, \(NdbNote.total_ndb_size) bytes")
            }
        #endif
    }

    func to_owned() -> NdbNote {
        if owned {
            return self
        }

        let buf = malloc(count)!
        memcpy(buf, UnsafeRawPointer(note.ptr), count)

        let new_note = ndb_note_ptr(ptr: OpaquePointer(buf))
        return NdbNote(note: new_note, size: count, owned: true, key: key)
    }

    func mark_ownership_moved() {
        owned = false
    }

    var content: String {
        String(cString: content_raw, encoding: .utf8) ?? ""
    }

    var content_raw: UnsafePointer<CChar> {
        ndb_note_content(note.ptr)
    }

    var content_len: UInt32 {
        ndb_note_content_length(note.ptr)
    }

    var id: NoteId {
        .init(Data(bytes: ndb_note_id(note.ptr), count: 32))
    }

    var raw_note_id: UnsafeMutablePointer<UInt8> {
        ndb_note_id(note.ptr)
    }

    func id_matches(other: NdbNote) -> Bool {
        memcmp(raw_note_id, other.raw_note_id, 32) == 0
    }

    var sig: NdbSignature {
        .init(Data(bytes: ndb_note_sig(note.ptr), count: 64))
    }

    var pubkey: Pubkey {
        .init(Data(bytes: ndb_note_pubkey(note.ptr), count: 32))
    }

    var created_at: UInt32 {
        ndb_note_created_at(note.ptr)
    }

    var kind: UInt32 {
        ndb_note_kind(note.ptr)
    }

    var tags: TagsSequence {
        .init(note: self)
    }

    deinit {
        if self.owned {
            #if DEBUG_NOTE_SIZE
                NdbNote.total_ndb_size -= Int(count)
                NdbNote.notes_created -= 1

                print("\(NdbNote.notes_created) ndb_notes, \(NdbNote.total_ndb_size) bytes")
            #endif
            free(UnsafeMutableRawPointer(note.ptr))
        }
    }

    static func == (lhs: NdbNote, rhs: NdbNote) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    // Implement the `Encodable` protocol
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(hex_encode(id.id), forKey: .id)
        try container.encode(hex_encode(sig.data), forKey: .sig)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(created_at, forKey: .created_at)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(tags, forKey: .tags)
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let content = try container.decode(String.self, forKey: .content)
        let pubkey = try container.decode(Pubkey.self, forKey: .pubkey)
        let kind = try container.decode(UInt32.self, forKey: .kind)
        let tags = try container.decode([[String]].self, forKey: .tags)
        let createdAt = try container.decode(UInt32.self, forKey: .created_at)
        let noteId = try container.decode(NoteId.self, forKey: .id)
        let signature = try container.decode(NdbSignature.self, forKey: .sig)

        guard let note = NdbNote(content: content, author: pubkey, kind: kind, tags: tags, createdAt: createdAt, id: noteId, sig: signature) else {
            throw DecodingError.initializationFailed
        }

        self.note = note.note
        owned = note.owned
        note.mark_ownership_moved() // This is done to prevent a double-free error when both `self` and `note` get deinitialized.
        count = note.count
        key = note.key
    }

    enum DecodingError: Error {
        case initializationFailed
    }

    #if DEBUG_NOTE_SIZE
        static var total_ndb_size: Int = 0
        static var notes_created: Int = 0
    #endif

    fileprivate enum NoteConstructionMaterial {
        case keypair(Keypair)
        case manual(Pubkey, NdbSignature, NoteId)

        var pubkey: Pubkey {
            switch self {
            case let .keypair(keypair):
                return keypair.pubkey
            case let .manual(pubkey, _, _):
                return pubkey
            }
        }

        var privkey: Privkey? {
            switch self {
            case let .keypair(kp):
                return kp.privkey
            case .manual:
                return nil
            }
        }
    }

    fileprivate init?(content: String, noteConstructionMaterial: NoteConstructionMaterial, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) {
        var builder = ndb_builder()
        let buflen = MAX_NOTE_SIZE
        let buf = malloc(buflen)

        ndb_builder_init(&builder, buf, buflen)

        var pk_raw = noteConstructionMaterial.pubkey.bytes

        ndb_builder_set_pubkey(&builder, &pk_raw)
        ndb_builder_set_kind(&builder, UInt32(kind))
        ndb_builder_set_created_at(&builder, UInt64(createdAt))

        var ok = true
        for tag in tags {
            ndb_builder_new_tag(&builder)
            for elem in tag {
                ok = elem.withCString { eptr in
                    ndb_builder_push_tag_str(&builder, eptr, Int32(elem.utf8.count)) > 0
                }
                if !ok {
                    return nil
                }
            }
        }

        ok = content.withCString { cptr in
            ndb_builder_set_content(&builder, cptr, Int32(content.utf8.count)) > 0
        }
        if !ok {
            return nil
        }

        var n = ndb_note_ptr()
        var len: Int32 = 0

        switch noteConstructionMaterial {
        case .keypair:
            var the_kp: ndb_keypair?

            if let sec = noteConstructionMaterial.privkey {
                var kp = ndb_keypair()
                memcpy(&kp.secret.0, sec.id.bytes, 32)

                if ndb_create_keypair(&kp) <= 0 {
                    #if DEBUG
                        print("bad keypair")
                    #endif
                } else {
                    the_kp = kp
                }
            }

            if var the_kp {
                len = ndb_builder_finalize(&builder, &n.ptr, &the_kp)
            } else {
                len = ndb_builder_finalize(&builder, &n.ptr, nil)
            }

            if len <= 0 {
                free(buf)
                return nil
            }
        case let .manual(_, signature, noteId):
            var raw_sig = signature.data.byteArray
            var raw_id = noteId.id.byteArray
            ndb_builder_set_sig(&builder, &raw_sig)
            ndb_builder_set_id(&builder, &raw_id)

            do {
                // Finalize note, save length, and ensure it is higher than zero (which signals finalization has succeeded)
                len = ndb_builder_finalize(&builder, &n.ptr, nil)
                guard len > 0 else { throw InitError.generic }

                // SECURITY WARNING: Signature verification disabled - secp256k1 not available
                // This note is NOT verified and should be treated as untrusted
                // Signature verification requires secp256k1 integration from NDK layer
            } catch {
                free(buf)
                return nil
            }
        }

        // guard let n else { return nil }

        owned = true
        count = Int(len)
        // self.note = n
        let r = realloc(buf, Int(len))
        guard let r else {
            free(buf)
            return nil
        }

        note = ndb_note_ptr(ptr: OpaquePointer(r))
        key = nil
    }

    convenience init?(content: String, keypair: Keypair, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) {
        self.init(content: content, noteConstructionMaterial: .keypair(keypair), kind: kind, tags: tags, createdAt: createdAt)
    }

    convenience init?(content: String, author: Pubkey, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970), id: NoteId, sig: NdbSignature) {
        self.init(content: content, noteConstructionMaterial: .manual(author, sig, id), kind: kind, tags: tags, createdAt: createdAt)
    }

    static func owned_from_json(json: String, bufsize: Int = 2 << 18) -> NdbNote? {
        return json.withCString { cstr in
            NdbNote.owned_from_json_cstr(
                json: cstr, json_len: UInt32(json.utf8.count), bufsize: bufsize
            )
        }
    }

    func verify() -> Bool {
        // SECURITY: Signature verification disabled - secp256k1 not available
        // Return false to indicate verification cannot be performed
        // Events using this should handle unverified state appropriately
        // Signature verification requires secp256k1 integration from NDK layer
        return false
    }

    static func owned_from_json_cstr(json: UnsafePointer<CChar>, json_len: UInt32, bufsize: Int = 2 << 18) -> NdbNote? {
        let data = malloc(bufsize)
        // guard var json_cstr = json.cString(using: .utf8) else { return nil }

        // json_cs
        var note = ndb_note_ptr()

        let len = ndb_note_from_json(json, Int32(json_len), &note.ptr, data, Int32(bufsize))

        if len == 0 {
            free(data)
            return nil
        }

        // Create new Data with just the valid bytes
        guard let new_note = realloc(data, Int(len)) else { return nil }
        let new_note_ptr = ndb_note_ptr(ptr: OpaquePointer(new_note))
        return NdbNote(note: new_note_ptr, size: Int(len), owned: true, key: nil)
    }

    func get_inner_event() -> NdbNote? {
        return inner_event
    }
}

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    var is_textlike: Bool {
        switch known_kind {
        case .text, .chat, .longform, .highlight, .live, .live_chat:
            true
        default:
            false
        }
    }

    var is_quote_repost: NoteId? {
        guard kind == 1, let quoted_note_id = referenced_quote_ids.first else {
            return nil
        }
        return quoted_note_id.note_id
    }

    var known_kind: NostrKind? {
        return NostrKind(rawValue: kind)
    }

    var too_big: Bool {
        return known_kind != .longform && content_len > 16000
    }

    var should_show_event: Bool {
        return !too_big
    }

    func is_hellthread(max_pubkeys: Int) -> Bool {
        switch known_kind {
        case .text, .boost, .like, .zap:
            return Set(referenced_pubkeys).count > max_pubkeys
        default:
            return false
        }
    }

    public var referenced_ids: References<NoteId> {
        References<NoteId>(tags: tags)
    }

    public var referenced_quote_ids: References<QuoteId> {
        References<QuoteId>(tags: tags)
    }

    public var referenced_noterefs: References<NoteRef> {
        References<NoteRef>(tags: tags)
    }

    public var referenced_follows: References<FollowRef> {
        References<FollowRef>(tags: tags)
    }

    public var referenced_pubkeys: References<Pubkey> {
        References<Pubkey>(tags: tags)
    }

    public var referenced_hashtags: References<Hashtag> {
        References<Hashtag>(tags: tags)
    }

    public var referenced_params: References<ReplaceableParam> {
        References<ReplaceableParam>(tags: tags)
    }

    public var referenced_mute_items: References<MuteItem> {
        References<MuteItem>(tags: tags)
    }

    public var referenced_comment_items: References<CommentItemRef> {
        References<CommentItemRef>(tags: tags)
    }

    public var references: References<RefId> {
        References<RefId>(tags: tags)
    }

    func thread_reply() -> ThreadReply? {
        if known_kind != .highlight {
            return ThreadReply(tags: tags)
        }
        return nil
    }

    func highlighted_note_id() -> NoteId? {
        return ThreadReply(tags: tags)?.reply.note_id
    }

    func block_offsets(ndb: Ndb) -> SafeNdbTxn<NdbBlockGroup.BlocksMetadata>? {
        let blocks_txn: SafeNdbTxn<NdbBlockGroup.BlocksMetadata>? = .new(on: ndb) { txn -> NdbBlockGroup.BlocksMetadata? in
            guard let key = ndb.lookup_note_key_with_txn(self.id, txn: txn) else {
                return nil
            }
            return ndb.lookup_blocks_by_key_with_txn(key, txn: txn)
        }

        guard let blocks_txn else { return nil }

        return blocks_txn
    }

    func is_content_encrypted() -> Bool {
        return known_kind == .dm // Probably other kinds should be listed here
    }

    func get_content(_ keypair: Keypair) -> String {
        if is_content_encrypted() {
            return decrypted(keypair: keypair) ?? "*failed to decrypt content*"
        } else if known_kind == .highlight {
            return referenced_comment_items.first?.content ?? ""
        }

        return content
    }

    func maybe_get_content(_ keypair: Keypair) -> String? {
        if is_content_encrypted() {
            return decrypted(keypair: keypair)
        } else if known_kind == .highlight {
            return referenced_comment_items.first?.content
        }

        return content
    }

    // Decryption is computed on-demand, not cached
    func decrypted(keypair: Keypair) -> String? {
        let our_pubkey = keypair.pubkey

        var pubkey = self.pubkey
        // This is our DM, we need to use the pubkey of the person we're talking to instead
        if our_pubkey == pubkey, let pk = referenced_pubkeys.first {
            pubkey = pk
        }

        return decrypt_dm(keypair.privkey, pubkey: pubkey, content: content, encoding: .base64)
    }

    public func direct_replies() -> NoteId? {
        return thread_reply()?.reply.note_id
    }

    public func thread_id() -> NoteId {
        guard let root = thread_reply()?.root else {
            return id
        }

        return root.note_id
    }

    public func last_refid() -> NoteId? {
        return referenced_ids.last
    }

    func is_reply() -> Bool {
        return thread_reply() != nil
    }

    func note_language(ndb _: Ndb, _ keypair: Keypair) -> String? {
        assert(!Thread.isMainThread, "This function must not be run on the main thread.")

        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        /*
         guard let blocks_txn = self.blocks(ndb: ndb) else {
             return nil
         }
         let blocks = blocks_txn.unsafeUnownedValue

         let originalOnlyText = blocks.blocks(note: self).compactMap {
                 if case .text(let txt) = $0 {
                     // Replacing right single quotation marks (’) with "typewriter or ASCII apostrophes" (')
                     // as a workaround to get Apple's language recognizer to predict language the correctly.
                     // It is important to add this workaround to get the language right because it wastes users' money to send translation requests.
                     // Until Apple fixes their language model, this workaround will be kept in place.
                     // See https://en.wikipedia.org/wiki/Apostrophe#Unicode for an explanation of the differences between the two characters.
                     //
                     // For example,
                     // "nevent1qqs0wsknetaju06xk39cv8sttd064amkykqalvfue7ydtg3p0lyfksqzyrhxagf6h8l9cjngatumrg60uq22v66qz979pm32v985ek54ndh8gj42wtp"
                     // has the note content "It’s a meme".
                     // Without the character replacement, it is 61% confident that the text is in Turkish (tr) and 8% confident that the text is in English (en),
                     // which is a wildly incorrect hypothesis.
                     // With the character replacement, it is 65% confident that the text is in English (en) and 24% confident that the text is in Turkish (tr), which is more accurate.
                     //
                     // Similarly,
                     // "nevent1qqspjqlln6wvxrqg6kzl2p7gk0rgr5stc7zz5sstl34cxlw55gvtylgpp4mhxue69uhkummn9ekx7mqpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qy28wumn8ghj7un9d3shjtnwdaehgu3wvfnsygpx6655ve67vqlcme9ld7ww73pqx7msclhwzu8lqmkhvuluxnyc7yhf3xut"
                     // has the note content "You’re funner".
                     // Without the character replacement, it is 52% confident that the text is in Norwegian Bokmål (nb) and 41% confident that the text is in English (en).
                     // With the character replacement, it is 93% confident that the text is in English (en) and 4% confident that the text is in Norwegian Bokmål (nb).
                     return txt.replacingOccurrences(of: "’", with: "'")
                 }
                 else {
                     return nil
                 }
             }
             .joined(separator: " ")
          */

        let originalOnlyText = get_content(keypair)

        // If there is no text, there's nothing to use to detect language.
        guard !originalOnlyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key.rawValue else {
            return nil
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        return localeToLanguage(locale)
    }

    var age: TimeInterval {
        let event_date = Date(timeIntervalSince1970: TimeInterval(created_at))
        return Date.now.timeIntervalSince(event_date)
    }
}

func hex_encode(_ data: Data) -> String {
    var str = ""
    for c in data {
        let c1 = hexchar(c >> 4)
        let c2 = hexchar(c & 0xF)

        str.append(Character(Unicode.Scalar(c1)))
        str.append(Character(Unicode.Scalar(c2)))
    }
    return str
}

private extension NdbNote {
    /// A generic init error type to help make error handling code more concise
    enum InitError: Error {
        case generic
    }
}
