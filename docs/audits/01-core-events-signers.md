# Audit: Core / Events / Signers

Scope: `Sources/NDKSwiftCore/Core/`, `Sources/NDKSwiftCore/Models/`, `Sources/NDKSwiftCore/Signers/`, `Sources/NDKSwiftCore/Errors/`, `Sources/NDKSwiftCore/Extensions/` (top level).

## Critical (correctness bugs)

- **`NDKList.encrypt` is a silent no-op masquerading as encryption** — `Sources/NDKSwiftCore/Models/Kinds/NDKList.swift:457-469`. The function takes a signer, sets `content = try JSONCoding.serializeToString(encryptedItems)` and returns. The inline comment admits *"For now, store as plain JSON - encryption would require NIP-04/44 implementation."* Callers (`addItem(encrypted: true)`, mute lists, etc.) believe their data is encrypted. Same in `decrypt(_:)` at line 472. This is security-sensitive: any caller asking for a private list item gets plaintext stored as the "encrypted" content. Either implement NIP-04/44 wrap/unwrap, or throw `NDKError.notImplemented` so callers can't silently rely on it.

- **`NDKBunkerSigner.connectNostrConnect` leaks the continuation forever** — `Sources/NDKSwiftCore/Signers/NDKBunkerSigner.swift:381-390`. The function stores `connectionContinuation` and launches an empty `Task {}` that does nothing — there is no timeout, no failure path, and no resume on `disconnect()` (line 732) or `deinit` (line 740). If no nostrconnect response arrives the caller awaits forever and the continuation is leaked. The bunker flow also offers no escape: a previous nostrconnect attempt's continuation may be silently overwritten by a second `connect()` call (line 383 unconditionally assigns), losing the first. Fix: track per-attempt continuations with a timeout (`Task.sleep` + `resume(throwing:)`), and in `disconnect()`/`deinit` resume any pending continuation with `.cancelled`.

- **`NDK.processEvent` skips signature verification when the relay isn't `NDKRelay` but still processes the event** — `Sources/NDKSwiftCore/Core/NDK.swift:779-806`. When `relay as? NDKRelay` is nil, the verifier is bypassed entirely (only a warning is logged) and the event flows on to the cache and subscription manager. Today the relay always is `NDKRelay`, but the public `RelayProtocol` abstraction explicitly allows other implementations — a test relay or any future adapter would silently bypass signature checks. Fix: either verify against `Crypto.verify` directly when the relay isn't `NDKRelay`, or reject the event.

- **Auth-required relay errors detected by `contains("auth")` substring** — `Sources/NDKSwiftCore/Core/Managers/NDKEventManager.swift:160-174`. NIP-42 specifies relay rejections start with literal prefix `auth-required:`. The current code matches *any* error string containing "auth", "restricted", or "authentication". This both over-fires (e.g. a relay returning "author blocked" would be misclassified) and under-fires (alternative reply prefixes would miss). Use `hasPrefix("auth-required:")` per NIP-42 and `hasPrefix("restricted:")` for that distinct prefix.

## High (likely bugs or footguns)

- **`NDKEvent.isReplaceable` semantics diverge from `EventKind.isReplaceable`** — `Sources/NDKSwiftCore/Models/NDKEvent.swift:285-289` returns true only for kinds 0, 3, and 10000-19999, excluding parameterized replaceable (30000-39999). But `Types.swift:279-283` includes 30000-39999 in `EventKind.isReplaceable`. `NDKFilter.isReplaceable` (`NDKFilter.swift:99-102`) uses the `EventKind` version. Callers comparing the two will get inconsistent answers for kind 30023 etc. Rename one (`isReplaceableEvent` vs `isAnyReplaceable`) or have `NDKEvent.isReplaceable` mirror the kind helper and let callers narrow via `isParameterizedReplaceable`.

- **`NDKEvent.tagReference` emits non-standard `a` tags with 5 elements** — `Sources/NDKSwiftCore/Models/NDKEvent.swift:325-336`. For replaceable/parameterized-replaceable events it returns `["a", "<kind>:<pubkey>:<d>", relayHint, markerValue, pubkey]`. NIP-01's `a` tag format is `["a", "kind:pubkey:d", relay-hint]`; markers belong on `e` tags (NIP-10), and the trailing pubkey is already embedded in the coordinate. Other clients receiving this may break parsing or treat the trailing positional field as a marker. Drop marker and pubkey for `a` tags.

- **`NDKBunkerSigner` does not override `encryptionEnabled()`** — `Sources/NDKSwiftCore/Signers/NDKBunkerSigner.swift` (no override; default in `NDKSigner.swift:44` returns `[]`). The signer implements `nip04_encrypt`/`nip44_encrypt` (lines 657-665) via RPC, but anyone calling `signer.encryptionEnabled()` to discover capability sees an empty list. This is the same kind of "pretends to not support" footgun. Override to return `[.nip04, .nip44]` (NIP-46 mandates both).

- **`NDKBunkerSigner` re-assigns `connectionContinuation` and the deserialized `connectionTypeRaw == "nostrConnect"` re-creates the signer with `options: nil`** — `Sources/NDKSwiftCore/Signers/NDKBunkerSigner.swift:800, 810-812`. After deserialization, a new `nostrConnect` URI gets generated with a fresh random secret (`initNostrConnect` inside `init`), but the original secret/URI is lost. Calling `connect()` on a restored nostrConnect session re-enters `connectNostrConnect` (line 339) and starts a new handshake — but `restoreState` (line 720-727) sets `isConnected = true` if `userPubkey` is set, which makes `connect()` early-return at line 287. So a "restored" session is in a hybrid state where it won't reconnect. Re-evaluate the restore flow: either keep the original secret on disk or skip the URI regeneration when restoring.

- **`NDKBunkerSigner` `deinit` mutates actor-isolated state without isolation** — `Sources/NDKSwiftCore/Signers/NDKBunkerSigner.swift:740-745`. `deinit` does `subscriptionTask?.cancel(); rpcClient = nil; isConnected = false` — these are actor-isolated stored properties. Swift's `deinit` for actors runs synchronously without isolation; mutating actor state from `deinit` is unsafe and produces warnings. Either move cleanup to an explicit async method called by the owner, or wrap in `Task { [subscriptionTask] in ...}` with `[weak self]` semantics — but in any event, do not assign to `rpcClient` and `isConnected` from `deinit`.

- **`NDKSessionData.processFollowListEvent`/`processMuteListEvent`/`processBlockedRelaysEvent` overwrite their own `.updating` state with `.ready` on the same call** — `Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:216-248, 252-271, 281-300`. In each function, after possibly setting `state = .updating(current:changes:)` (lines 233, 263, 293), the very next statements unconditionally set `state = .ready(...)` (lines 247, 270, 299). The `.updating` branch is dead code — observers will never see it because Observation collapses synchronous writes. Either remove the `.updating` setter, or actually leave the state in `.updating` until something marks the change complete.

- **`NDK.processEOSE` fires-and-forgets a `Task` with no cancellation tracking** — `Sources/NDKSwiftCore/Core/NDK.swift:842-846`. Each EOSE creates an unowned `Task { await internalSubscriptionManager.processEOSE(...) }`. If a relay rapidly cycles connect/EOSE during shutdown, these tasks accumulate and can outlive the NDK instance. Either await synchronously (the surrounding context is already async) or hold/cancel the task.

- **`NDKPool.addRelay` returns a "blocked" relay that is not in the pool** — `Sources/NDKSwiftCore/Core/Managers/NDKPool.swift:310-317`. When a relay is on the blocked list, the function returns a freshly-constructed `NDKRelay` that is *not* inserted into `relayMap`, has no NDK reference, and no observers. Callers (e.g. `NDKEventManager.publishToRelays`) treat the returned relay as a managed pool member and may try to publish to it — leading to silent failures. Either throw, return an optional, or surface the blocked status via a clear error.

- **`pubkey(_:)` on `NDKEventBuilder` silently swallows invalid pubkeys** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:209-216`. Invalid pubkey input logs a warning and returns `self` unchanged, so `pubkey` remains an empty string. When `build()` runs and the signer's pubkey is not used, the event is signed with `pubkey == ""`, failing validation later or producing an unsignable event. Either throw, or — if you want to keep the fluent style — store the error and rethrow at `build()`.

- **`NDKEventBuilder.reply` for kind-1 with parent e-tags copies all parent tags blindly without re-marking NIP-10 root/reply** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:115-129`. It does `for tag in event.tags { if "e"/"p" { builder.tag(tag) } }`, then adds a new `["e", parent.id, relay, "reply", pubkey]` and the parent author p-tag. Per NIP-10, in a multi-level thread the existing parent's `reply` marker should be **rewritten to `root`** if it was the original root, and only the new reply gets `reply`. As-is, the new event can have multiple tags marked `reply`, which other clients will mis-thread.

- **`NDKFilter` Codable round-trip can lose the `events` and `pubkeys` fields if both are also present as `#e`/`#p` tag filters** — `Sources/NDKSwiftCore/Models/NDKFilter.swift:131-145, 159-162`. The decoder reads `#e` into `self.events` and `#p` into `self.pubkeys`, while the loop at line 139-145 skips `#e`/`#p`. But the encoder writes `events`/`pubkeys` to `#e`/`#p` *and* writes any other `#X` tag filter normally. The dictionary representation at `dictionary` (line 388-406) doesn't emit empty arrays but tag filters are emitted only via `tagFilters` and not deduped against `events`/`pubkeys`. Confirm: if a user `addTagFilter("e", values: ...)` and also sets `events:` they will collide on `#e`. Add a single source of truth (always store `#e`/`#p` in `tagFilters`).

## Medium (technical debt / inconsistencies)

- **Magic-number kind literals where `EventKind` constants exist** — `Sources/NDKSwiftCore/Core/Managers/NDKEventManager.swift:93, 119` use `event.kind != 10002` instead of `EventKind.relayList`; `NDKEvent.swift:279, 288, 294, 295` use raw `20000`/`30000`/`40000` bounds instead of the `EventKind.*Range` constants you already defined in `Types.swift:266-275`.

- **Duplicated kind alias slots in `EventKind`** — `Sources/NDKSwiftCore/Core/Types.swift:115-125, 175-177, 200-203`. `profile == metadata`, `contactList == contacts`, `zap == zapReceipt`, `cashuMintList == nutzapPreferences`. The duplicates make the enum's source of truth ambiguous and can produce confusing autocomplete. Either expose them via computed properties (`static var profile: Int { metadata }`) or pick one canonical name.

- **`NDKEventTracker.customProperties` stores `[String: Any]` inside an `actor`** — `Sources/NDKSwiftCore/Models/NDKEventTracker.swift:37, 180-198, 240-249`. The actor's public API accepts and returns `Any`, defeating Swift 6 Sendable checks. `getStats()` also returns `[String: Any]`. Use a typed value enum or restrict to `Sendable` constraints — `Any` is a concurrency hole.

- **`NDKEventTracker` has no upper bound on the in-memory maps** — `Sources/NDKSwiftCore/Models/NDKEventTracker.swift:25-40`. `seenOnRelays`, `relayPublishStatuses`, `relayOKMessages`, `sourceRelays`, `customProperties`, `firstSeenTimestamps` all grow indefinitely; `cleanupOldEvents(cutoffDate:)` exists (line 222) but nothing in the codebase appears to call it. Wire it to a periodic timer or trigger from cache eviction.

- **`OKMessage` includes `receivedAt: Date` in `Equatable` synthesis** — `Sources/NDKSwiftCore/Core/Types.swift:406-410`. Two OK messages with same accepted/message but different timestamps are not equal — which is correct *if* you want temporal uniqueness, but conflicts with logical "same response" comparisons used elsewhere. Pick one and document.

- **`NDKRelayListManager` writes `kind 10002` events using all currently connected relays as the new list** — `Sources/NDKSwiftCore/Core/NDKRelayListManager.swift:189-211`. Any temporarily-connected outbox-discovered relay (origin `.outbox`) gets persisted to the user's published kind:10002. This will pollute the user's relay list with discovery relays they never chose. Filter by `origin == .appRelays` before constructing the new list.

- **`NDKProfile.startObservation` redundantly hops to `MainActor` from a class that is already `@MainActor`** — `Sources/NDKSwiftCore/Core/NDKProfile.swift:5-6, 102-105`. The class itself is annotated `@MainActor` (line 5), but the inner async loop wraps `self.metadata = metadata` in `await MainActor.run { ... }`. The hop is unnecessary; the loop is already in the actor's isolated context (it was launched via `Task` and the class is MainActor-isolated). Removing the `MainActor.run` simplifies and removes a needless hop.

- **`NDKProfile` keeps the subscription alive forever** — `Sources/NDKSwiftCore/Core/NDKProfile.swift:76-110`. The outer `Task` consuming `subscription.events` and the inner one consuming the cache stream are never cancelled. The `CancellationHandle` only flips a flag the loops check — there is no explicit `task.cancel()` and no `closeOnEose`. Each `getOrCreateProfile` adds a persistent subscription that lives until the profile is LRU-evicted (cache cap 500) — meaning up to 500 always-on subscriptions per session. Use `closeOnEose: true` for the network subscription or store and cancel the `Task`.

- **`NDKSessionData.loadCachedWOT` / `saveWOTToCache` are stub no-ops** — `Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:426-436`. Both functions are explicitly documented as "For now, return nil"/"For now, no-op". `loadWebOfTrust` (line 322) calls into them and runs full WOT sync every cold start. Either implement persistence (e.g. via the cache layer) or remove the dead code path so callers know WOT is always recomputed.

- **`NDKSessionData.syncWebOfTrust` fetches *all* contact-list events from discovery relays each refresh** — `Sources/NDKSwiftCore/Core/Session/NDKSessionData.swift:344-389`. With a typical follow set of a few hundred this is expensive and the timer runs once per day (`wotTimer`). There is no `since:` filter and `maxAge: 5 * minute` argues for short caching — the two settings are contradictory.

- **`NDKEventBuilder` is a `final class @unchecked Sendable` with mutable state** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:57-63`. The class comment acknowledges this is a footgun. Builders crossing async boundaries (e.g. `await tagUser`, `await build`) are vulnerable to data races if shared. Marking the type as a value type (`struct`) would be safer; if class semantics are required, gate mutation behind a lock or actor.

- **`NDKEventBuilder` references `sharedNDK` static via `static func setSharedNDK`** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:65-72`. The static is set in `NDK.init` (`NDK.swift:341`) but is *never read* by `NDKEventBuilder` itself. Dead state.

- **`NDKEventBuilder.tagBech32` for `nprofile` adds only one relay hint when multiple are encoded** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:706-708`. NIP-19 supports multiple relays in nprofile/nevent. The builder silently drops all but the first. Either round-trip all relays as multiple p-tags (per NIP-10/27 there's no defined multi-relay format on a p-tag) or document the limitation.

- **`NDK.handleAuthChallenge` builds the AUTH message by hand instead of via the codec** — `Sources/NDKSwiftCore/Core/NDK.swift:923-946`. It composes `let authMessage: [Any] = ["AUTH", eventDict]` then `JSONSerialization.data(...)`. There must be a `NostrMessage` encoder elsewhere (since CLIENT messages are sent in many places); using `[Any]` here means a future NIP-42 evolution requires changing two places.

- **`NDK.processEvent` and friends pass `RelayProtocol` then immediately downcast to `NDKRelay`** — `Sources/NDKSwiftCore/Core/NDK.swift:781, 832, 891`. Every code path that needs anything beyond `url` and `send` falls back to `as? NDKRelay`. Either tighten the parameter type, or expose the needed surface (signature stats, `updateConnectionState`, `markAsEvil`) on `RelayProtocol`.

- **`SubscriptionSwapManager` uses a "100 ms bridge filter" sleep with no documented rationale** — `Sources/NDKSwiftCore/Core/Subscription/SubscriptionSwapManager.swift:77-89`. A magic 100 ms delay between the bridge filter and the full filter; if relays haven't responded in that window, "bridge events" are silently lost. This is fragile and should be event-driven (await first batch, then swap).

- **`NDKEvent.encode` uses `naddr` with empty identifier for kind 0/3/10000-19999** — `Sources/NDKSwiftCore/Models/NDKEvent.swift:388-395`. For kind 0 (metadata), encoding to `naddr` with empty `d` is unusual — a `nprofile` is the conventional encoding. NIP-19 doesn't prohibit it, but third-party clients may not handle it. Consider returning `nprofile` for kind 0 and `nevent` for kind 3 (or document this choice).

## Low (style / nits worth tracking)

- **`NDK.startRelayObserver` initial load runs on `MainActor` and awaits the pool actor twice** — `Sources/NDKSwiftCore/Core/NDK.swift:470-503`. The `self.relays = await self.pool.relays` plus `appRelays = await self.pool.appRelays` are two round-trips; expose `(relays, appRelays)` snapshot in one call.

- **`NDKList.allItems = publicItems + encryptedItems`** but `encryptedItems` is a getter that parses JSON every call — `Sources/NDKSwiftCore/Models/Kinds/NDKList.swift:189-216`. Every access to `allItems` re-parses content; cache it.

- **`NDKContactList.fromEvent` exists alongside `NDKList.from(_:ndk:)`** — `Sources/NDKSwiftCore/Models/Kinds/NDKContactList.swift:61-71` vs `NDKList.swift:219-229`. Same pattern; parallel APIs invite divergence.

- **`NDKLogger.log` calls in hot subscription paths use string interpolation even when below threshold** — e.g. `Sources/NDKSwiftCore/Core/NDK.swift:773-803`. The trace/debug strings are formatted regardless of whether the logger filters them. `@autoclosure` parameters would eliminate the cost.

- **Excess emoji in log lines, sometimes the same emoji multiple times in one message** — broadly across `NDK.swift`, `NDKPool.swift`, `NDKEventManager.swift`. Minor style; consider whether a structured log category is more useful.

- **`NDKArticle.readingTime` splits on `" "` only** — `Sources/NDKSwiftCore/Models/Kinds/NDKArticle.swift:93-96`. Treats every space-separated token as a word; runs of newlines/punctuation are not splits. Inaccurate for markdown content.

- **`NDKEventBuilder.reply` returns the builder synchronously (await applied inside) but mutates `builder.kind` via the inner `kind(_:)` chain on a discarded result** — `Sources/NDKSwiftCore/Models/NDKEventBuilder.swift:112, 132`. The line `builder.kind(EventKind.textNote)` discards the returned builder; works only because `kind(_:)` mutates `self`. Inconsistent with the doc-promised functional pattern.

- **`NDKPrivateKeySigner.privateKey` is exposed via `privateKeyForNIP59`, `privateKeyValue`, and `serialize()`** — `Sources/NDKSwiftCore/Signers/NDKPrivateKeySigner.swift:9-11, 121-123, 131-136`. Three different ways to extract a private key reduces auditability. `privateKeyValue` is even labelled "for testing"; mark it `internal` or remove.

- **`BunkerURLParser.extractBunkerPubkey` handles `bunker://pubkey` via `path.hasPrefix("//")` substring** — `Sources/NDKSwiftCore/Signers/NDKBunkerSigner.swift:53-64`. URL parsing of `bunker://abc?...` already populates `url.host`; the `path` fallback is dead because URL won't return a path that starts with `//`. Either remove the fallback or document.

- **`OKMessage` is not `Codable`** — `Sources/NDKSwiftCore/Core/Types.swift:406-410`. Trivial to add and useful for persistence.

- **`EventKind.blockedMints` (10020) has no documentation comment** — `Sources/NDKSwiftCore/Core/Types.swift:204`. Inconsistent with neighboring constants.

- **`NDKRelayListManager.loadRelayList` early-returns after the first cache event** — `Sources/NDKSwiftCore/Core/NDKRelayListManager.swift:124-133`. Double `break` is correct but fragile; refactor with `for try await event = subscription.events.first(...)`.

## Observations / questions for maintainer

- The `NDK.signer` and `NDK.sessionData` are `public var` (`Sources/NDKSwiftCore/Core/NDK.swift:53, 57`) but the class is `final` + `@Observable`. Mutating them from arbitrary threads concurrently with reads is undefined. Should these be `@MainActor` or wrapped in an actor?

- `NDKEvent.encode(includeRelays:relayHints:)` is shadowed by `Codable.encode(to:)` — calling `event.encode()` may resolve ambiguously depending on context. Consider renaming to `toBech32()` or `bech32Encoded()` to avoid the overload collision.

- The `NDKError` enum is a single 200+ line type covering validation, network, storage, wallet, Cashu, Blossom, and serialization (`Sources/NDKSwiftCore/Core/Types.swift:415-622`). Some cases (`walletInsufficientBalance` + `insufficientBalance` + `walletInvalidProof`) overlap. Splitting into per-subsystem errors would help users handle them more precisely.

- `NDKEventBuilder.encrypt(...)` returns `NDKEvent` directly (sync-style) rather than the builder; subsequent fluent chaining is impossible. The naming suggests it sets a state, but the body actually `build`s. Consider `buildEncrypted(...)`.

- `NDKPool` uses `connectionErrorRateLimiter` (a global, referenced at `NDKPool.swift:394, 635, 718, 829`) without a visible declaration in scope — confirm it's defined in another in-scope module file and that it's actor-safe.

- The `@Observable final class NDK` exposes many `@ObservationIgnored` lazy properties — combined with the `@Observable` macro this means writes to these are not visible to SwiftUI. That is presumably intentional, but worth a one-line doc comment on each.
