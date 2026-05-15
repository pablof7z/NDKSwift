# Audit: Outbox / Negentropy / NIP-77 / UI / Cross-cutting

Read-only audit, Agent 5 of 5. Domain: `NDKSwiftCore/Outbox/`, `NDKSwiftCore/Negentropy/`, `NDKSwiftCore/NIP77/`, `NDKSwiftCore/Utils/`, `NDKSwiftCore/Errors/`, `NDKSwiftUI/`. Plus a cross-cutting sweep of the whole Sources tree.

All line numbers refer to the state of the tree at commit `e9925313`.

## Critical

### C1. Negentropy receives items in **descending** order — wire-protocol violation that breaks all reconciliation

Path:
- `NDKCacheNegentropyStorage.getItems` (`Sources/NDKSwiftCore/Negentropy/NDKCacheNegentropyStorage.swift:17`) returns the result of `cache.getEventsByTimeRange(...)`.
- `getEventsByTimeRange` (`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:1317`) forwards to `queryEvents`.
- `queryEvents` (`Sources/NDKSwiftCore/Cache/NDKNostrDBCache.swift:401`) ends with `results.sort { $0.createdAt > $1.createdAt }` — explicit DESCENDING.
- The Negentropy default storage extensions (`Negentropy.swift:534-587`) trust that the stream is sorted ascending by `(timestamp, id)` — they do binary search (`findLowerBound`), incremental fingerprinting, and incremental varint delta encoding on that order.

Concrete chain of corruption:
1. `splitRange` iterates items left-to-right and feeds each into `NegentropyAccumulator.add` (`NegentropyAccumulator.swift:16`). With items in DESC order the accumulator hashes them in the wrong sequence, so the local fingerprint never matches a spec-compliant peer's fingerprint over the same set.
2. `encodeTimestampOut` (`Negentropy.swift:434`) computes `delta = timestamp &- lastTimestampOut` (wrap-around) and writes `delta &+ 1` as a varint. With DESC iteration, `timestamp < lastTimestampOut` on every step, so the unsigned subtraction wraps to ~`UInt64.max`, producing pathological 10-byte varints on every bound.
3. `getMinimalBound` (`Negentropy.swift:415`) assumes `prev.timestamp <= curr.timestamp`. With reversed order this returns the wrong shared-prefix bound.
4. `findLowerBound` (`Negentropy.swift:539`) binary-searches assuming ascending order; on a DESC array it returns garbage indices, causing `lower > upper` slices that later index-out-of-range or produce empty fingerprints.

No tiebreaker by id is applied in the sort, so even if direction were flipped the order would still not be canonical Negentropy order (`timestamp ASC, id ASC`).

### C2. Two contradictory Negentropy wire encoders coexist; one is dead code that disagrees with the live one

`Sources/NDKSwiftCore/Negentropy/Negentropy.swift` (the path actually used) uses big-endian varints (encode: shift then reverse, line 454; decode: shift-left on each byte, line 514) and a bound layout of `varint(timestampDelta+1) || varint(idLen) || id`.

`Sources/NDKSwiftCore/Negentropy/NegentropyEncoder.swift` uses standard little-endian (LEB128-style) varints (encode line 118-128; decode line 313-334), a totally different message structure (bounds-mode byte, count + 8-byte fingerprint prefix, separate have/need ID lists), and a different concept of "initial message" (`encodeInitialMessage` writes only `0x61`).

A grep across `Sources/` shows `NegentropyEncoder` and `NegentropyDecoder` are referenced **only** from their own file:

```
$ grep -rn "NegentropyEncoder\|NegentropyDecoder" Sources/
Sources/NDKSwiftCore/Negentropy/NegentropyEncoder.swift:4
Sources/NDKSwiftCore/Negentropy/NegentropyEncoder.swift:138
```

This is a 350-line dead-code parallel implementation. Anyone reading the codebase will be misled by which is canonical, and the `NegentropyMessage` enum it defines (`NegentropyReconciler.swift:144-149`) leaks the wrong mental model.

### C3. `NIP77SyncHandler` shares mutable session state through a `static var`

`Sources/NDKSwiftCore/NIP77/NDKSyncExtension.swift:198`:

```swift
extension NIP77SyncHandler {
    ...
    private static var completedSessions = [String: CompletedSession]()
    ...
    func completeSession(_ session: SyncSession, subscriptionId: String) {
        Self.completedSessions[subscriptionId] = CompletedSession(...)   // line 205
    }
}
```

`NIP77SyncHandler` is `public actor`. Actor isolation does not extend to type-level (`static`) storage. This `static var` is mutated from inside the actor's methods but is shared across every `NIP77SyncHandler` instance in the process. With Swift 6 strict concurrency this is a hard data race; in Swift 5 it is an undetected race when two concurrent sync sessions run.

Note also: the *instance* `completedSessions` (`NIP77SyncHandler.swift:27`) and this static dict have the same name — confusion is baked in. The instance dict is the one actually used by `getCompletedSession` (`NIP77SyncHandler.swift:241`). The static is therefore both racy *and* never read.

### C4. `NDKUIFollowListDataSource` retain cycle — every instance leaks

`Sources/NDKSwiftUI/DataSources/NDKUIFollowListDataSource.swift:36-58`:

```swift
private func observeFollowList() {
    observationTask = Task { @MainActor in
        var latestEvent: NDKEvent?
        for await batch in dataSource.events {    // implicit self.dataSource
            ...
            followList = Set(pubkeys)             // implicit self.followList
            lastUpdate = ...                      // implicit self.lastUpdate
        }
    }
}
```

- `self` owns `observationTask`.
- The Task's closure has no capture list, so it captures `self` strongly via `dataSource`, `followList`, `lastUpdate` accesses.
- `for await batch in dataSource.events` blocks the closure for the subscription's lifetime, which is open until closed elsewhere — that lifetime is unbounded in this class.
- Therefore `self` is never deallocated; `deinit` (line 31) never runs; `observationTask?.cancel()` in `deinit` is unreachable.

Every `NDKUIFollowListDataSource` created leaks until process exit. Worse: the underlying `NDKSubscription` and any associated relay subscriptions also leak because nothing closes them.

### C5. Zap "user reacted" detection is a stub — UI permanently shows hasZapped == false

`Sources/NDKSwiftUI/Components/Actions/NDKUIZapButton.swift:448-451`:

```swift
private func parseZapRequestSender(_: String) -> String? {
    // Parse JSON to extract the pubkey from the zap request
    return nil
}
```

The only caller is `extractZapSender` (line 423-434), which is the only path that sets `userZapped = true` in `updateZapState` (line 396-400). Because the parser is a hard-coded `nil`, `hasZapped` is always `false` for the current user. All visual state that depends on it (active color line 104, background line 276, border line 288) renders incorrectly. The public API contract of `ZapState.hasZapped` is silently broken.

This is also security-adjacent: the right way per NIP-57 is to JSON-decode the `description` tag (which contains the signed zap *request*) and read its `pubkey` — not the zap *receipt*'s own pubkey, which is the LSP, not the zapper. The stub avoids that complexity entirely.

## High

### H1. Reaction/repost state never reflects deletions in real time

`Sources/NDKSwiftUI/State/ReactionState.swift:128-134` (and analogous code in `RepostState.observeReposts` / `NDKUIReactionButton.observeReactions`):

```swift
for await batch in subscription.events {
    for event in batch {
        allReactions[event.id] = event
    }
    await updateState(from: Array(allReactions.values))
}
```

There is no subscription to kind 5 (deletion) events and no removal of reactions when the user unlikes. Sibling `toggle()` (line 100) calls `userReactionEvent.delete(...)` to publish a deletion, sets `hasReacted = false` locally, but `allReactions` retains the deleted reaction object forever. Next time `updateState` runs (any new reaction arrives), `hasReacted` will flip *back to true* because the deleted reaction event is still in `allReactions` and matches `userPubkey`.

Symptom: tap heart → it un-fills → any other user reacts → it re-fills against the user's wish.

Same bug exists in `NDKUIReactionButton`'s `ReactionButtonState.updateReactionState` (lines 284-304), and the count semantics are different too: it counts events not pubkeys (line 291 `totalCount += 1` on every event), so one user reacting twice (network duplicate) double-counts.

### H2. Negentropy default storage extensions re-fetch the entire dataset on every call

`Sources/NDKSwiftCore/Negentropy/Negentropy.swift:533-587`. Every one of `size()`, `findLowerBound`, `fingerprint`, and the two `iterate` overloads internally calls:

```swift
let items = try await getItems(in: NegentropyRange(lower: nil, upper: nil, ...))
```

For a session that covers an active reconciliation, this is `O(splits × items)` calls into the storage — each of which round-trips through `cache.queryEvents`, deserialises every event, applies filters, sorts (DESC, see C1), allocates a fresh `NDKEvent` array, then maps to `NegentropyItem`. On a 10 000-event cache with a 16-bucket split tree of depth 3 this is ~50× redundant full scans.

`findLowerBound` (line 539) is especially perverse — it pulls the whole dataset just to do a binary search.

### H3. OK-message classification uses substring matching that produces both false positives and false negatives

`Sources/NDKSwiftCore/Outbox/NDKPublishingStrategy.swift:248-256`:

```swift
} else if let message = response.message {
    if message.contains("rate") {
        return .rateLimited
    } else if message.contains("auth") {
        return .authRequired
    } else if message.contains("invalid") || message.contains("error") {
        return .permanentFailure(reason: .invalid(message))
    }
}
```

NIP-01 specifies machine-readable *prefixes* in OK messages: `duplicate:`, `pow:`, `blocked:`, `rate-limited:`, `invalid:`, `auth-required:`, `restricted:`, `error:`. Substring matching:

- `contains("auth")` also matches `"unauthorized"`, `"author rejected"`, `"deauth in progress"`.
- `contains("rate")` matches `"moderate spam content"`, `"could not generate signature"`.
- `contains("error")` is so generic it catches any human-readable failure note.
- Misses the canonical prefixes when relays use them strictly (e.g. `"pow: 24 bits required"` falls through and becomes `.temporaryFailure`, which triggers a retry loop on a permanent failure).

This impacts retry strategy directly: rate-limit false positives waste exponential-backoff budget; permanent-failure false negatives cause infinite retry against rejecting relays.

### H4. NIP-65 e-tag relay hints are added to the publish set with **no validation or normalization**

`Sources/NDKSwiftCore/Outbox/NDKRelaySelector.swift:83-91`:

```swift
for tag in event.tags {
    if tag.count >= 3 && tag[0] == "e" {
        let relayHint = tag[2]
        if !relayHint.isEmpty {
            selectedRelays.insert(relayHint)
        }
    }
}
```

`tag[2]` is treated as a relay URL with zero checks. Compare to `NDKOutboxManager.processRelayListEvent` (`NDKOutboxManager.swift:455-456`) which goes through `.validForOutbox` filtering, and `NDKRelaySelector.chooseRelayCombinationForPubkeys:241-249` which checks blocklist + `URLNormalizer.isValidForOutbox`.

Consequences:
- Malformed strings (`"https://"`, `"javascript:..."`, `""` after whitespace strip — actually empty is caught; anything else isn't), `"localhost"`, `"ws://insecure"` all pass through.
- The same relay with subtly different URLs (`"wss://r.com"`, `"wss://r.com/"`, `"WSS://r.com"`) will be treated as different publish targets and may trigger multiple connection attempts.
- An untrusted event author can list a relay-hint pointing at a malicious or paid endpoint, and this code will try to publish to it.

### H5. `NDKRelaySelector.chooseRelayCombinationForPubkeys` has duplicated "second" and "third" passes

`NDKRelaySelector.swift:263-321`. The second pass (line 263-292) iterates `pubkeys`, fetches relays from `pubkeyRelayInfo.pubkeysToRelays[pubkey]`, and assigns them. The third pass (line 294-321) does *the same thing* — same source dictionary (`pubkeyRelayInfo.pubkeysToRelays[pubkey]`, line 300), same filtering, same assignment loop — but is documented as "Add hint relays directly from HintIndex for each pubkey".

`pubkeyRelayInfo` is built once by `getAllRelaysForPubkeys` (line 540-585) which *already* falls back to the HintIndex (lines 565-580). There's no second source being consulted in the "third pass" — it just re-runs the second pass against any remaining capacity, in arbitrary dictionary order, without the `sortedRelays` ranking the second pass used.

Net effect: the second pass picks ranked best relays; the third pass top-up picks unranked arbitrary relays. The dead code intent appears to be "now consult HintIndex" but never actually does.

### H6. `NIP77Message.fromDictionary` decodes `since`/`until` as `Int64` — JSON decoding will silently drop them

`Sources/NDKSwiftCore/NIP77/NIP77Message.swift:319-323`:

```swift
if let since = dict["since"] as? Int64 {
    filter.since = Timestamp(since)
}
if let until = dict["until"] as? Int64 {
    filter.until = Timestamp(until)
}
```

`JSONSerialization.jsonObject(with:)` produces `NSNumber` for numeric JSON, and Swift bridges them to `Int` (on 64-bit, which is all Apple platforms NDKSwift targets). `as? Int64` against an `NSNumber`-backed Int **fails** because the dynamic type is `__NSCFNumber`/`Int`, not `Int64`. So in practice every NIP-77 NEG-OPEN filter loses its time bounds.

Should be `as? Int` (or `(dict["since"] as? NSNumber)?.int64Value`). Same class of issue is absent elsewhere because most decoders go through `JSONDecoder`/`Codable`.

Additionally, `toDictionary`/`fromDictionary` (lines 273-355) doesn't roundtrip `events` (`#e`) or `pubkeys` (`#p`) explicitly. They get folded into generic `tags`, and any caller who built an `NDKFilter` with the dedicated `events`/`pubkeys` slots loses that distinction across NIP-77 transit.

### H7. NIP-77 long-poll waits on async sleep — busy poll loop on the main NDK extension

`Sources/NDKSwiftCore/NIP77/NDKSyncExtension.swift:75-80`:

```swift
while await syncHandler.isSyncActive(subscriptionId: subscriptionId) {
    if Date().timeIntervalSince(startWait) > timeout {
        throw NIP77Error.timeout("Sync timeout after \(timeout) seconds")
    }
    try await Task.sleep(nanoseconds: 100 * TimeConstants.nanosecondsPerMillisecond)
}
```

This is a 100 ms wake-up polling loop hitting the `NIP77SyncHandler` actor lock every tick to ask if the work is done. The right pattern is for `NIP77SyncHandler` to expose a completion future / AsyncStream the caller can await directly. As written, every active sync burns ~10 actor hops/second per sync session.

### H8. `NDKOutboxManager.fetchRelayListFromNetwork` has a Sendable-violating data race

`NDKOutboxManager.swift:757-816`. The function declares two local `var`s — `eoseRelays` and `relayListEvent` — then enters a `withTaskGroup` and writes to them from **two different child tasks** (lines 786-794 writes `relayListEvent`; lines 797-804 writes `eoseRelays`). Each child task is `@Sendable`, so it should require the captured `var` to be Sendable-safe. Reads after the group (line 819, 821, 824) assume both writes have committed.

The Swift 5 mode allows this without a diagnostic, but the writes are not synchronised — they race with each other and with the read after `await group.next()` returns. With strict concurrency this will be a compile error. With release builds it can produce stale `relayListEvent == nil` after the relay actually responded, falsely returning "no relay list found".

Additionally, `await group.next()` (line 812) waits for the first child to *finish*, and the first child to finish is normally the 2-second timeout task. So the event-collector task gets cancelled mid-iteration on the AsyncStream — events received in the last 100 ms before the cancellation propagation may be dropped silently.

## Medium

### M1. `NegentropyAccumulator` uses incremental SHA-256 over `(LE timestamp ‖ id)`

`Sources/NDKSwiftCore/Negentropy/NegentropyAccumulator.swift:16-27`:

```swift
public mutating func add(_ item: NegentropyItem) {
    var timestamp = item.timestamp.littleEndian
    withUnsafeBytes(of: &timestamp) { bytes in
        hash.update(data: Data(bytes))
    }
    hash.update(data: item.id)
    itemCount += 1
}
```

The fingerprint then is `SHA-256(concat(LE_u64(ts_i) ‖ id_i for i in order))` truncated to 16 bytes (`Negentropy.swift:567`).

This appears to diverge from the negentropy v1 reference accumulator, which (per the reference C++ implementation) accumulates a commutative sum modulo 2^256 over the items and only hashes once at the end. The order-dependence of an incremental SHA-256 is also exactly why C1 (DESC ordering) is fatal — a commutative accumulator would tolerate ordering bugs.

I cannot point at the spec text from this audit (read-only, no network), but the in-tree evidence — fragile order-dependence plus the standalone-spec-PDF-style accumulator name "Accumulator" — strongly suggests this is not the spec algorithm. If you are talking to vanilla NIP-77 relays (e.g. strfry), reconciliation will not converge regardless of whether C1 is fixed.

### M2. Negentropy `decodeBound` accepts an ID prefix longer than the protocol allows in only one place

`Sources/NDKSwiftCore/Negentropy/Negentropy.swift:502-505` rejects `len > 32`. Good. But `idSize = 32` is used elsewhere (`NegentropyConstants.idSize`) and the *encoder* `encodeBound` at line 446 will happily encode a longer `id`. There is no symmetric encode-side cap. A `NegentropyBound` constructed with a 33-byte id (which the current public constructor allows — line 23 has no precondition on id length) will be emitted and then **rejected on decode by the other side**.

### M3. `DataReader.readBytes` returns a `Data` slice with non-zero startIndex

`Negentropy.swift:645-650`:

```swift
mutating func readBytes(_ count: Int) -> Data? {
    guard position + count <= data.count else { return nil }
    let bytes = data[position ..< position + count]   // slice retains base index
    position += count
    return bytes
}
```

The returned `Data` shares the storage of the underlying buffer and its `startIndex` is `position` of the original buffer, not 0. Callers that index into it with `id[0]` will read from the original offset (which on the first call is 0, then advances). This bites when:

- The returned `Data` is hashed by `SHA256.update(data:)` — `update` does the right thing because it uses the slice's iterator.
- The returned id is later passed to `NegentropyItem(id:)` (the precondition `id.count == 32` would still hold).
- But the value gets compared by `Set<Data>.insert(id)` (`Negentropy.swift:271`). `Data` Hashable conformance hashes contents, not range, so two semantically-equal slices with different startIndex hash equal — OK.

The bug is subtle and may not currently bite, but `data[start..<end]` returning a non-zero-based slice is a perennial Swift footgun in this file. A safe pattern is `Data(data[start..<end])` (the copy initialiser re-bases). Recommend auditing every site.

### M4. `Bech32.encode` writes TLV length without checking that `relay.utf8.count <= 255`

`Sources/NDKSwiftCore/Utils/Bech32.swift:264, 341, 391`:

```swift
let relayData = Array(relay.utf8)
tlvData.append(1)
tlvData.append(UInt8(relayData.count))   // ⚠️ traps if relay UTF-8 > 255 bytes
tlvData.append(contentsOf: relayData)
```

A relay URL whose UTF-8 encoding is ≥ 256 bytes — possible with internationalised onion service URLs, query parameters, or pathological subdomains — will trap with `Swift.UInt8(_:) Overflow`. Same issue in `nevent`/`naddr`. `Data(hexString:)`-derived URLs from `nprofile`/`nevent`/`naddr` decode loops would similarly require validation.

### M5. `Data(hexString:)` silently auto-pads odd-length hex with a leading zero

`Sources/NDKSwiftCore/Utils/DataHexExtensions.swift:11-35`:

```swift
init?(hexString: String) {
    var hex = hexString.trimmed
    ...
    if hex.count % 2 != 0 {
        hex = "0" + hex   // silent padding
    }
    ...
}
```

`HexValidator.validateHex` enforces an even, exact length only when `expectedByteCount` is provided. Callers that go through `String.hexDecoded()` (extensive — search shows ~30 call sites) or `Data(hexString:)` directly will get truncated-but-valid data on truncated input.

Example impact: a copy-paste-truncated event id `"abcd...e"` (63 chars) becomes a 32-byte ID with leading zero, then comparisons silently mismatch the intended target without ever throwing.

### M6. `NIP77SyncHandler` `addRelay` with empty author pubkey

`NDKSyncExtension.swift:52`:

```swift
relay = await addRelay(relayURL, origin: .outbox(authorPubkey: ""))
```

`.outbox(authorPubkey: "")` claims this relay was discovered through the outbox model for an author whose pubkey is the empty string. Anywhere this origin is later consulted (per-pubkey relay tracking, telemetry, dedup) will associate the relay with the empty-string "user". Should probably be a dedicated origin variant for sync.

### M7. Negentropy `compareData` early-exit short-circuits an "impossible" branch

`Negentropy.swift:591-618`:

```swift
func compareData(_ a: Data, _ b: Data) -> Int {
    if a.isEmpty && b.isEmpty { return 0 }
    if a.isEmpty { return -1 }
    if b.isEmpty { return 1 }
    guard !a.isEmpty && !b.isEmpty else {   // unreachable, lines 598-600
        return a.count - b.count
    }
    ...
```

Lines 597-600 are unreachable because the three preceding ifs already cover the empty cases. The dead branch returns `a.count - b.count`, which contradicts the subsequent length-tiebreaker semantics (lines 615-617) anyway — shorter is "less than" there but the dead branch returns negative when `a.count < b.count`, which is the same sign — so it's accidentally consistent, but it should just be deleted.

Also worth noting: `Array(a)` / `Array(b)` (lines 606-607) copy the entire `Data` into a new heap allocation per call. With this function used in the binary-search path of `findLowerBound` (called once per item per fingerprint match), this is `O(n²)` allocation pressure during reconciliation.

### M8. `NDKUIRelativeTime` Timer + Swift concurrency mismatch

`Sources/NDKSwiftUI/Components/NDKUIRelativeTime.swift:97-110`. The struct is not `@MainActor`, but `currentTime` is `@State` (main-actor-isolated through SwiftUI). The `Timer.scheduledTimer(withTimeInterval:repeats:block:)` closure (line 102) is `@Sendable` per Foundation's signature, but it directly writes `currentTime` — which is fine *only* if Timer fires on the main run loop. Timer schedules on whatever run loop is current at scheduling time; with Swift concurrency and View bodies executed under a MainActor-isolated context, this happens to be main — but the pattern is fragile and will produce warnings under strict concurrency.

Additionally, the timer is stored in `@State` which is value-type semantics; SwiftUI's docs recommend `.task` + an AsyncStream / `Task.sleep` loop instead.

### M9. `NDKUnifiedSearchDataSource` leaks app-specific configuration into a generic library

`Sources/NDKSwiftUI/DataSources/NDKUnifiedSearchDataSource.swift:340-346`:

```swift
private func getSearchRelays() -> Set<String> {
    let relays = UserDefaults.standard.stringArray(forKey: "chirp_search_relays") ?? [
        "wss://relay.nostr.band"
    ]
    return Set(relays)
}
```

`"chirp_search_relays"` is the example app's UserDefaults key (Chirp is referenced in `e1843c5a Add Chirp README`). A generic UI library should not couple to a specific consumer; the search relays should be injected via init or read from `ndk.discoveryConfig`.

Also: hashtag streaming appends events and re-sorts the full array on every batch (`NDKUnifiedSearchDataSource.swift:334-335`), causing O(n log n) view recomputation per batch. With a popular hashtag and fast-arriving events, this is a known SwiftUI animation-thrash pattern.

### M10. `NDKPublishingStrategy.attemptPublishToRelay` does not implement NIP-42 auth

`NDKPublishingStrategy.swift:265-269`:

```swift
private func handleAuthChallenge(relay _: NDKRelay) async -> Bool {
    // This would implement NIP-42 auth
    // For now, returning false as auth implementation is relay-specific
    return false
}
```

Auth-required relays will always fail publishing through the outbox pipeline, despite the AUTH challenge being a recoverable state. The retry loop (line 207-215) detects `authRequired`, asks `handleAuthChallenge` which always returns false, and gives up. Per NIP-65, an author may *only* publish to read-relays that require auth, so this gap meaningfully shrinks the deliverable surface.

### M11. `NDKRelaySelector` contains three unreferenced private functions

`NDKRelaySelector.swift:401-475` (`extractContextualRelays`), `:454-475` (`extractContextualRelaysFromFilter`), `:477-504` (`selectRelaysForAuthors`). All three are `private func`s with no callers in the file or anywhere in `Sources/`. They duplicate logic that *is* used (the contextual-relay extraction was inlined directly into `selectRelaysForPublishing` at lines 83-91). Dead code; should be removed or wired in.

## Low

### L1. `NDKUI*` PreviewProviders all crash when SwiftUI renders the preview

Six call sites use the same pattern:

```swift
let mockNDK: NDK = { fatalError("NDK requires async cache init") }()
```

- `NDKUIProfilePicture.swift:148`
- `NDKUIRichTextView.swift:348`
- `NDKUIMarkdownView.swift:301`
- `NDKUIReactionButton.swift:370`
- `NDKUIFollowButton.swift:391`
- `NDKUIZapButton.swift:624`

The block is invoked immediately when SwiftUI evaluates `static var previews`. Xcode previews of these components crash on render, defeating the purpose of having `#if DEBUG` previews. Suggest either an `init?` mock, a separately compiled mock module, or skipping previews for components that hard-require NDK.

### L2. `NDKUI*.onAppear { setupObservation() }` patterns

`NDKUIFollowButton.swift:124`, `NDKUIReactionButton.swift:113`, `NDKUIZapButton.swift:159`. `.onAppear` fires on every reappearance, but the inner methods spawn a fresh observation Task each time without first awaiting the prior cancellation. For views that go on/off screen in a `LazyVStack` this means transient duplicate subscriptions until the cancellation propagates through the AsyncStream. Use `.task` (auto-cancels on disappearance) or guard against re-entry.

### L3. `NDKUIReactionButton` counts events, not unique pubkeys

`NDKUIReactionButton.swift:284-304`:

```swift
for event in events where event.content == reaction {
    totalCount += 1
    ...
}
```

If the same user reacts twice (e.g. duplicate event delivery from two relays where dedup hasn't kicked in yet, or an actual double-reaction), they count twice. Compare to `ReactionState.updateState` (`ReactionState.swift:144-156`) which dedups by `Set<String>` of pubkeys. Two implementations, two different definitions of "count", inconsistent UX.

### L4. Emoji equality uses raw `String ==` without normalisation

`ReactionState.swift:141`, `NDKUIReactionButton.swift:290`. `event.content == reaction`. Emoji like `"❤️"` can be transmitted as `U+2764 U+FE0F` (with variation selector) or `U+2764` alone, plus skin-tone modifiers, ZWJ sequences, etc. Two semantically-identical hearts will not compare equal. Recommend `String.unicodeScalars`-based normalisation or Unicode NFC + identifier-folding.

### L5. `NDKUnifiedSearchDataSource.startHashtagStream` uses magic kind 1

`NDKUnifiedSearchDataSource.swift:312`: `kinds: [1]` instead of `[EventKind.textNote]`. There is an `EventKind` enum used elsewhere; consistency would help.

### L6. `LoggingHelpers.timing` divides by zero when `duration == 0`

`Sources/NDKSwiftCore/Utils/LoggingHelpers.swift:111-125`. `Double(count) / duration` with `duration == 0` produces `+inf`, and the resulting log line shows `"X items, inf items/s"`. Cosmetic, but a `guard duration > 0 else { ... }` is a one-liner.

### L7. `Negentropy.swift` reset of timestamps on every reconcile message disagrees with the spec

`Negentropy.swift:185-186`:

```swift
// Reset timestamp tracking for each message
lastTimestampIn = 0
lastTimestampOut = 0
```

Reference negentropy implementations typically reset the encoder state *per output frame* but maintain a separate decoder state across messages. Resetting *both* per incoming message means the *output* frame produced by this call also starts from 0 — which is correct only if the peer also resets per message. Worth confirming against another implementation; could be a source of cross-implementation incompatibility.

### L8. `getRelaysForDiscovery` returns the **whole connected set** as a fallback for relay-list lookup

`NDKOutboxManager.swift:648-661`. If no explicit discovery relays are configured, this hits every connected relay with a kind-10002 filter. For an app connected to 20 relays this is 20 REQs. The right pattern is to use a small bootstrap set (a handful of well-known indexers).

### L9. `NDKPublishingStrategy.publishToRelay` exponential backoff cast to UInt64

`NDKPublishingStrategy.swift:204, 225`:

```swift
try? await Task.sleep(nanoseconds: UInt64(backoffInterval) * TimeConstants.nanosecondsPerSecond)
backoffInterval *= OutboxConstants.backoffMultiplier
```

`backoffInterval` is `TimeInterval` (Double). `UInt64(backoffInterval)` truncates fractional seconds — for an initial backoff of 0.5s this rounds to 0 nanoseconds. Fix: convert via `UInt64(backoffInterval * 1_000_000_000)`.

### L10. `NegentropyEncoder.decodeFullId` returns an 8-byte prefix padded to 32 zeros

`NegentropyEncoder.swift:345-349` (dead code per H/C1, but worth noting):

```swift
private static func decodeFullId(data: Data, index: inout Data.Index) throws -> Data {
    return try decodeIdPrefix(data: data, index: &index)
        .paddedToLength(32)
}
```

This claims to decode a full id but actually pads 8 bytes with 24 zeros. A caller treating the result as a full id will silently produce garbage. The function name lies about its semantics.

## Cross-cutting findings (TODOs, force-unwraps, prints, swallowed errors)

### TODO/FIXME/XXX/HACK comments

```
$ grep -rEni "todo|fixme|xxx|hack" Sources/ --include='*.swift'
(no matches)
```

**Zero markers across the entire `Sources/` tree.** Either the team disciplines them out aggressively or they are tracked elsewhere. Either way: nothing actionable in this category for this audit.

### `fatalError(`

```
$ grep -rn "fatalError(" Sources/ --include='*.swift'
```

User-reachable instances (i.e. not test, not vendored NostrDB):

- `NDKUIProfilePicture.swift:148`, `NDKUIRichTextView.swift:348`, `NDKUIMarkdownView.swift:301`, `NDKUIReactionButton.swift:370`, `NDKUIFollowButton.swift:391`, `NDKUIZapButton.swift:624` — all six are the same `let mockNDK: NDK = { fatalError(...) }()` pattern inside `#if DEBUG` preview blocks. Trips on every preview render in Xcode. Consolidated as L1.

NostrDB-internal (vendored library — `Cache/NostrDB/FlatBufferBuilder.swift:128`, `AsciiCharacter.swift:38`, `Table.swift:41`, `String+extension.swift:102`, `:109`) — out of scope per audit brief but worth noting that `String+extension.swift:102,109` are `serialize` overloads with bodies of just `fatalError("serialize should never be called from string directly")`, which is a code-smell substitute for an `@available(*, unavailable)` annotation.

### `preconditionFailure`

One instance: `Cache/NostrDB/NdbTagsIterator.swift:71` — `"Sequence subscript out of bounds"`. Vendored library; conventional sequence-subscript precondition. Acceptable.

### `try!` and `as!`

```
$ grep -rEn "try!\s|as!\s" Sources/ --include='*.swift'
```

- `try!`: zero matches.
- `as!`: one match — `Cache/NostrDB/FbConstants.swift:60`: `self as! Self.NumericValue`. Vendored. Tightly constrained generic context.

Clean.

### `print(` calls in production

Outside of:
- Vendored `Cache/NostrDB/` (NdbNote, NdbTxn, Ndb — extensive debug prints, but vendored)
- Doc comments (`/// print(...)` shows up everywhere as illustrative code)

The **only** production `print(` calls in `Sources/`:

- `Sources/NDKSwiftUI/State/RepostState.swift:91`: `print("[RepostState] toggle() - checking ndk.signer: \(...)")`
- `Sources/NDKSwiftUI/State/RepostState.swift:93`: `print("[RepostState] ERROR: ndk.signer is nil - ...")`

Both should go through `NDKLogger` like the rest of the codebase.

### Empty / error-swallowing catch blocks

```
$ grep -rnEz "catch\s*\{\s*\}" Sources/ --include='*.swift'
(no matches for empty bodies)
```

No literally-empty `catch { }` blocks. But:

- `try?` used 104 times across the tree. Spot-check shows most are intentional (cache miss, optional decode), but several in `NDKOutboxManager.fetchRelayListFromNetwork` (`NDKOutboxManager.swift:808`: `try? await Task.sleep(...)`) and `NDKPublishingStrategy` (`:204, :225`) swallow cancellation silently — which is the conventional way to dismiss sleep cancellation but is worth flagging in retry loops where it can mask cancellation propagation.

- `NDKPublishingStrategy.attemptPublishToRelay:259-262`:

  ```swift
  } catch {
      return .temporaryFailure
  }
  ```

  Discards the underlying error and unconditionally classifies as temporary. The retry loop then keeps retrying against, e.g., DNS failures forever (up to `publishRetries`). The error type is never logged at this site.

- `NIP77SyncHandler.swift:202`, `:218`, `:226` — three logged-and-continue catches. Acceptable.

### `nonisolated(unsafe)` mutable storage

11 sites across `Sources/`. Two of relevance to this audit's domain:

- `ReactionState.swift:57` and `RepostState.swift:56`: `@ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?` — class is `@MainActor`, so removing `nonisolated(unsafe)` would just default the property to MainActor-isolated, which is what you want. The `(unsafe)` is here only so the `deinit` can call `observationTask?.cancel()` (deinit is `nonisolated` by default). The right fix in Swift 6 is `isolated deinit` or a `nonisolated(nonsending) let cancellation = CancellationHandle()` indirection. As written this is a tolerated lie.

- Other `nonisolated(unsafe)` sites are in NDKLogger, NDKRelay, etc. — out of audit scope, but globally the codebase relies on this annotation more than is ideal.

### `@unchecked Sendable` usage

13 sites. Mostly justified at the call-site with a comment explaining the discipline (e.g. `NdbNote.swift:300-303`). One that stands out as undocumented and worth scrutiny: `Models/NDKEventBuilder.swift:57` — comment block exists; builder pattern with shared mutation. Out of domain scope.

### Files named "Disabled"/"Deprecated"/"Old"

None. Clean.

## Observations

### What the codebase does well

- Zero TODO/FIXME debt. That's exceptional; treat it as a goal-state.
- `NDKLogger` is used pervasively in Outbox and NIP-77 — good observability story.
- The `OutboxConstants` indirection lets retry/backoff/relays-per-author all be tuned centrally rather than scattered as magic numbers.
- `URLNormalizer.tryNormalizeRelayUrl` is *almost* universally applied; the e-tag hint code path (H4) is the conspicuous miss.
- `NDKOutboxManager` provides a clean positive/negative cache split with checkedRelays tracking for the negative case (`:680-686`) — that's good distributed-systems thinking.
- The Bech32 implementation looks correct on the encode/decode core; my concerns there (M4) are about length-prefix overflow on TLV inputs, not the polymod logic itself.

### Recurring themes

1. **Two parallel implementations of the same concept**: `Negentropy` vs `NegentropyEncoder/Decoder`, instance `completedSessions` vs static `completedSessions`, `NDKUIReactionButton.ReactionButtonState` vs the standalone `ReactionState`. Each pair has slightly different semantics, and there's no documented "this is the canonical one". Pick one and delete the other.

2. **SwiftUI components mix the new `@Observable` (iOS 17+) macro and the older `@StateObject + ObservableObject` patterns**. `NDKUIReactionButton/FollowButton/ZapButton` use the old pattern; `ReactionState/RepostState` use `@Observable`. Same UI module, two paradigms — confusing for library users.

3. **Public APIs depend on private nominal types via `internal init`/factory methods**, then bridge across modules using `Sendable` protocols. There's no explicit boundary between "core data structures" and "UI state objects" — they sometimes get used in either role.

4. **Cancellation discipline is inconsistent.** Some code uses `[weak self]` in spawned Tasks (Reaction/Repost state — though the inner `await self?.observe()` then captures self strongly inside `observe*()` because that method is `private func` on the class — see C4). Some doesn't capture weakly at all (`NDKUIFollowListDataSource` — full retain cycle). Some uses `nonisolated(unsafe)` to allow `deinit`-side cancellation. A pattern doc plus a code review pass on every `Task { ... await self.foo() ... }` site would help.

### Out-of-scope-but-noticed

- `Sources/NDKSwiftCashu/Wallet/NIP60WalletEventStream` uses `@unchecked Sendable` — Agent 3's domain.
- `Models/NDKRelay.swift` has heavy use of `nonisolated(unsafe)` storage for a UI bridge — Agent 2's domain, but the pattern is widespread enough that it bears system-level attention.

### Suggested triage order

1. **C1** (DESC ordering) — single-line fix in `NDKNostrDBCache.queryEvents` plus an explicit ASC variant for Negentropy storage. Highest impact, smallest blast radius.
2. **C4** (FollowListDataSource leak) — `[weak self]` in the Task closure + replace `for await batch in dataSource.events` with a cancellable wrapper.
3. **C5** (zap sender stub) — implement the JSON decode of the `description` tag.
4. **C2** (dead encoder code) — delete `NegentropyEncoder.swift`, `NegentropyDecoder`, and the unused `NegentropyMessage` cases.
5. **H1** (reaction deletion) — subscribe to kind 5, remove from local map.
6. **H3** (OK-message prefix matching) — switch to prefix matching per NIP-01.
7. **H4** (e-tag hint validation) — pipe through `URLNormalizer.isValidForOutbox`.
8. **H8** + **H7** (NIP-77 race + busy poll) — actor-isolated completion channel.
9. **M1** (fingerprint accumulator) — verify against the negentropy reference; this and C1 are the two pieces of work to make NIP-77 actually interoperate with strfry/other-impl peers.

Total findings: 5 Critical, 8 High, 11 Medium, 10 Low, plus cross-cutting summaries. ~34 substantive items, plus the cross-cutting tallies.
