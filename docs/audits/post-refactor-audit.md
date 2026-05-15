# Post-refactor audit — SQLite aux store, NdbTxn rewrite, FanoutSink

Scope: `NDKCacheSQLiteStore.swift` (commit `c10216b6`), `NdbTxn.swift` (commit
`d7f2ecf5`), `NDKSubscription.swift` events accessor (commit `bb15b57a`).
Wiring in `NDKNostrDBCache.swift` is in scope because it's where the new
SQLite layer is consumed and where the deletion / NIP-05 / KV state actually
lives.

## Critical (correctness bugs)

### 1. `Ndb.close()` orders the env destroy *before* the generation bump — NdbTxn deinit can call `ndb_end_query` on a destroyed env

`Ndb.swift:346-357`:

```
closed = true
ndb_destroy(ndb.ndb)
generation += 1
```

The rewritten `NdbTxn.deinit` (`NdbTxn.swift:87-112`) reads `ndb.generation`
and `ndb.is_closed` without synchronization and then calls
`ndb_end_query(&self.txn)`. There is a real TOCTOU window:

- Thread A (background, releasing the last txn ref) enters deinit, reads
  `ndb.generation` (still equal to its own, since the bump hasn't happened),
  reads `ndb.is_closed` (still false; `closed` not yet set), and proceeds.
- Thread B calls `Ndb.close()`, sets `closed = true`, destroys the LMDB env.
- Thread A executes `ndb_end_query(&self.txn)` — the env it's tied to is
  gone.

Even if you reorder the check, neither `closed` nor `generation` is published
under any synchronization primitive (`Ndb.closed` is a plain `private var
Bool`, `Ndb.generation` is a plain `var Int`, and `Ndb` declares
`@unchecked Sendable` at `Ndb.swift:154`). Two threads racing on these are a
data race per the Swift memory model irrespective of the LMDB-env hazard.

Fix sketch: bump `generation` *first*, then `closed = true`, then
`ndb_destroy` — and at minimum make `closed`/`generation` reads/writes
atomic (or move them under the existing `CallbackHandler` actor, or hold a
lock). The rewrite is otherwise a strict improvement; this hazard existed
before but the new deinit makes it the *only* path closing the txn, so it
fires more often.

### 2. `NDKNostrDBCache.clearDecryptedContent()` invokes `store.clearAll()` — truncates *every* SQLite table

`NDKNostrDBCache.swift:1296-1302`:

```swift
public func clearDecryptedContent() async {
    await decryptedContentCache.clear()
    sqliteWriteThrough { store in
        try await store.clearAll() // limited blast — but we don't have a per-table truncate yet
        _ = store
    }
}
```

`NDKCacheSQLiteStore.clearAll()` (`NDKCacheSQLiteStore.swift:337-345`)
truncates `kv`, `deleted_events`, `decrypted_content`, `nip05_cache`, and
`fetch_times`. A caller asking to clear decrypted content silently wipes
the NIP-05 cache, all KV state, deletion markers, and fetch-time
fingerprints. The comment "limited blast" is the opposite of what the code
does. Either add a per-table truncate to `NDKCacheSQLiteStore`
(`DELETE FROM decrypted_content;`) and call it here, or — at minimum —
gate this behind an explicit "I really mean clear everything" API.

### 3. FanoutSink has no buffering; batches yielded before the first consumer registers are lost forever

`NDKSubscription.swift:383-389` spawns `Task { await self.startObserving() }`
from `init` before any caller has accessed `subscription.events`. The
observe task registers with `dataRequirementManager` and starts looping
`for await batch in eventStream { await self.handleEvents(batch) }`
(`NDKSubscription.swift:493-498`). Cache-hit batches are produced
synchronously inside the requirement registration and arrive almost
immediately. They reach `handleEvents` → `fanout.yield(newTransformed)`
(`NDKSubscription.swift:535`).

`FanoutSink.yield` (`NDKSubscription.swift:196-203`) takes a snapshot of
the *current* consumers under the lock and yields to that snapshot.
There is no buffer, no replay. If the caller's `for await b in
subscription.events` hasn't reached `createTrackedEventStream` yet (the
caller might still be on the line *after* `init`), the batch is yielded
to an empty consumer set and is gone.

This is a regression versus the previous `internalEvents:
AsyncStream<[T]>` design: a single AsyncStream with default
`.unbounded` buffering would queue early batches until the first iterator
appeared. Worse, those events are still inserted into `processedEventIds`
(`NDKSubscription.swift:521-523`), so `refresh()` won't recover them — the
dedup set blocks them — and the only way to see them is to tear down the
whole subscription.

Fix sketch: have `FanoutSink` retain a bounded ring buffer of the most
recent N batches, replayed to each newly-registered consumer; OR make
`startObserving` defer launching until the first `events` access; OR don't
populate `processedEventIds` until a consumer is present.

## High (likely bugs)

### 4. `NDKNostrDBCache.clearPersisted()` doesn't touch the SQLite sidecar — hydration on next launch resurrects deleted state

`NDKNostrDBCache.swift:693-738` clears in-memory state, closes
`nostrDB`, deletes `data.mdb` / `lock.mdb`, and reopens. It never touches
`ndkswift-aux.sqlite`. Result: after `clearPersisted()` the in-memory
caches are empty but on the next `NDKNostrDBCache.init` (next process
start), `hydrateFromSQLite()` will repopulate `deletedEventIds`,
`nip05Cache`, `kvStore`, and `fetchTimes` from the sidecar that
`clearPersisted` ignored. Either delete the sidecar file alongside the
LMDB files at `NDKNostrDBCache.swift:717`, or call `try await
sqliteStore?.clearAll()` before reopening.

### 5. `invalidateNIP05` mutates the in-memory entry but never persists the new status (pre-existing, now load-bearing)

`NDKNostrDBCache.swift:1438-1444`:

```swift
if var entry = nip05Cache[identifier] {
    nip05ByPubkey.removeValue(forKey: entry.pubkey)
    entry.status = .invalid
    nip05Cache[identifier] = entry
}
```

The mutated `.invalid` entry is written back to the in-memory dictionary
but `sqliteWriteThrough { store.saveNIP05(...) }` is never called for
this branch. On next launch, `hydrateFromSQLite` (line 206-220) reads
back the *old* `.unverified`/`.verified` row and the entry is "valid"
again.

This bug existed pre-rewrite (in-memory was always volatile) but the
whole point of commit `c10216b6` is to make NIP-05 state persistent, so
the rewrite exposes it.

### 6. Concurrent `sqliteWriteThrough` writes to the same key can land in SQLite out-of-order

Every mutator that goes through `sqliteWriteThrough`
(`NDKNostrDBCache.swift:237-248`) spawns a fresh detached Task. The Task
then `await`s the SQLite actor. The actor serializes work *internally*,
but Swift's actor mailbox has no FIFO guarantee for messages submitted
by independent Tasks — the order in which two pending awaits acquire the
actor is unspecified.

Concrete scenario: from the cache actor, the caller does

```swift
await cache.setValue(v1, forKey: "k", namespace: "n")
await cache.setValue(v2, forKey: "k", namespace: "n")
```

In-memory ends up at `v2`. Each call enqueues a Task; both await
`store.setKV`. Either order is legal, so SQLite may end up at `v1` even
though in-memory and the user's intent agree on `v2`. Process restart →
hydration loads `v1` → divergence.

Fix sketch: serialize per-namespace/key on a dedicated actor or order
queue, or change `sqliteWriteThrough` to await the write before
returning (giving up the fire-and-forget ergonomic but preserving
ordering), or use a single producer-consumer queue inside the
`NDKNostrDBCache` actor that drains in submission order.

### 7. `NdbTxn` and `SafeNdbTxn` retain a strong `var ndb: Ndb` — the txn keeps `Ndb` alive even when generation/closed says it shouldn't

`NdbTxn.swift:33-42` (and the `SafeNdbTxn` mirror at line 140-149) hold
`var ndb: Ndb` strongly. When a transaction outlives its expected
scope (e.g. captured in a closure, stored in a property), `Ndb` cannot
deallocate. `Ndb.deinit` calls `self.close()` (`Ndb.swift:1078-1083`),
which in turn destroys the LMDB env — and the deinit of the held txn
then races with that close on the same thread. The strong reference
also means a stray txn pins a stale generation indefinitely, which
defeats the generation-mismatch fast-skip in deinit (the generation
never gets bumped because nobody can close the db).

Worth weakening to `weak var ndb: Ndb?` and guarding deinit accordingly.

## Medium (debt)

### 8. NIP-05 hydration silently drops rows whose JSON no longer decodes

`NDKNostrDBCache.swift:209` uses `try? decoder.decode(...)` and skips
rows that fail. Any schema migration of `NIP05CacheEntry` orphans every
existing row — they vanish from in-memory state but stay in SQLite, and
the next save with the same identifier overwrites them. There's no
warning log, no migration trigger, and no schema_version field for the
JSON payload (only for the table layout, at
`NDKCacheSQLiteStore.swift:118`). Log a warning when decode fails and
gate a deletion-or-migration pass on the in-table version.

### 9. `auxStorePath` builds a path that's identical for every cache opened with `path: nil`

`NDKNostrDBCache.swift:163-169` falls back to `Ndb.db_path() ??
NSTemporaryDirectory()` — the documents directory. Two `NDKNostrDBCache`
instances created with `path: nil` in the same process both open the
same SQLite file (the FULLMUTEX flag handles thread-safety inside one
handle, but each instance has its own handle). SQLite-level writes
serialize fine via WAL, but the two cache actors' in-memory caches
diverge: instance A's write-through updates SQLite; instance B's
in-memory still reflects its hydration snapshot. If the SDK ever
supports multiple `NDKNostrDBCache` per process, this needs an
explicit policy. Today it's mostly a footgun; document or detect.

### 10. `sqliteWriteThrough` swallows the error; the in-memory copy is now permanently inconsistent with disk

`NDKNostrDBCache.swift:237-248` logs at `.warning` and moves on. If the
disk is full, a hash-collision lookup fails, the connection breaks
(SQLITE_CORRUPT), every subsequent write also fails — the cache keeps
serving stale in-memory values that will silently be lost on next
launch. There is no health check, no consumer notification, no
auto-disable of the sidecar. Consider tracking
`consecutiveWriteFailures` and either flipping `sqliteStore` to nil
(falling back fully to memory-only and surfacing that via a published
property) or surfacing a delegate callback.

### 11. `decryptedContentCache` hydration is capped at 1000 most-recent rows but the live LRU has the same 1000 capacity — fine, but the SQLite table grows unbounded

`NDKNostrDBCache.swift:1278` and `:183`. Every
`storeDecryptedContent` writes through and there is no compaction or
TTL on the SQLite side (only the in-memory LRU evicts). Over time the
sidecar grows monotonically, and hydration always loads the same
1000-newest slice. Add either a delete-old policy keyed on `cached_at`
or a periodic vacuum trigger.

## Observations

### 12. `NdbTxn.inherited` and `SafeNdbTxn.inherited` are immutable `false`

`NdbTxn.swift:39` and `:146`. The comment correctly notes "binary compat".
If nothing outside this file reads `inherited`, the property and the
comment are pure dead weight; if something does, those callers can be
simplified to drop the parameter entirely. Quick `grep` would tell;
removing the field would shrink the wrapper.

### 13. `NDKCacheSQLiteStore`'s actor deinit closing the SQLite handle is fine

`NDKCacheSQLiteStore.swift:60-64`. Concurrency lawyers worry about
actor deinit semantics, but here it's safe: `sqlite3_close_v2` under
`SQLITE_OPEN_FULLMUTEX` is callable from any thread, the handle is not
shared, and the actor cannot deinit while any `Task { await
self.sqliteStore ... }` is mid-flight (the await keeps the actor
alive). The only thing extending lifetime is the pile of in-flight
write-through tasks — they drain, the actor deinits, the handle
closes. No bug; flagging because the task brief explicitly asked.
