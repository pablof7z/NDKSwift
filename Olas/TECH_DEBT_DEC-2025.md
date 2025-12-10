# Olas iOS Technical Debt Report - December 2025

## Executive Summary

The Olas codebase is functional but has accumulated significant technical debt. The most critical issues are **massive code duplication** between PostCard and VideoPostCard, **inconsistent architecture patterns**, and **violation of the project's own CLAUDE.md guidelines** (particularly around ViewModels and @Observable usage).

---

## ✅ RESOLVED Issues

### ~~2. Architecture Violations: ObservableObject vs @Observable~~ [RESOLVED]

**Resolution:** All classes have been migrated to use the `@Observable` macro:

| Class | Pattern Used | Status |
|-------|-------------|--------|
| `SparkWalletManager` | `@Observable` | ✅ Migrated |
| `AuthViewModel` | `@Observable` | ✅ Migrated |
| `WalletViewModel` | `@Observable` | ✅ Migrated |
| `FeedViewModel` | `@Observable` | ✅ Migrated |
| `MuteListManager` | `@Observable` | ✅ Migrated |
| `SettingsManager` | `@Observable` | ✅ Migrated |
| `RelayMetadataCache` | `@Observable` | ✅ Migrated |
| `MintDiscoveryViewModel` | `@Observable` | ✅ Migrated |
| `CollectionsManager` | `@Observable` | ✅ Already correct |

All view call sites have been updated from `@StateObject`/`@ObservedObject`/`@EnvironmentObject` to `@State`/`@Environment`.

---

### ~~3. Keychain Code Duplication~~ [RESOLVED]

**Resolution:** Created `Utilities/KeychainService.swift` - a shared enum-based utility:

```swift
enum KeychainService {
    enum Account: String {
        case userNsec = "user_nsec"
        case sparkMnemonic = "spark_mnemonic"
    }

    static func save(_ value: String, for account: Account) throws
    static func load(for account: Account) -> String?
    static func delete(for account: Account)
    static func exists(for account: Account) -> Bool
}
```

Both `AuthViewModel` and `SparkWalletManager` now use this shared service, eliminating ~100 lines of duplicated keychain code.

---

### ~~8. Singleton + ObservableObject Anti-Pattern~~ [RESOLVED]

**Resolution:** `SettingsManager` now uses `@Observable` macro and views access it with `@State` instead of `@StateObject`. The singleton pattern is correctly handled - singletons with `@Observable` work properly because the observation tracking is property-based, not lifecycle-based.

---

## 🔴 HIGH PRIORITY Issues

### 1. Massive Code Duplication: PostCard vs VideoPostCard

**Files:** `Views/Components/PostCard.swift` (526 lines), `Views/Components/VideoPostCard.swift` (445 lines)

**Problem:** ~70% of these two files are nearly identical copy-pasted code:

| Function/Component | PostCard Lines | VideoPostCard Lines | Identical? |
|-------------------|----------------|---------------------|------------|
| `postHeader` | 76-126 | 56-106 | ✅ 99% identical |
| `profilePictureButton` | 128-138 | 108-118 | ✅ Identical |
| `postActions` | 205-239 | 210-230 | ✅ Very similar |
| `postCaption` | 253-275 | 232-254 | ✅ Identical |
| `handleDoubleTap()` | 277-295 | 291-305 | ✅ Nearly identical |
| `toggleLike()` | 297-309 | 307-318 | ✅ Nearly identical |
| `publishReaction()` | 311-328 | 320-336 | ✅ Identical |
| `loadReactions()` | 330-335 | 338-342 | ✅ Identical |
| `loadReactionCount()` | 337-355 | 344-360 | ✅ Identical |
| `loadCommentCount()` | 357-375 | 363-380 | ✅ Identical |
| `muteAuthor()` | 377-386 | 382-388 | ✅ Identical |
| `copyEventId()` | 388-396 | 390-398 | ✅ Identical |
| `PostCaptionText` / `VideoCaptionText` | 399-438 | 407-445 | ✅ Identical |

**Impact:** Any bug fix or feature addition requires changes in both files. High risk of divergence.

**Recommended Fix:** Extract shared logic into composition-based components. See dedicated refactoring plan.

---

## 🟡 MEDIUM PRIORITY Issues

### 4. Business Logic in View Layer

**Per CLAUDE.md:** *"Display functions only display - if you're adding business logic to display code, STOP"*

**Problem:** Views directly publish Nostr events and manage subscriptions:

| File | Function | Issue |
|------|----------|-------|
| `PostCard.swift:311-328` | `publishReaction()` | Publishes events to network |
| `PostCard.swift:337-375` | `loadReactionCount()`, `loadCommentCount()` | Manages NDK subscriptions |
| `VideoPostCard.swift:320-336` | Same pattern | Duplicated |

**Impact:** Tight coupling between UI and network layer. Harder to test. Duplicated logic.

**Recommended Fix:** Extract to a `ReactionService` or similar that handles reaction state and publishing.

---

### 5. SparkWalletManager Over-Abstraction

**File:** `ViewModels/SparkWalletManager.swift` (394 lines - reduced from 450)

**Problems:**
1. **Duplicates SparkWallet state** - Manager has observable properties that mirror SparkWallet's internal state
2. **Many observable properties** - Too much UI state in one class
3. **Formatting methods** wrap `SatsConverter` but add no value
4. **Mixed concerns** - Business logic (wallet ops), UI state (fiat rates), and persistence (now uses KeychainService)

**Impact:** Hard to maintain, test, or modify wallet behavior.

**Recommended Fix:**
- Use `SparkWallet` actor directly where possible
- Keep only truly UI-specific state in manager

---

### 6. Legacy Theme Color Aliases

**File:** `Utils/Theme.swift:18-21`

```swift
// Legacy aliases - mapped to new brand colors
public static let deepTeal = Color(hex: "F97316")   // ← This is ORANGE, not teal
public static let oceanBlue = Color(hex: "EA580C")  // ← This is ORANGE, not blue
public static let seafoam = Color.secondary         // ← Not seafoam green
```

**Problem:** Color names don't match their values. Confusing for anyone reading the code.

**Recommended Fix:** Remove legacy aliases, find/replace all usages to accurate names (`brandPrimary`, `brandSecondary`, etc.).

---

### 7. NotificationCenter Observer Leak

**File:** `VideoPostCard.swift:268-275`

```swift
private func setupPlayer() {
    NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
    ) { _ in
        avPlayer.seek(to: .zero)
        avPlayer.play()
    }
    // Never removed!
}
```

**Impact:** Potential memory leak. Observer persists after view disappears.

**Recommended Fix:** Store observer token and remove in `onDisappear` or use Combine publisher.

---

### 9. Task Cancellation Inconsistency

Different patterns used across the codebase:

```swift
// Pattern A - Nil after cancel
subscriptionTask?.cancel()
subscriptionTask = nil

// Pattern B - Just cancel
eventTask?.cancel()

// Pattern C - No cancellation handling
// (some views don't cancel tasks on disappear)
```

**Impact:** Potential for orphaned tasks, inconsistent cleanup.

**Recommended Fix:** Standardize on Pattern A throughout codebase.

---

## 🟢 LOW PRIORITY Issues

### 10. Silent Error Handling

Multiple locations swallow errors without logging or user feedback:

| Location | Issue |
|----------|-------|
| `ImageCache.swift:45` | Silent fail on image download |
| `SparkWalletManager.swift:274` | Silent fail for fiat rate |
| `MuteListManager.swift` | Mute operations fail silently |
| `PostCard.swift:384` | Mute fails silently |

**Recommended Fix:** At minimum, log errors. Consider toast/snackbar for user-facing failures.

---

### 11. Magic String Constants

Keychain services now centralized in `KeychainService.swift` with proper enum-based account keys. ✅ Partially resolved.

---

### 12. FullscreenImageViewer Should Be Separate File

**File:** `PostCard.swift:440-526`

87-line component embedded at bottom of PostCard file.

**Recommended Fix:** Extract to `Views/Components/FullscreenImageViewer.swift` for reusability.

---

## Priority Matrix

| Priority | Issue | Effort | Impact | Status |
|----------|-------|--------|--------|--------|
| 🔴 HIGH | PostCard/VideoPostCard duplication | Medium | High | Pending |
| ~~🔴 HIGH~~ | ~~ObservableObject → @Observable~~ | ~~Medium~~ | ~~High~~ | ✅ RESOLVED |
| ~~🔴 HIGH~~ | ~~Keychain code duplication~~ | ~~Low~~ | ~~Medium~~ | ✅ RESOLVED |
| 🟡 MEDIUM | Business logic in views | Medium | Medium | Pending |
| 🟡 MEDIUM | SparkWalletManager complexity | High | Medium | Partial |
| 🟡 MEDIUM | Legacy theme color names | Low | Low | Pending |
| 🟡 MEDIUM | NotificationCenter leak | Low | Medium | Pending |
| ~~🟡 MEDIUM~~ | ~~Singleton + StateObject pattern~~ | ~~Low~~ | ~~Low~~ | ✅ RESOLVED |
| 🟡 MEDIUM | Task cancellation inconsistency | Low | Low | Pending |
| 🟢 LOW | Silent error handling | Medium | Low | Pending |
| ~~🟢 LOW~~ | ~~Magic strings~~ | ~~Low~~ | ~~Low~~ | ✅ Partial |
| 🟢 LOW | File organization | Low | Low | Pending |

---

## Metrics (Updated)

- **Total Swift files in Olas:** 57 (+1 for KeychainService)
- **Lines in PostCard.swift:** 526
- **Lines in VideoPostCard.swift:** 445
- **Estimated duplicated lines:** ~350
- **Classes using ObservableObject (should be @Observable):** 0 ✅
- **Classes correctly using @Observable:** 9 ✅

---

## Next Steps

1. **Immediate:** Fix PostCard/VideoPostCard duplication (see dedicated plan)
2. ~~**Short-term:** Migrate ObservableObject → @Observable across all managers~~ ✅ DONE
3. ~~**Short-term:** Extract KeychainService utility~~ ✅ DONE
4. **Medium-term:** Extract reaction/comment logic from views
5. **Medium-term:** Simplify SparkWalletManager

---

*Report generated: December 2025*
*Last updated: December 2025 - Resolved keychain duplication and @Observable migration*
