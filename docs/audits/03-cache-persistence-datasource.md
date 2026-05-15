# Audit: Cache / Persistence / DataSource

Scope: `Sources/NDKSwiftCore/Cache/`, `Sources/NDKSwiftCore/DataSource/`, `Sources/NDKSwiftCore/Core/Session/`, storage-related Managers, and the Swift→C boundary in `Sources/NDKSwiftCore/Cache/NostrDB/` (NOT the C code itself).

Conventions: every finding cites `file:line`. Read directly; no code changes.

---

## Critical

### C1. Refactor regression: per-launch loss of NIP-05, KV store, decrypted-content, fetch-times, and unverified deletion-markers (no migration)

The commit that removed `NDKSQLiteCache` (e9925313) deleted 13 migration files including `Migration_v9_NIP05Cache.swift`, `Migration_v13_KeyValueStore.swift`, `Migration_v5_DecryptedContent.swift`, `Migration_v7_FetchTimestamps.swift`, `Migration_v4_OptimisticPublishing.swift`, etc. In the replacement `NDKNostrDBCache`, the following stores are declared as in-memory only and never persisted:

- `Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:98` — `deletedEventIds` (logical-deletion markers) — wiped on launch; once the deletion record is in LMDB but the in-memory set is empty, the deleted event reappears in query results.
- `Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1102` — `decryptedContentCache: LRUCache<String, String>` — every NIP-04/NIP-44 message must be re-decrypted on every launch.
- `Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1132` — `kvStore: [String: [String: Data]]` (the generic KV API, e.g. WOT scores in Session) — fully ephemeral despite being a documented `getValue/setValue/deleteValue` public surface (used as if persistent by callers).
- `Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1166-1170` — `nip05Cache`, `nip05ByPubkey`, `domainVerificationAttempts` — `NIP05Manager` writes here expecting persistence (`Sources/NDKSwiftCore/NIP05/NIP05Manager.swift:152,348,371,395`); every launch re-runs all .well-known/nostr.json fetches, hitting rate limits and burning bandwidth.
- `Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1280` — `fetchTimes` — `recordFetchTime` is called from `NDKSubscriptionManager` (`DataSource/NDKSubscriptionManager.swift:208`) to gate cache-staleness checks; with no persistence, the cache-freshness `maxAge` shortcut at `NDKSubscriptionManager.swift:95-101` always misses on cold start.

No code reads from a legacy SQLite file on upgrade. Existing users lose every queued unpublished event, every verified NIP-05, every WOT cache, etc. when they install the post-e9925313 build.

### C2. `ndbSubscribe` does not register the subscription before the initial query — race window for missed events

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:983-991`: the comment claims "CRITICAL: Create the subscription FIRST before querying to avoid race condition." Look at the implementation of `ndbSubscribe` at `Ndb.swift:914-976`: the actual `ndb_subscribe(...)` call sits inside a `Task { ... }` block at line 950. The outer `AsyncStream` initializer returns synchronously; control then falls through to `query(with:filters:maxResults:)` at line 991. The `Task` that calls `ndb_subscribe` is unordered relative to `query` — the documented invariant does not hold. Any event indexed by another ingester thread in the window between `query` finishing and `ndb_subscribe` actually running is lost.

A second nested `continuationSetupTask` (line 956-959) registers the continuation with the callback handler in yet another Task, racing against both `ndb_subscribe` returning and the C side firing callbacks. The `Ndb.CallbackHandler` queues into `subscriptionQueueMap` when no continuation is set yet (`Ndb.swift:1138-1149`), which mostly papers over this, but the per-subscription max of 2000 (`Ndb.swift:1100`) silently drops further events.

### C3. `NdbTxn` thread-affinity via `Thread.current.threadDictionary` is incompatible with Swift Concurrency

`Sources/NDKSwiftCore/Cache/NostrDB/NdbTxn.swift:35-64` (and the identical block at lines 172-201 in `SafeNdbTxn`) stores the active `ndb_txn`, its generation, and refcount in `Thread.current.threadDictionary`. The deinit at lines 102-110 / 233-241 decrements the refcount on whatever thread runs the deinit.

Every public cache method on `NDKNostrDBCache` is `async` and routinely suspends. A Task that opens an `NdbTxn`, calls `await self.relayCache.set(...)`, and resumes may resume on a different thread. Consequences:

- The "inherited txn" fast-path silently misses the parent's open txn (returns to opening a fresh `ndb_begin_query` — extra LMDB read-txn churn).
- A Task can pick up an unrelated thread's active txn (silently using somebody else's snapshot).
- The deinit can run on a thread where `ndb_txn_ref_count` is `nil`, never calling `ndb_end_query` — a leaked LMDB read-txn, which on long-running processes can pin a stale snapshot and bloat the database.

This was OK in the Damus origin where these were called from GCD queues. It is not OK as a transitively-reachable type from the async cache actor.

### C4. `eventRelaySources` grows monotonically — never pruned with events

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:94` declares `eventRelaySources: [String: Set<String>]`. The only places that remove from it are `clear()` (line 511) and `clearPersisted()` (line 529). `enforceMemoryLimit` (line 212), `pruneOldEvents` (line 263), and `deleteEvent` (line 496) all touch `events` and `eventAccessOrder` but never `eventRelaySources`. A long-running app accumulates entries indefinitely; the `maxMemoryEvents` ceiling (line 7) is bypassed for relay-source bookkeeping, and the dictionary remains a hard memory leak.

---

## High

### H1. `NDKSubscription.events` is a single-consumer broadcast — multiple iterators silently lose events

`Sources/NDKSwiftCore/DataSource/NDKSubscription.swift:186-217`. `createTrackedEventStream` (called once per `subscription.events` access) creates a fresh `AsyncStream` and spawns a `Task` that iterates `internalEvents` (the underlying single stream) and forwards into the new stream. `internalEvents` is a single `AsyncStream` (built once at line 302-305 or 372-376); the AsyncStream contract is that values are delivered to *one* iterator. If two consumers call `subscription.events`, two forwarding Tasks each `for await batch in source` — only one will actually receive each batch; the other will sit idle or get interleaved partial events. Combined with `ConsumerTracker.increment/decrement`, the count looks right but the consumer never sees the data.

Additionally inside that function:
- Line 199 sets `continuation.onTermination = { ... tracker.decrement() }` then line 212 overwrites it. The line-199 closure is dead code. Net effect: termination decrements exactly once, which is correct, but the duplicate assignment indicates the author misread `onTermination` semantics.

### H2. `NDKSubscriptionStateManager.setTask` cancels the previous task on each set; `init` paths set the task asynchronously, so a fast `updateFilter` can race with the initial observe Task

`Sources/NDKSwiftCore/DataSource/NDKSubscription.swift:320-324` and `:391-395`. The initial observe Task is created and *then* a separate `Task { await manager.setTask(observeTask) }` stores it. If a caller calls `updateFilter(...)` (`:532`) before that registration Task completes, `cancelTask()` finds no task to cancel, and the initial observe Task continues alongside the new one — producing duplicate event delivery and double-registered requirements (see `addObserver` at `NDKSubscriptionRequirement.swift:69` which never deduplicates).

### H3. `Ndb.subscribe`/`query` copy `NdbFilter.ndbFilter` (the struct value) into a freshly-allocated `UnsafeMutablePointer<ndb_filter>` array; the C `ndb_filter` likely owns internal pointers

`Sources/NDKSwiftCore/Cache/NostrDB/NdbFilter.swift:73-75` — `var ndbFilter: ndb_filter { return filterPointer.pointee }` returns a *value copy* of the C struct.

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:848-854` (in `query`) and `:918-921` (in `ndbSubscribe`) both copy that pointee into a separate heap allocation: `filtersPointer.advanced(by: index).pointee = ndbFilter.ndbFilter`. When that allocation is `deallocate()`d, no `ndb_filter_destroy` is called on it. Conversely, when the original `NdbFilter` is destroyed (its deinit at line 361-364 calls `ndb_filter_destroy` on `filterPointer`), the *copies* now hold dangling internal pointers (element arrays, etc.) — if `ndb_filter` `struct` carries a pointer to a separately-allocated element buffer, the copies share that buffer.

In practice the copies are used synchronously during the same `query`/`ndb_subscribe` call before the original goes out of scope, so this is usually OK. But `ndbSubscribe` keeps the copied `filtersPointer` alive across an async `state.deallocateFilters()` call (line 940/969) — by then the original `NdbFilter` may have been deinitialized. Worth a hard read of the C `ndb_filter` definition; if it owns heap memory the current code double-frees or use-after-frees.

### H4. NIP-09 deletion (kind 5) events are never applied to the cache automatically

There is no code path that, on receiving a kind-5 event, populates `NDKNostrDBCache.deletedEventIds` for the e-tagged event IDs. `deleteEvent(id:)` (`NDKNostrDBCache.swift:496`) exists but nothing calls it from event ingestion. `processEvent` (`NDKNostrDBCache.swift:878`) just stores the kind-5 like any other event. Searching the whole tree (`grep -rn "deletedEventIds\|kind.*== 5\b\|EventKind.delete"`) shows no automated handler. The cache returns deleted events to queries even after the deletion event is ingested.

### H5. NIP-40 `expiration` tag is not respected anywhere in the cache

`grep -rn "expiration"` returns no matches under `Sources/NDKSwiftCore/Cache/`. Expired events are returned from `getEvent`, `queryEvents`, `observeEvents`, etc. — both relays and the spec say such events should be discarded.

### H6. `NDKNostrDBCache.processEvent` bypasses the LRU bookkeeping that `saveEvent` maintains

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:878-901`. Network-received events are stored at line 900 (`events[event.id] = event`) but `eventAccessOrder` is never updated and `enforceMemoryLimit` is never called. `saveEvent` (line 288-322) handles both. Two consequences:

1. The in-memory cache grows past `maxMemoryEvents` until the next periodic enforcement (every 5 min, line 19).
2. When enforcement runs, `eventAccessOrder` is stale relative to `events`, triggering the O(N²) fallback at line 230-235 (`eventAccessOrder.removeAll { $0 == id }` inside a loop). For 10 000+ events this is a multi-second main-actor-blocking operation. The whole *point* of LRU is to avoid this.

### H7. `NDKSessionData` mutates `@Observable` state from arbitrary (non-MainActor) context

`Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:6` declares `@Observable public class NDKSessionData` (no `@MainActor`). `loadLists` (line 126) spawns `Task { for await batch in dataSource.events { for event in batch { processFollowListEvent(event, ...) } } }` (line 197-213). The processing functions assign to `contactListState`, `muteListState`, `blockedRelaysState`, `latestContactListEventId`, etc. on whatever executor the Task lands on. SwiftUI bindings will see updates from a non-main thread → undefined behavior and "Modifying state during view update" runtime warnings.

Also `loadWebOfTrust` (line 322) calls `Timer.scheduledTimer(...)` on whatever thread the property accessor `webOfTrust` was invoked on (line 315-319). Scheduling a Timer requires a RunLoop; on a background thread there's typically no run loop, so the daily WOT refresh silently never fires.

### H8. `processFollowListEvent`/`processMuteListEvent`/`processBlockedRelaysEvent` write `.updating` then immediately overwrite with `.ready` — the `.updating` state is unobservable

`Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:230-247` (follow), `:258-270` (mute), and the corresponding block in blocked-relays. The function assigns `contactListState = .updating(...)` (line 233), then unconditionally assigns `contactListState = .ready(newContactList, fromCache: fromCache)` (line 247). There is no `await` between them, so observers never see `.updating`. Either the intent (smooth `current` → `changes` transition for UI) is lost, or the `.updating` enum case is dead.

---

## Medium

### M1. `NDKNostrDBCache.getProfileMetadata` returns `eventId: "unknown"` (placeholder)

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:790` — `let eventId = "unknown"` with a `// For now, use a placeholder` comment. This is the value returned to every caller via `(metadata, updatedAt, eventId)`. Anything consuming `eventId` (delta detection, dedup, relay-hint lookup for the originating kind:0) will get a literal string `"unknown"`. The kind:0 event ID is actually trivially recoverable via `lookup_note_by_key` against the profile's note key, but the code doesn't bother.

### M2. `saveProfileMetadata` is a public no-op

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1295-1300`. Public API, advertised in tests/docs as "Save parsed profile metadata to cache", but the body just logs and returns. Anyone who built on top of `await cache.saveProfileMetadata(...)` thinking they wrote anything is wrong. The signature also has two suppressed parameter names (`updatedAt _:`, `eventId _:`), which is a confession.

### M3. `OptimisticPublishingManager` swallows initialization failure

`Sources/NDKSwiftCore/Cache/OptimisticPublishing/OptimisticPublishingManager.swift:7-13`. If `UnpublishedStore(cachePath:)` throws (disk full, permissions, malformed JSONL — see U1 below), the constructor logs at `.warning` and continues with `store == nil`. Every subsequent `add/confirm/recordPublishFailure` call (e.g. `addUnpublishedEvent` at `NDKNostrDBCache.swift:945` and `NDKEventManager.swift:109`) silently succeeds-without-doing-anything via `try await store?.add(...)`. Offline event queuing becomes a no-op without any caller-visible signal.

### M4. `UnpublishedStore` corrupts itself on a single malformed line

`Sources/NDKSwiftCore/Cache/OptimisticPublishing/UnpublishedStore.swift:87-93`. The loader does `try? JSONDecoder().decode(...)` per line and `continue`s on failure. That's gentle. But `add()` only appends (line 157, single line), while `markRelayPublished` / `markRelayFailed` / `remove` rewrite the whole file (lines 188, 203, 212). If a process is killed mid-`appendToFile` (line 119-138, non-atomic seek+write) you get a torn line — the rest of the file remains valid and the next launch silently drops that one record. Acceptable, but the partial line stays in the file until the next full rewrite. The contents could grow unbounded if only `add()` is called.

### M5. JSONL `add()` writes a duplicate line for the same `eventId` if `add()` is called twice

`UnpublishedStore.swift:142-165` — `records[event.id] = record` then `appendToFile(record)`. If the same event is added again (e.g. retry path), a second line is appended even though the dictionary collapses to one entry. Repeated retries grow the file linearly until the next full `writeToFile` (only triggered by `markRelayPublished/Failed/remove`). Reload reconstructs the dict so functionally OK, but disk grows.

### M6. `OutboxFilterStrategy.unknownAuthors` fallback path drops events when fallback subs are not yet connected

`Sources/NDKSwiftCore/DataSource/NDKSubscriptionRequirement.swift:204-254`. For unknown authors the code attempts to use `ndk.pool.connectedRelayURLs` first, then `pool.appRelays`, then `ndk.configuredRelayURLs`. If all three are empty the branch logs and *returns* (line 229-233) — unknown-author authors are simply not queried. There is no later-replay mechanism within this requirement (it relies on `handleRelayDiscovery` external to the requirement, line 458, which is documented to "log for debugging" only). The outbox path for unknown authors quietly drops.

### M7. `EOSETracker` ignores EOSE from un-expected relays and warns; no path to add them as expected

`Sources/NDKSwiftCore/DataSource/EOSETracker.swift:51-57`. If a relay sends EOSE but isn't in `expectedRelays`, the tracker logs `.warning` and *returns*, never counting that EOSE. `NDKSubscriptionRequirement.applyOutboxStrategy` calls `setExpectedRelays(Set(relaySubscriptions.keys))` (line 166) — but the requirement also receives EOSE from fallback relays added later via `createSubscription(... isFallback: true)` (line 246), and from "discovered" relays added in `NDKSubscriptionManager.handleRelayDiscovery` (line 416-432). For those, `addExpectedRelay` on the tracker is only called from `handleRelayAdded` (`NDKSubscriptionRequirement.swift:421`) which is reached only when `NDKSubscriptionCoordinator.markRelayAsActive(...)` (`NDKSubscriptionCoordinator.swift:439`) runs — and that only fires on the *replay* code path (`InternalSubscriptionManager.replaySubscriptionsForRelay`), not on initial creation. Net effect: a relay added via outbox fallback may send EOSE that's discarded, and aggregated-EOSE is delayed or never emitted.

### M8. Ingester is async; cache `queryEvents` papers over by also scanning the in-memory map — but `observeEvents` skips initial in-memory events

`NDKNostrDBCache.queryEvents` (`:357-409`) merges native nostrdb query results with `queryEventsInMemory` (`:412-448`) — sensible mitigation given the nostrdb async ingester. But `observeEvents` (`:576-639`) relies entirely on `nostrDB.subscribe`'s initial-batch (line 601) for "existing" events. Events that were just saved via `saveEvent` and haven't been ingested yet by nostrdb's async pipeline are missing from the initial batch (and only show up later when nostrdb finishes ingesting — if ever). This causes subtle staleness in `NDKSubscriptionRequirement.startProcessing` (which calls `cache.observeEvents(... includeExisting: true)`, `NDKSubscriptionRequirement.swift:89-92`).

### M9. `convertToNDKEvent` uses `note.content` which is `String(cString:)` — assumes NUL termination

`Sources/NDKSwiftCore/Cache/NostrDB/NdbNote.swift:347-349` — `content` is `String(cString: content_raw, encoding: .utf8) ?? ""`. The wrapper *does* expose `content_len` (line 355), but the Swift content accessor ignores it and trusts that the C buffer is NUL-terminated. If the content embeds a NUL byte or is not terminated (depends on how nostrdb stores raw JSON content payloads), this either truncates the content or reads past the buffer end. Safer: `Data(bytes: content_raw, count: Int(content_len))` → `String(data:encoding:)`.

### M10. `getDebugCheckedRoot` has identical DEBUG and non-DEBUG branches

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:1204-1212`. The name asserts that the function "checks" something in debug builds. Both branches just call `getRoot(byteBuffer: &byteBuffer)` with no verification (the verifier types in `Verifiable.swift` / `TableVerifier.swift` exist but are not wired up). Either delete the wrapper or actually use `Verifier`.

---

## Low

### L1. `NDKSubscription.fingerprint` is computed twice per requirement

`NDKSubscriptionManager.createRequirement` (`Sources/NDKSwiftCore/DataSource/NDKSubscriptionManager.swift:172`) computes `[optimizedFilter].toFingerprint(closeOnEose: closeOnEose)` and passes it to `createSubscription`. `InternalSubscriptionManager.createSubscription` (`Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift:52`) also computes the same fingerprint (`fingerprint ?? filters.toFingerprint(closeOnEose: closeOnEose)`) — fine because `fingerprint` is passed, but `NDKSubscriptionCoordinator.init` (`:406`) does the same `?? filters.toFingerprint(...)` defaulting *again*. Net: one wasted computation per subscription create.

### L2. `text_search` results buffer is a fixed-128 C array hand-unrolled via 128 `switch` cases

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:413-547` — 128 explicit `case` arms because the C result type is a fixed C array that Swift can't subscript. Brittle (will break silently if the C side bumps `NDB_MAX_TEXT_SEARCH_RESULTS`), and even now `limit` is capped at 128 regardless of what the caller asks for (line 398). Either expose the constant from C and bind via `withUnsafePointer { $0.withMemoryRebound(to: …) }` (as `stat()` already does at line 773-777), or document the 128 ceiling on the public API.

### L3. `NDKNostrDBCache.search_profile` requires NdbTxn that ignores closure cancellation

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:860-869` opens a fresh `NdbTxn(ndb:)` (line 865) without `Task.checkCancellation`. If the caller's Task is cancelled while we're in the LMDB read, the txn still runs to completion. Minor.

### L4. `clear()` cancels `enforcementTask` only inside `clearPersisted` (line 523), not inside `clear` (line 508)

`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:508-515`. After `clear()`, the background enforcement task keeps running against a now-empty cache. Wasted wakeups, no correctness bug.

### L5. `OptimisticPublishingManager.recordPublishFailure` does not emit a change event when `store?.markRelayFailed` succeeds — wait, it does inside the store. OK.

(Removed — already correct via `markRelayFailed` line 206. False alarm; included for transparency.)

### L6. `NDKEventManager.publishToRelays` swallows `cache.saveEvent` failures

`Sources/NDKSwiftCore/Core/Managers/NDKEventManager.swift:83-87`. If the local cache write fails (disk full, permission, ndb closed) the publish proceeds — meaning relays receive the event but the client has no record of it. `cache.addUnpublishedEvent` further down (line 109/121) silently logs at warning too. Combined with M3, a user can publish events that the client immediately "forgets".

### L7. `NDKSessionData.processFollowListEvent` and friends are not guarded by isolation, so the `event.id != latest…EventId` delta check is a TOCTOU

`Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:218`, `:254`, `:283`. The check is read+write in a non-isolated class. Concurrent processing of two batches (e.g. cached + network arriving close in time) can both see `nil` and both write the "first load" path. Not catastrophic — Observable just re-fires — but the `.updating` vs `.ready` branching depends on this and gets it wrong.

### L8. `NDKFetchedEvent.handleEvent` updates `event` without checking `cancellation.isCancelled` after the await

`Sources/NDKSwiftCore/DataSource/NDKFetchedEvent.swift:252-266`. The subscription iteration loop checks `cancellation.isCancelled` (line 237), but `handleEvent` itself doesn't. If cancellation flips between the loop check and `handleEvent` running, the published `event` is updated post-deinit observation. Cosmetic given `@MainActor` constraints.

### L9. `NdbFilter.create(from:)` declared but unused

`Sources/NDKSwiftCore/Cache/NostrDB/NdbFilter.swift:89-91` plus the same logic as a free function in the `Array<NostrFilter>.toNdbFilters()` extension at line 378-381. Two identical APIs, neither used outside of tests. Dead.

### L10. `Ndb.is_closed` is `closed || ndb.ndb == nil` but `closed` is mutated without synchronization

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:159,164-166,346-357`. `Ndb` is `@unchecked Sendable`; `closed` is read/written from arbitrary contexts. The class comment claims the field is "not hotly contended" but the only synchronization is "we hope" — `is_closed` checked at line 666, 706, 713, 721, 734, 750, 762, 847, 861, 970, 979 from many threads.

---

## Observations

### O1. `NDKNostrDBCache.dataToHex` is fine, `hexToData` is O(N) but allocates a `String` per byte

`NDKNostrDBCache.swift:1047-1062`. Not a hot path, but `dataToHex` (1064-1073) is correctly using `reduce(into:)` while `hexToData` still creates a String per byte (`String(hex[index..<nextIndex])`). For 32-byte event IDs called millions of times, this is measurable. Consider a single-pass `UnsafeBufferPointer` decoder.

### O2. Cache config disk-limit enforcement does not actually shrink LMDB

`NDKNostrDBCache.enforceDiskLimit` (`:243-257`) calls `pruneOldEvents` which just adds to `deletedEventIds` (line 263-277). LMDB files do not shrink. The whole "maxDiskSizeMB" knob is a polite lie — the database can only grow until `clearPersisted` blows it away.

### O3. Public Sendable surface on the cache is reasonable, but a few API leaks remain

`NdbFilter`, `NdbNote`, `Ndb` are all internal — good. But `NdbStat`, `NdbStatCounts`, `NdbDatabase`, `NdbCommonKind` are `public` (`Ndb.swift:31,72,112,121`). They claim `Sendable` and look correct. The only concern is that they expose internal database-index identities; future LMDB-index reorderings will be breaking API changes.

### O4. The "consolidation" left `NDKCache` as a doc-only term in three places

`Sources/NDKSwiftCore/Negentropy/NDKCacheNegentropyStorage.swift:3,4` — the class name is still `NDKCacheNegentropyStorage` and its doc says "Negentropy storage implementation backed by NDKCache" referring to the deleted protocol. The class uses the concrete `NDKNostrDBCache`; the comment is stale.

`Sources/NDKSwiftCore/Negentropy/NegentropyReconciler.swift:14` and `Sources/NDKSwiftCore/Negentropy/Negentropy.swift:48` — DocC examples reference `NDKCacheNegentropyStorage` which is fine (the type exists) but the doc text "backed by NDKCache" is misleading.

### O5. No `TODO`/`FIXME`/`HACK` markers in the audited scope

`grep -rni "todo\|fixme\|hack" Sources/NDKSwiftCore/{Cache,DataSource,Core/Session,Core/Managers}` returns nothing. That's unusual for code that recently had a major rewrite; either the markers were cleaned up (the optimistic interpretation) or unresolved issues are tracked elsewhere.

### O6. `NDKSubscription` is declared `final class … : Sendable` but creates `Task`s that capture `self` weakly inconsistently

E.g. `NDKSubscription.swift:204` `let task = Task { for await batch in source { ... continuation.yield(batch) } }` does not weak-capture `self`, but the enclosing closure doesn't reference `self`. OK. Compare to `:320` `Task { [weak self] in await self?.startObserving() }`. Style inconsistency only.

### O7. The optimistic-publishing pipeline conflates "queued for publish (offline)" with "publish attempted but waiting for ACK"

`UnpublishedStore.UnpublishedEventRecord.pendingRelays: [String: String]` (`UnpublishedStore.swift:24`) uses `""` for "pending" and a non-empty reason for "failed". This means callers cannot distinguish "this relay was queued because we were offline" from "this relay rejected with empty error string." `EventConfirmationState` (line 219-229) returns `.optimistic` whenever no relay has published yet — there's no way to surface "we tried, all relays failed." UI showing publish-failure indicators must dig through `getAllUnpublishedRecords` and inspect strings.

### O8. The `Ndb` `Log` shim is hard-stubbed out

`Sources/NDKSwiftCore/Cache/NostrDB/Ndb.swift:16-21` — `Log.error/info/debug` are all empty bodies. All the `Log.error("ndb_init failed...")` calls in `open()` (line 269) and elsewhere go to `/dev/null`. NDKLogger isn't used in `Ndb.swift` at all. If `ndb_init` fails (out of disk, permissions, corrupt db) the user sees only "NDKNostrDBCacheError.failedToOpen" with no detail.

### O9. `NDKMetaSubscription.start` spawns nested Tasks; the inner Task is fire-and-forget and isn't stored on stateManager

`Sources/NDKSwiftCore/DataSource/NDKMetaSubscription.swift:225-244`. The outer `processingTask` is stored via `setProcessingTask` (line 246). The inner relay-updates Task at line 226-236 is not — on `stop()` (`MetaSubscriptionStateManager.stop`, line 87-93) only `processingTask` is cancelled. The inner Task keeps consuming `relayUpdates` until that stream closes by itself.

### O10. Logical-deletion markers (`deletedEventIds`) prevent restoration via a re-published kind-5 reversal

NIP-09 has no "undo deletion" today, but logically a user could re-publish the original event to a new relay. `deletedEventIds` is a one-way set with no eviction; once an ID lands there it's filtered from queries until app restart (regression risk mostly the other direction — C1 says it doesn't persist, this O10 says the in-memory copy has no inverse). Combined with C1, the behavior is "deletions are forgotten on launch, then re-applied if a relay re-sends the kind:5." Inconsistent.

---

## Cross-cutting summary

1. **The SQLite→NostrDB consolidation discarded several layers that had nothing to do with event storage** (KV, NIP-05, decrypted content, fetch times, deletion markers). The new cache re-declares them as `private var`s with no persistence. This is the biggest practical regression from e9925313 and should be high-priority.
2. **The Ndb / NdbTxn layer was lifted from Damus without re-evaluating its thread model against Swift Concurrency.** `Thread.current.threadDictionary` for txn nesting is a fundamental mismatch and quietly degrades behavior. The subscribe/query race in `Ndb.swift:914-1019` has a misleading comment claiming a guarantee that the code does not provide.
3. **The DataSource layer's `NDKSubscription` is sound on paper but has actor/Task ordering bugs and a multi-consumer broadcast assumption that AsyncStream doesn't support.** It works for single-consumer SwiftUI but will surface when anyone iterates `events` twice.
4. **Session state mutation is not actor-isolated despite being `@Observable`.** Multiple state writes within one synchronous method also produce unobservable intermediate states.
5. **Optimistic publishing fails open** — if the store can't initialize, every publish call silently no-ops. This deserves at least a propagated error or a fallback.

— end of audit —
