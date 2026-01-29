//
//  NdbTagElem.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation
import NDKSwiftCore
import NostrDB

struct NdbStrIter: IteratorProtocol {
    typealias Element = CChar

    var ind: Int
    let str: ndb_str
    let tag: NdbTagElem // stored for lifetime reasons
    let isPackedId: Bool

    mutating func next() -> CChar? {
        // For NDB_PACKED_ID, don't iterate raw bytes as C string
        // as this can read past bounds - return nil to make iterator empty
        guard !isPackedId else { return nil }

        guard str.str != nil else { return nil }

        // Validate pointer accessibility if this is the first access
        if ind == 0 {
            guard str.str[0] >= 0 || str.str[0] < 0 else { return nil }
        }

        let c = str.str[ind]
        if c != 0 {
            ind += 1
            return c
        }

        return nil
    }

    init(tag: NdbTagElem) {
        str = ndb_tag_str(tag.note.note.ptr, tag.tag.ptr, tag.index)
        ind = 0
        self.tag = tag
        self.isPackedId = (str.flag == NDB_PACKED_ID)
    }
}

struct NdbTagElem: Sequence, Hashable, Equatable {
    let note: NdbNote
    let tag: ndb_tag_ptr
    let index: Int32
    let str: ndb_str

    func hash(into hasher: inout Hasher) {
        if str.flag == NDB_PACKED_ID {
            hasher.combine(bytes: UnsafeRawBufferPointer(start: str.id, count: 32))
        } else if str.str != nil {
            // Validate first byte is accessible before calling strlen
            guard str.str[0] >= 0 || str.str[0] < 0 else { return }
            hasher.combine(bytes: UnsafeRawBufferPointer(start: str.str, count: strlen(str.str)))
        }
    }

    static func == (lhs: NdbTagElem, rhs: NdbTagElem) -> Bool {
        if lhs.str.flag == NDB_PACKED_ID && rhs.str.flag == NDB_PACKED_ID {
            return memcmp(lhs.str.id, rhs.str.id, 32) == 0
        } else if lhs.str.flag == NDB_PACKED_ID || rhs.str.flag == NDB_PACKED_ID {
            return false
        }

        guard lhs.str.str != nil, rhs.str.str != nil else { return false }

        // Validate first byte is accessible before calling strlen
        guard (lhs.str.str[0] >= 0 || lhs.str.str[0] < 0),
              (rhs.str.str[0] >= 0 || rhs.str.str[0] < 0) else { return false }

        let l = strlen(lhs.str.str)
        let r = strlen(rhs.str.str)
        if l != r { return false }

        return memcmp(lhs.str.str, rhs.str.str, r) == 0
    }

    init(note: NdbNote, tag: ndb_tag_ptr, index: Int32) {
        self.note = note
        self.tag = tag
        self.index = index
        str = ndb_tag_str(note.note.ptr, tag.ptr, index)
    }

    var is_id: Bool {
        return str.flag == NDB_PACKED_ID
    }

    var isEmpty: Bool {
        if str.flag == NDB_PACKED_ID {
            return false
        }
        guard str.str != nil else { return true }
        // Validate pointer accessibility
        guard str.str[0] >= 0 || str.str[0] < 0 else { return true }
        return str.str[0] == 0
    }

    var count: Int {
        if str.flag == NDB_PACKED_ID {
            return 32
        } else if str.str != nil {
            // Validate pointer accessibility before calling strlen
            guard str.str[0] >= 0 || str.str[0] < 0 else { return 0 }
            return strlen(str.str)
        } else {
            return 0
        }
    }

    var single_char: AsciiCharacter? {
        guard str.str != nil else { return nil }
        // Validate pointer accessibility
        guard str.str[0] >= 0 || str.str[0] < 0 else { return nil }
        let c = str.str[0]
        guard c != 0 && str.str[1] == 0 else { return nil }
        return AsciiCharacter(c)
    }

    func matches_char(_ c: AsciiCharacter) -> Bool {
        guard str.str != nil else { return false }
        // Validate pointer accessibility
        guard str.str[0] >= 0 || str.str[0] < 0 else { return false }
        return str.str[0] == c.cchar && str.str[1] == 0
    }

    func matches_id(_ d: Data) -> Bool {
        if str.flag == NDB_PACKED_ID, d.count == 32 {
            return memcmp(d.bytes, str.id, 32) == 0
        }
        return false
    }

    func matches_str(_ s: String, tag_len: Int? = nil) -> Bool {
        if str.flag == NDB_PACKED_ID,
           s.utf8.count == 64,
           var decoded = hex_decode(s), decoded.count == 32 {
            return memcmp(&decoded, str.id, 32) == 0
        }

        guard str.str != nil else { return false }

        // Ensure the Swift string's utf8 count matches the C string's length.
        guard (tag_len ?? strlen(str.str)) == s.utf8.count else {
            return false
        }

        // Handle empty strings explicitly to avoid memcmp with nil base address
        if s.utf8.count == 0 {
            return true
        }

        // Compare directly using the utf8 view.
        return s.utf8.withContiguousStorageIfAvailable { buffer in
            guard let baseAddress = buffer.baseAddress else {
                // Handle case where buffer has no base address (shouldn't happen with count > 0, but be safe)
                return false
            }
            return memcmp(baseAddress, str.str, buffer.count) == 0
        } ?? false
    }

    func data() -> NdbData {
        return NdbData(note: note, str: str)
    }

    func id() -> Data? {
        guard case let .id(id) = data() else { return nil }
        return id.id
    }

    func u64() -> UInt64? {
        switch data() {
        case .id:
            return nil
        case let .str(str):
            guard str.str != nil else { return nil }

            var endPtr: UnsafeMutablePointer<CChar>?
            let res = strtoull(str.str, &endPtr, 10)

            // Check if the entire string was consumed (null terminator reached)
            if let end = endPtr, end.pointee == 0 {
                return res
            } else {
                return nil
            }
        }
    }

    func string() -> String {
        switch data() {
        case let .id(id):
            return hex_encode(id.id)
        case let .str(s):
            guard s.str != nil else { return "" }

            // Additional safety: validate the first byte is accessible
            // If the pointer is invalid/dangling, this will catch many cases
            // before String(cString:) potentially crashes
            guard s.str[0] >= 0 || s.str[0] < 0 else { return "" }

            return String(cString: s.str, encoding: .utf8) ?? ""
        }
    }

    func makeIterator() -> NdbStrIter {
        return NdbStrIter(tag: self)
    }
}
