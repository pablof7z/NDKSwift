//
//  NdbTxn.swift
//  damus
//
//  Created by William Casarin on 2023-08-30.
//
//  Rewritten 2026-05 for Swift Concurrency.
//
//  The original implementation tracked nested transactions through
//  `Thread.current.threadDictionary`, which is fundamentally incompatible
//  with Swift Concurrency: an `async` function can suspend at any await
//  and resume on a different thread, so the "inherited txn" fast-path
//  could silently miss a parent's open transaction OR pick up an
//  unrelated thread's snapshot. The deinit could also run on a thread
//  where the refcount slot was missing, leaking the LMDB read-txn.
//
//  This rewrite drops the inheritance fast-path entirely: every NdbTxn /
//  SafeNdbTxn owns exactly one `ndb_begin_query` and unconditionally
//  closes it with `ndb_end_query` in its deinit. The cost is extra LMDB
//  read transactions when nested-looking calls happen; the gain is
//  correctness — no data race on threadDictionary, no use of another
//  context's snapshot, no leaked read-txn pinning a stale snapshot.

import Foundation

import NostrDB

#if TXNDEBUG
    private var txn_count: Int = 0
#endif

// Would use struct and ~Copyable but generics aren't supported well
class NdbTxn<T>: RawNdbTxnAccessible {
    var txn: ndb_txn
    private var val: T!
    var moved: Bool
    /// Retained for binary-compat with callers that read this; always false
    /// in the new design since we no longer inherit parent transactions.
    let inherited: Bool = false
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: T) -> NdbTxn<T> {
        // A "pure" txn carries a value without an actual db handle. Mark it
        // as a moved/no-op so deinit doesn't try to end a query that was
        // never begun.
        let txn = NdbTxn(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, name: "pure_txn")
        txn.moved = true
        return txn
    }

    init?(ndb: Ndb, with: (NdbTxn<T>) -> T = { _ in () }, name: String? = nil) {
        guard !ndb.is_closed else { return nil }
        self.name = name ?? "txn"
        self.ndb = ndb
        generation = ndb.generation
        txn = ndb_txn()
        let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
        if !ok {
            return nil
        }
        #if TXNDEBUG
            txn_count += 1
            print("txn: open  gen\(generation) '\(self.name)' \(txn_count)")
        #endif
        moved = false
        val = with(self)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: T, generation: Int, name: String) {
        self.txn = txn
        self.val = val
        moved = false
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
        // The previous version did three checks (moved, generation, closed)
        // then called ndb_end_query — but the close-state checks weren't
        // synchronized against Ndb.close(), so an interleaving where
        // close() destroyed the env between our check and our call was
        // possible. endQueryIfAlive locks Ndb's lifecycle state, validates
        // both conditions inside the lock, and runs the close call from
        // within it.
        guard !moved else { return }
        var localTxn = self.txn
        let didClose = ndb.endQueryIfAlive(generation: generation) {
            ndb_end_query(&localTxn)
        }
        #if TXNDEBUG
            if didClose {
                txn_count -= 1
                print("txn: close gen\(generation) '\(name)' \(txn_count)")
            } else {
                print("txn: skip close gen\(generation) '\(name)' (closed or stale generation)")
            }
        #else
            _ = didClose
        #endif
    }

    // functor
    func map<Y>(_ transform: (T) -> Y) -> NdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: transform(val), generation: generation, name: name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (NdbTxn<T>) -> Y) -> NdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: with(self), generation: generation, name: name)
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
    /// Retained for binary-compat with callers that read this; always false
    /// in the new design. See NdbTxn for the rewrite rationale.
    let inherited: Bool = false
    var ndb: Ndb
    var generation: Int
    var name: String

    static func pure(ndb: Ndb, val: consuming T) -> SafeNdbTxn<T> {
        let txn = SafeNdbTxn(ndb: ndb, txn: ndb_txn(), val: val, generation: ndb.generation, name: "pure_txn")
        txn.moved = true
        return txn
    }

    static func new(on ndb: Ndb, with valueGetter: (PlaceholderNdbTxn) -> T? = { _ in () }, name: String = "txn") -> SafeNdbTxn<T>? {
        guard !ndb.is_closed else { return nil }
        var txn = ndb_txn()
        let ok = ndb_begin_query(ndb.ndb.ndb, &txn) != 0
        if !ok {
            return nil
        }
        let generation = ndb.generation
        #if TXNDEBUG
            txn_count += 1
            print("txn: open  gen\(generation) '\(name)' \(txn_count)")
        #endif
        let placeholderTxn = PlaceholderNdbTxn(txn: txn)
        guard let val = valueGetter(placeholderTxn) else {
            // Caller refused; clean up the txn we opened so we don't leak it.
            ndb_end_query(&txn)
            return nil
        }
        return SafeNdbTxn<T>(ndb: ndb, txn: txn, val: val, generation: generation, name: name)
    }

    private init(ndb: Ndb, txn: ndb_txn, val: consuming T, generation: Int, name: String) {
        self.txn = txn
        self.val = consume val
        moved = false
        self.ndb = ndb
        self.generation = generation
        self.name = name
    }

    deinit {
        // See NdbTxn.deinit for rationale — atomically validate generation
        // and is_closed under Ndb.lifecycleLock, then run ndb_end_query
        // inside the lock so close() can't destroy the env between
        // validation and the call.
        guard !moved else { return }
        var localTxn = self.txn
        let didClose = ndb.endQueryIfAlive(generation: generation) {
            ndb_end_query(&localTxn)
        }
        #if TXNDEBUG
            if didClose {
                txn_count -= 1
                print("txn: close gen\(generation) '\(name)' \(txn_count)")
            }
        #else
            _ = didClose
        #endif
    }

    // functor
    func map<Y>(_ transform: (borrowing T) -> Y) -> SafeNdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: transform(val), generation: generation, name: name)
    }

    // comonad!?
    // useful for moving ownership of a transaction to another value
    func extend<Y>(_ with: (SafeNdbTxn<T>) -> Y) -> SafeNdbTxn<Y> {
        moved = true
        return .init(ndb: ndb, txn: txn, val: with(self), generation: generation, name: name)
    }

    consuming func maybeExtend<Y>(_ with: (consuming SafeNdbTxn<T>) -> Y?) -> SafeNdbTxn<Y>? where Y: ~Copyable {
        moved = true
        let ndb = self.ndb
        let txn = self.txn
        let generation = self.generation
        let name = self.name
        guard let newVal = with(consume self) else { return nil }
        return .init(ndb: ndb, txn: txn, val: newVal, generation: generation, name: name)
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
        return NdbTxn<T.Wrapped>(ndb: ndb, txn: txn, val: unwrappedVal, generation: generation, name: name)
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
