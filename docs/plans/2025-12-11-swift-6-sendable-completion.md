# Swift 6 Sendable Conformance Completion

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete Swift 6 strict concurrency migration by fixing all remaining Sendable conformance warnings

**Architecture:** Fix Sendable conformance issues in three categories: (1) unnecessary annotations, (2) non-Sendable class references, (3) concurrent closure captures. Use @unchecked Sendable judiciously only where runtime safety can be guaranteed.

**Tech Stack:** Swift 6, Swift Concurrency, Actors

---

## Task 1: Clean up unnecessary nonisolated(unsafe) annotations

**Files:**
- Modify: `Sources/NDKSwiftCore/Utils/DateFormatters.swift:39,52,65,91,103`

**Issue:** DateFormatter, ISO8601DateFormatter, and RelativeDateTimeFormatter are Sendable by default in modern Swift, making `nonisolated(unsafe)` unnecessary and triggering compiler warnings.

**Step 1: Remove nonisolated(unsafe) from display formatter**

In `Sources/NDKSwiftCore/Utils/DateFormatters.swift:39`, change:
```swift
public nonisolated(unsafe) static let display: DateFormatter = {
```

To:
```swift
public static let display: DateFormatter = {
```

Remove the concurrency safety comment block (lines 34-38) as it's no longer needed.

**Step 2: Remove nonisolated(unsafe) from dateOnly formatter**

In `Sources/NDKSwiftCore/Utils/DateFormatters.swift:52`, change:
```swift
public nonisolated(unsafe) static let dateOnly: DateFormatter = {
```

To:
```swift
public static let dateOnly: DateFormatter = {
```

Remove the concurrency safety comment block (lines 47-51).

**Step 3: Remove nonisolated(unsafe) from timeOnly formatter**

In `Sources/NDKSwiftCore/Utils/DateFormatters.swift:65`, change:
```swift
public nonisolated(unsafe) static let timeOnly: DateFormatter = {
```

To:
```swift
public static let timeOnly: DateFormatter = {
```

Remove the concurrency safety comment block (lines 60-64).

**Step 4: Build and verify warnings are gone**

Run: `swift build 2>&1 | grep -i "DateFormatters.swift.*nonisolated"`
Expected: No output (warnings eliminated)

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/Utils/DateFormatters.swift
git commit -m "Remove unnecessary nonisolated(unsafe) from Sendable formatters

DateFormatter types are Sendable by default in Swift 6,
making nonisolated(unsafe) unnecessary and triggering warnings."
```

---

## Task 2: Fix NDK Sendable conformance

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/NDK.swift:14`

**Issue:** NDK class is referenced in Sendable contexts but doesn't conform to Sendable. Full Sendable conformance requires extensive refactoring. Use @unchecked Sendable with clear safety documentation.

**Step 1: Add @unchecked Sendable conformance**

In `Sources/NDKSwiftCore/Core/NDK.swift:14`, change:
```swift
public final class NDK {
```

To:
```swift
/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - NDK is designed as a singleton-style coordinator accessed from multiple contexts
/// - Internal state is protected by actors (PendingAuthEventsManager, etc.)
/// - Mutable properties (signer, cache, pool) are thread-safe types or accessed via MainActor
/// - Typical usage pattern: created once, configured early, then used read-only
public final class NDK: @unchecked Sendable {
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | grep "NDKMetaSubscription.*non-Sendable type 'NDK'"`
Expected: No output (warning eliminated)

**Step 3: Commit**

```bash
git add Sources/NDKSwiftCore/Core/NDK.swift
git commit -m "Add @unchecked Sendable conformance to NDK

NDK is used in Sendable contexts (NDKMetaSubscription).
Internal synchronization via actors and MainActor properties
ensures thread-safe usage."
```

---

## Task 3: Fix Ndb class Sendable conformance

**Files:**
- Modify: `Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift`

**Issue:** Ndb class is referenced in Sendable contexts but doesn't conform. Needs @unchecked Sendable with safety documentation.

**Step 1: Find the Ndb class definition**

Run: `grep -n "^public final class Ndb" Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift`

**Step 2: Add @unchecked Sendable conformance**

Add to the Ndb class declaration:
```swift
/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - Underlying ndb pointer is thread-safe C library
/// - Actor-isolated continuations dictionary protects concurrent access
/// - All mutable state managed through actors or atomic operations
public final class Ndb: @unchecked Sendable {
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | grep "NdbNoteLender.*non-Sendable type 'Ndb'"`
Expected: No output (warning eliminated)

**Step 4: Commit**

```bash
git add Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift
git commit -m "Add @unchecked Sendable conformance to Ndb

Ndb wraps thread-safe C library with actor-protected state.
Safe for concurrent access across isolation boundaries."
```

---

## Task 4: Fix NdbNote Sendable conformance

**Files:**
- Modify: `Sources/NDKSwiftNostrDB/NostrDB/NdbNote.swift`

**Issue:** NdbNote is referenced in Sendable contexts but doesn't conform.

**Step 1: Find the NdbNote class definition**

Run: `grep -n "^public final class NdbNote" Sources/NDKSwiftNostrDB/NostrDB/NdbNote.swift`

**Step 2: Add @unchecked Sendable conformance**

Add to the NdbNote class declaration:
```swift
/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - Wraps immutable note data from C library
/// - All operations read-only after initialization
/// - No mutable shared state
public final class NdbNote: @unchecked Sendable {
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | grep "NdbNoteLender.*non-Sendable type 'NdbNote'"`
Expected: No output (warning eliminated)

**Step 4: Commit**

```bash
git add Sources/NDKSwiftNostrDB/NostrDB/NdbNote.swift
git commit -m "Add @unchecked Sendable conformance to NdbNote

NdbNote wraps immutable C data structures.
Read-only after initialization, safe for concurrent access."
```

---

## Task 5: Fix concurrent closure captures in Ndb.swift

**Files:**
- Modify: `Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift:870-915`

**Issue:** @Sendable closure captures and mutates local vars (streaming, terminationStarted, subid). Need actor-based synchronization or immutable captures.

**Step 1: Refactor to use state actor**

In `Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift`, before the problematic function (around line 865), add:
```swift
/// Actor to manage subscription state for concurrent access
private actor SubscriptionState {
    var streaming: Bool = true
    var terminationStarted: Bool = false
    var subid: UInt64 = 0

    func setSubid(_ id: UInt64) {
        subid = id
    }

    func markTerminated() -> Bool {
        if terminationStarted {
            return false  // Already terminated
        }
        terminationStarted = true
        streaming = false
        return true  // First termination
    }

    func getSubid() -> UInt64 {
        return subid
    }
}
```

**Step 2: Replace mutable captures with actor**

In the subscription function (around line 870), replace:
```swift
var streaming = true
var subid: UInt64 = 0
var terminationStarted = false
```

With:
```swift
let state = SubscriptionState()
```

**Step 3: Update termination handler (first occurrence)**

Replace the first `continuation.onTermination` closure (line 876):
```swift
continuation.onTermination = { @Sendable _ in
    guard !terminationStarted else { return }
    terminationStarted = true
    Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
    streaming = false
    if subid != 0 {
        ndb_unsubscribe(self.ndb.ndb, subid)
        Task { await self.unsetContinuation(subscriptionId: subid) }
    }
    filtersPointer.deallocate()
}
```

With:
```swift
continuation.onTermination = { @Sendable _ in
    Task {
        guard await state.markTerminated() else { return }
        Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
        let currentSubid = await state.getSubid()
        if currentSubid != 0 {
            ndb_unsubscribe(self.ndb.ndb, currentSubid)
            await self.unsetContinuation(subscriptionId: currentSubid)
        }
        filtersPointer.deallocate()
    }
}
```

**Step 4: Update streaming check**

Replace (line 889):
```swift
if !streaming {
    return
}
```

With:
```swift
if !(await state.streaming) {
    return
}
```

**Step 5: Update subid assignment**

Replace (line 894):
```swift
subid = ndb_subscribe(self.ndb.ndb, filtersPointer, Int32(filters.count))
```

With:
```swift
let newSubid = ndb_subscribe(self.ndb.ndb, filtersPointer, Int32(filters.count))
await state.setSubid(newSubid)
```

**Step 6: Update second termination handler**

Replace the second `continuation.onTermination` closure (line 904):
```swift
continuation.onTermination = { @Sendable _ in
    guard !terminationStarted else { return }
    terminationStarted = true
    Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
    streaming = false
    continuationSetupTask.cancel()
    Task { await self.unsetContinuation(subscriptionId: subid) }
    filtersPointer.deallocate()
    guard !self.is_closed else { return }
    ndb_unsubscribe(self.ndb.ndb, subid)
}
```

With:
```swift
continuation.onTermination = { @Sendable _ in
    Task {
        guard await state.markTerminated() else { return }
        Log.debug("ndb_wait: stream: Terminated early", for: .ndb)
        continuationSetupTask.cancel()
        let currentSubid = await state.getSubid()
        await self.unsetContinuation(subscriptionId: currentSubid)
        filtersPointer.deallocate()
        guard !self.is_closed else { return }
        ndb_unsubscribe(self.ndb.ndb, currentSubid)
    }
}
```

**Step 7: Update continuation setup**

Replace (line 899):
```swift
let continuationSetupTask = Task {
    await self.setContinuation(for: subid, continuation: continuation)
}
```

With:
```swift
let continuationSetupTask = Task {
    let currentSubid = await state.getSubid()
    await self.setContinuation(for: currentSubid, continuation: continuation)
}
```

**Step 8: Build and verify**

Run: `swift build 2>&1 | grep "Ndb.swift.*concurrently-executing"`
Expected: No output (warnings eliminated)

**Step 9: Commit**

```bash
git add Sources/NDKSwiftNostrDB/NostrDB/Ndb.swift
git commit -m "Fix concurrent closure captures with actor-based state

Replace mutable var captures in @Sendable closures with
actor-protected state to eliminate race conditions and
Swift 6 concurrency warnings."
```

---

## Task 6: Verify all Sendable warnings eliminated

**Step 1: Clean build**

Run: `rm -rf .build && swift build 2>&1 | tee /tmp/final-build.txt`

**Step 2: Check for Sendable warnings**

Run: `grep -i "sendable" /tmp/final-build.txt | grep "warning:"`
Expected: No output

**Step 3: Check for concurrency warnings**

Run: `grep "concurrently-executing" /tmp/final-build.txt`
Expected: No output

**Step 4: Confirm build success**

Run: `tail -5 /tmp/final-build.txt`
Expected: "Build complete!"

**Step 5: Document completion**

If all warnings eliminated, document in commit message for final commit.

---

## Notes

- Tasks 2, 3, 4 use @unchecked Sendable - this is acceptable when underlying implementation is thread-safe but cannot prove it to compiler
- Task 5 is most complex - refactors mutable captures to use actor-based synchronization
- Each task is independent and can be implemented separately
- Test builds after each task to verify warnings are eliminated
- Follow TDD principles where applicable (though most tasks are refactoring, not new features)
