//
//  NdbTxn.swift
//  damus
//
//  Created by William Casarin on 2023-08-30.
//

import Foundation
import NDKSwiftCore
import NostrDB

#if TXNDEBUG
    fileprivate var txn_count: Int = 0
#endif

// Would use struct and ~Copyable but generics aren't supported well
class NdbTxn<T>: RawNdbTxnAccessible {
    var txn: ndb_txn
    private var val: T!
    var moved: Bool
    var inherited: Bool
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: T) -> NdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, inherited: true, name: "pure_txn")
    }

    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }, name: String? = nil) {
        guard !ndb.is_closed else { return nil }
        self.name = name ?? "txn"
        self.ndb = ndb
        generation = ndb.generation
        if let active_txn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn,
           let txn_generation = Thread.current.threadDictionary["txn_generation"] as? Int,
           let ref_count = Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int,
           txn_generation == ndb.generation
        {
            // some parent thread is active, use that instead
            #if DEBUG
                print("txn: inherited txn")
            #endif
            txn = active_txn
            inherited = true
            generation = txn_generation
            let new_ref_count = ref_count + 1
            Thread.current.threadDictionary["ndb_txn_ref_count"] = new_ref_count
        } else {
            txn = ndb_txn()
            guard !ndb.is_closed else { return nil }
            generation = ndb.generation
            #if TXNDEBUG
                txn_count += 1
            #endif
            let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
            if !ok {
                return nil
            }
            generation = ndb.generation
            Thread.current.threadDictionary["ndb_txn"] = txn
            Thread.current.threadDictionary["ndb_txn_ref_count"] = 1
            Thread.current.threadDictionary["txn_generation"] = ndb.generation
            inherited = false
        }
        #if TXNDEBUG
            print("txn: open  gen\(generation) '\(self.name)' \(txn_count)")
        #endif
        moved = false
        val = with(self)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: T, generation: Int, inherited: Bool, name: String) {
        self.txn = txn
        self.val = val
        moved = false
        self.inherited = inherited
        self.ndb = ndb
        self.generation = generation
        self.name = name
    }

    /// Only access temporarily! Do not store database references for longterm use. If it's a primitive type you
    /// can retrieve this value with `.value`
    var unsafeUnownedValue: T {
        precondition(!moved)
        return val
    }

    deinit {
        if self.generation != ndb.generation {
            #if DEBUG
                print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            #endif
            return
        }
        if ndb.is_closed {
            #if DEBUG
                print("txn: not closing. db closed")
            #endif
            return
        }
        if let ref_count = Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int {
            let new_ref_count = ref_count - 1
            Thread.current.threadDictionary["ndb_txn_ref_count"] = new_ref_count
            assert(new_ref_count >= 0, "NdbTxn reference count should never be below zero")
            if new_ref_count <= 0 {
                ndb_end_query(&self.txn)
                Thread.current.threadDictionary.removeObject(forKey: "ndb_txn")
                Thread.current.threadDictionary.removeObject(forKey: "ndb_txn_ref_count")
            }
        }
        if inherited {
            #if DEBUG
                print("txn: not closing. inherited")
            #endif
            return
        }
        if moved {
            return
        }

        #if TXNDEBUG
            txn_count -= 1
            print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
    }

    // functor
    func map<Y>(_ transform: (T) -> Y) -> NdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: transform(val), generation: generation, inherited: inherited, name: name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (NdbTxn<T>) -> Y) -> NdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: with(self), generation: generation, inherited: inherited, name: name)
    }
}

protocol RawNdbTxnAccessible: AnyObject {
    var txn: ndb_txn { get set }
}

class PlaceholderNdbTxn: RawNdbTxnAccessible {
    var txn: ndb_txn

    init(txn: ndb_txn) {
        self.txn = txn
    }
}

class SafeNdbTxn<T: ~Copyable> {
    var txn: ndb_txn
    var val: T!
    var moved: Bool
    var inherited: Bool
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: consuming T) -> SafeNdbTxn<T> {
        .init(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, inherited: true, name: "pure_txn")
    }

    static func new(on ndb: Ndb, with valueGetter: (PlaceholderNdbTxn) -> T? = { _ in () }, name: String = "txn") -> SafeNdbTxn<T>? {
        guard !ndb.is_closed else { return nil }
        var generation = ndb.generation
        var txn: ndb_txn
        let inherited: Bool
        if let active_txn = Thread.current.threadDictionary["ndb_txn"] as? ndb_txn,
           let txn_generation = Thread.current.threadDictionary["txn_generation"] as? Int,
           let ref_count = Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int,
           txn_generation == ndb.generation
        {
            // some parent thread is active, use that instead
            #if DEBUG
                print("txn: inherited txn")
            #endif
            txn = active_txn
            inherited = true
            generation = txn_generation
            let new_ref_count = ref_count + 1
            Thread.current.threadDictionary["ndb_txn_ref_count"] = new_ref_count
        } else {
            txn = ndb_txn()
            guard !ndb.is_closed else { return nil }
            generation = ndb.generation
            #if TXNDEBUG
                txn_count += 1
            #endif
            let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
            if !ok {
                return nil
            }
            generation = ndb.generation
            Thread.current.threadDictionary["ndb_txn"] = txn
            Thread.current.threadDictionary["ndb_txn_ref_count"] = 1
            Thread.current.threadDictionary["txn_generation"] = ndb.generation
            inherited = false
        }
        #if TXNDEBUG
            print("txn: open  gen\(self.generation) '\(self.name)' \(txn_count)")
        #endif
        let placeholderTxn = PlaceholderNdbTxn(txn: txn)
        guard let val = valueGetter(placeholderTxn) else { return nil }
        return SafeNdbTxn<T>(ndb: ndb, txn: txn, val: val, generation: generation, inherited: inherited, name: name)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: consuming T, generation: Int, inherited: Bool, name: String) {
        self.txn = txn
        self.val = consume val
        moved = false
        self.inherited = inherited
        self.ndb = ndb
        self.generation = generation
        self.name = name
    }

    deinit {
        if self.generation != ndb.generation {
            #if DEBUG
                print("txn: OLD GENERATION (\(self.generation) != \(ndb.generation)), IGNORING")
            #endif
            return
        }
        if ndb.is_closed {
            #if DEBUG
                print("txn: not closing. db closed")
            #endif
            return
        }
        if let ref_count = Thread.current.threadDictionary["ndb_txn_ref_count"] as? Int {
            let new_ref_count = ref_count - 1
            Thread.current.threadDictionary["ndb_txn_ref_count"] = new_ref_count
            assert(new_ref_count >= 0, "NdbTxn reference count should never be below zero")
            if new_ref_count <= 0 {
                ndb_end_query(&self.txn)
                Thread.current.threadDictionary.removeObject(forKey: "ndb_txn")
                Thread.current.threadDictionary.removeObject(forKey: "ndb_txn_ref_count")
            }
        }
        if inherited {
            #if DEBUG
                print("txn: not closing. inherited")
            #endif
            return
        }
        if moved {
            return
        }

        #if TXNDEBUG
            txn_count -= 1
            print("txn: close gen\(generation) '\(name)' \(txn_count)")
        #endif
    }

    // functor
    func map<Y>(_ transform: (borrowing T) -> Y) -> SafeNdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: transform(val), generation: generation, inherited: inherited, name: name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (SafeNdbTxn<T>) -> Y) -> SafeNdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: with(self), generation: generation, inherited: inherited, name: name)
    }

    consuming func maybeExtend<Y>(_ with: (consuming SafeNdbTxn<T>) -> Y?) -> SafeNdbTxn<Y>? where Y: ~Copyable {
        moved = true
        let ndb = self.ndb
        let txn = self.txn
        let generation = self.generation
        let inherited = self.inherited
        let name = self.name
        guard let newVal = with(consume self) else { return nil }
        return .init(ndb: ndb, txn: txn, val: newVal, generation: generation, inherited: inherited, name: name)
    }
}

protocol OptionalType {
    associatedtype Wrapped
    var optional: Wrapped? { get }
}

extension Optional: OptionalType {
    typealias Wrapped = Wrapped

    var optional: Wrapped? {
        return self
    }
}

extension NdbTxn where T: OptionalType {
    func collect() -> NdbTxn<T.Wrapped>? {
        guard let unwrappedVal: T.Wrapped = val.optional else {
            return nil
        }
        moved = true
        return NdbTxn<T.Wrapped>(ndb: ndb, txn: txn, val: unwrappedVal, generation: generation, inherited: inherited, name: name)
    }
}

extension NdbTxn where T == Bool { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == Bool? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == Int { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == Int? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == Double { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == Double? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == UInt64 { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == UInt64? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == String { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == String? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == NoteId? { var value: T { return unsafeUnownedValue } }
extension NdbTxn where T == NoteId { var value: T { return unsafeUnownedValue } }
