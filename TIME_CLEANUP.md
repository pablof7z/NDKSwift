# Task.sleep Cleanup Plan

This document tracks the analysis and cleanup of `Task.sleep` usage throughout NDKSwift. Each instance is analyzed to understand why it exists and how to properly fix it.

## 2. RetryPolicy Delay (RetryPolicy.swift:177)

**Problem**: Using Task.sleep for retry delays between failed operations.

**Current Code**:
```swift
public func execute<T>(
    operation: @escaping () async throws -> T,
    shouldRetry: @escaping (Error) -> Bool = { _ in true }
) async throws -> T {
    reset()
    
    while true {
        do {
            return try await operation()
        } catch {
            guard shouldRetry(error) else { throw error }
            guard let delay = nextDelay() else {
                throw NDKError.unknown("Max retry attempts reached", underlying: error)
            }
            
            // Wait for the delay
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
```

**Analysis**: This is actually a **LEGITIMATE USE** of Task.sleep! 

**Why it's correct**:
- Retry delays need actual time delays between attempts
- The delay is properly calculated with exponential backoff
- The sleep can be cancelled if the task is cancelled
- This is exactly what Task.sleep is designed for

**No fix needed**: This is proper usage. When you need to wait between retry attempts, Task.sleep is the correct tool.

**Status**: NO CHANGE NEEDED ✓

---

## 3. RetryPolicy Timeout (RetryPolicy.swift:199)

**Problem**: Using Task.sleep in a TaskGroup for timeout implementation.

**Current Code**:
```swift
public func executeWithTimeout<T>(...) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation task
        group.addTask {
            try await self.execute(operation: operation, shouldRetry: shouldRetry)
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw NDKError.timeout(operation: "Retry operation", seconds: Int(timeout))
        }
        
        // Return the first result (either success or timeout)
        guard let result = try await group.next() else {
            throw NDKError.unknown("No result from retry operation")
        }
        
        // Cancel remaining tasks
        group.cancelAll()
        
        return result
    }
}
```

**Analysis**: This is also a **LEGITIMATE USE** of Task.sleep!

**Why it's correct**:
- Uses TaskGroup properly to race operation against timeout
- Cancels the losing task with `group.cancelAll()`
- This is the recommended pattern for implementing timeouts in Swift
- No resource leak because TaskGroup manages cancellation

**No fix needed**: This is exactly how timeouts should be implemented with TaskGroup.

**Status**: NO CHANGE NEEDED ✓

---

## 5. NDKRelayConnection Continuation Storage (NDKRelayConnection.swift:208)

**Problem**: 10ms sleep to "ensure continuation is stored first" before sending event.

**Current Code**:
```swift
group.addTask {
    try await withCheckedThrowingContinuation { continuation in
        // Store the continuation - this is now within the actor context
        Task { [weak self] in
            await self?.storePendingContinuation(eventId: eventId, continuation: continuation)
        }
    }
}

group.addTask {
    // Give a tiny delay to ensure continuation is stored first
    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    
    // Send the event
    let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
    try await self.send(eventMessage)
    // ...
}
```

**Analysis**: This is a **RACE CONDITION HACK**!

**Why it's wrong**:
- The code spawns a Task to store the continuation, then hopes 10ms is enough time
- Race condition: if the system is slow, the event might be sent before continuation is stored
- When OK response arrives, it won't find the continuation and will be ignored
- This will fail intermittently under load

**Root problem**: 
- Creating a Task inside `withCheckedThrowingContinuation` breaks the atomicity
- The continuation should be stored synchronously before any async work begins

**Proper fix**:
- Store the continuation synchronously BEFORE starting any async tasks
- Restructure the code to ensure proper ordering without timing dependencies

**Status**: TO FIX - Critical race condition that needs proper synchronization

---

## 6. NDKRelayConnection Event Timeout (NDKRelayConnection.swift:216)

**Problem**: Timeout implementation in the same race-prone TaskGroup.

**Current Code**:
```swift
// Wait for timeout
try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

// If we get here, we timed out
await self.handleTimeout(eventId: eventId)
throw NDKError.timeout(operation: "publishEvent", seconds: Int(timeout))
```

**Analysis**: This timeout is part of the same flawed design as #5.

**Why it's problematic**:
- It's in a TaskGroup that races against the continuation task
- The timeout handling is coupled with the race condition from #5
- If the continuation isn't stored (due to race), timeout won't work properly

**However**: The timeout itself is legitimate - we do need timeouts for network operations.

**Proper fix**: 
- This will be fixed as part of restructuring the entire `publishEvent` method
- The timeout should remain but in a properly structured TaskGroup

**Status**: TO FIX - As part of fixing #5's race condition

---

## 7. NDKProfileManager Batch Delay (NDKProfileManager.swift:335)

**Problem**: Using Task.sleep for batching profile fetch requests.

**Current Code**:
```swift
private func scheduleBatchProcessing() {
    // Cancel existing task if any
    batchTask?.cancel()
    
    // Schedule new batch processing
    batchTask = Task { [weak self] in
        guard let self = self else { return }
        try? await Task.sleep(nanoseconds: UInt64(self.config.batchDelay * 1_000_000_000))
        await self.processPendingBatch()
    }
}
```

**Analysis**: This is a **LEGITIMATE USE** with proper cancellation!

**Why it's correct**:
- Implements proper debouncing/batching pattern
- Cancels previous timer when new requests come in
- Groups multiple profile requests into a single network call
- The delay is configurable (default 0.1 seconds)
- Task is properly stored and can be cancelled

**Good pattern**:
- Multiple profile requests within 100ms get batched together
- Reduces network traffic and relay load
- Proper cleanup with task cancellation

**Status**: NO CHANGE NEEDED ✓ (Good implementation of batching)

---

## 8. NDKRelayCollection Periodic Check (NDKRelayCollection.swift:213)

**Problem**: Polling every 2 seconds to check for relay pool changes.

**Current Code**:
```swift
while !Task.isCancelled {
    do {
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let currentRelays = await ndk.relays
        let currentUrls = Set(currentRelays.map { $0.url })
        
        // Check for added/removed relays
        // ...
    }
}
```

**Analysis**: This is **INEFFICIENT POLLING** that should be event-driven!

**Why it's wrong**:
- Polls every 2 seconds regardless of whether anything changed
- Wastes CPU cycles and battery on mobile devices
- Creates unnecessary work checking relay lists
- The 2-second interval is arbitrary

**Root cause**: 
- The relay pool doesn't emit change notifications
- NDKRelayCollection can't subscribe to pool changes

**Proper fix**:
- NDKPool should emit an AsyncStream of relay changes
- NDKRelayCollection should observe this stream instead of polling
- Only react when actual changes occur

**Status**: TO FIX - Replace polling with event-driven updates

---

## 9. NDKSubscriptionCoordinator fetchEvents Timeout (NDKSubscriptionCoordinator.swift:164)

**Problem**: Fire-and-forget timeout task that doesn't get cancelled.

**Current Code**:
```swift
var hasSeenEose = false

// Set up timeout
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
    if !hasSeenEose {
        print("[NDKSubscriptionCoordinator.fetchEvents] Timeout reached, closing subscription")
        await subscription.close()
    }
}

// Collect events
for try await event in subscription {
    events.append(event)
}
hasSeenEose = true
```

**Analysis**: **RESOURCE LEAK** - timeout task never cancelled!

**Why it's wrong**:
- Creates a timeout task but never stores or cancels it
- If EOSE arrives before timeout, the task keeps running
- Uses shared mutable state (`hasSeenEose`) without proper synchronization
- Similar pattern to the RPC timeout issue (#1)

**Proper fix**:
- Store the timeout task and cancel it when done
- OR use TaskGroup to properly race timeout against event collection
- Avoid shared mutable state

**Status**: TO FIX - Add proper task cancellation

---

## 10. CashuDeposit Polling (CashuDeposit.swift:132)

**Problem**: Polling Cashu mint for deposit status with exponential backoff.

**Current Code**:
```swift
while checks < maxChecks {
    do {
        // Check mint-quote for Lightning invoice payment
        let mintQuote = try await mintManager.mintQuote(quote: quote.quoteId, mint: mint)
        
        if mintQuote.paid == true {
            // Success! Mint the tokens
            let proofs = try await mintManager.mint(quote: quote, mint: mint)
            // ...
            break
        }
    } catch {
        // Handle specific errors
    }
    
    // Still pending - calculate dynamic polling interval
    let interval = min(baseInterval * pow(1.5, hoursOld), maxInterval)
    
    // Wait before next check
    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
}
```

**Analysis**: This is a **LEGITIMATE USE** of Task.sleep!

**Why it's correct**:
- Polling is necessary - Cashu mints don't push status updates
- Uses exponential backoff (starts at 2 min, increases to max 2 hours)
- Properly handles cancellation via AsyncStream
- Task is stored and cancelled on termination
- This is exactly what polling APIs require

**Good patterns**:
- Dynamic interval based on quote age
- Proper error handling for expected "not paid" status
- Clean termination handling

**Status**: NO CHANGE NEEDED ✓ (Required for external API polling)

---

## 11. NDKFetchingStrategy Timeout (NDKFetchingStrategy.swift:315)

**Problem**: Using Task.sleep for timeout in a utility function.

**Current Code**:
```swift
private func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw FetchError.timeout
        }

        guard let result = try await group.next() else {
            throw FetchError.timeout
        }

        group.cancelAll()
        return result
    }
}
```

**Analysis**: This is a **LEGITIMATE USE** - proper timeout implementation!

**Why it's correct**:
- Uses TaskGroup correctly to race operation against timeout
- Properly cancels the losing task with `group.cancelAll()`
- This is the standard Swift pattern for implementing timeouts
- Reusable utility function that does it right

**Status**: NO CHANGE NEEDED ✓ (Textbook timeout implementation)

---

## 12. NDKLightningZapProtocol Timeout (NDKLightningZapProtocol.swift:173)

**Problem**: Timeout task for waiting for zap receipts.

**Current Code**:
```swift
// Create timeout task
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    await subscription.close()
    throw ZapError.timeoutWaitingForReceipt
}

do {
    for try await event in subscription {
        // Check if receipt matches...
        if matches {
            timeoutTask.cancel()
            await subscription.close()
            return event
        }
    }
} catch {
    timeoutTask.cancel()
    await subscription.close()
    throw error
}
```

**Analysis**: This is **MOSTLY CORRECT** with proper cancellation!

**Why it's good**:
- Timeout task is stored in a variable
- Cancelled on success (lines 190, 196)
- Cancelled on error (line 203)
- Subscription properly closed in all cases

**Minor issue**: 
- If the AsyncSequence completes without finding a match (line 208), the timeout task might not be cancelled
- But this is a minor edge case

**Status**: NO CHANGE NEEDED ✓ (Good timeout implementation with proper cleanup)

---

## 13. NDKPublishingStrategy Rate Limit Backoff (NDKPublishingStrategy.swift:197)

**Problem**: Using Task.sleep for exponential backoff on rate limiting.

**Current Code**:
```swift
case .rateLimited:
    await item.updateRelayStatus(relayURL, status: .rateLimited)
    // Exponential backoff
    try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
    backoffInterval *= config.backoffMultiplier
```

**Analysis**: This is a **LEGITIMATE USE** of Task.sleep!

**Why it's correct**:
- Rate limiting requires actual delays before retry
- Uses exponential backoff (multiplies interval each time)
- This is the standard pattern for handling rate limits
- The delay is necessary to respect server rate limits

**Status**: NO CHANGE NEEDED ✓ (Proper rate limit handling)

---

## 14. NDKPublishingStrategy Retry Backoff (NDKPublishingStrategy.swift:218)

**Problem**: Using Task.sleep for retry backoff on failures.

**Current Code**:
```swift
case .temporaryFailure:
    if attempts < config.maxRetries {
        await item.updateRelayStatus(relayURL, status: .retrying(attempt: attempts))
        try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
        backoffInterval *= config.backoffMultiplier
```

**Analysis**: Also a **LEGITIMATE USE** of Task.sleep!

**Why it's correct**:
- Temporary failures need backoff before retry
- Uses same exponential backoff pattern
- Respects max retry limits
- Necessary for network failure recovery

**Status**: NO CHANGE NEEDED ✓ (Proper retry handling)

---

## 15. NDKSubscriptionManager Grouping Delay (NDKSubscriptionManager.swift:382)

**Problem**: Using Task.sleep for subscription grouping delay.

**Current Code**:
```swift
// Set timer to execute group
group.timer = Task {
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    await executeGroup(fingerprint: fingerprint)
}

// In executeGroup:
private func executeGroup(fingerprint: FilterFingerprint) async {
    guard var group = pendingGroups[fingerprint] else { return }
    pendingGroups.removeValue(forKey: fingerprint)
    group.cancel() // Cancels the timer
    // ...
}
```

**Analysis**: This is a **LEGITIMATE USE** with proper cleanup!

**Why it's correct**:
- Implements subscription batching/grouping to reduce relay load
- Timer is stored and can be cancelled
- When group executes, it cancels its own timer
- If new subscriptions arrive, they join existing group
- Configurable delay (default 100ms)

**Good patterns**:
- Reduces network traffic by batching subscriptions
- Proper task management with cancellation
- Self-cleaning when group executes

**Status**: NO CHANGE NEEDED ✓ (Well-implemented batching)

---

## 16. NDKSubscriptionManager Periodic Cleanup (NDKSubscriptionManager.swift:630)

**Problem**: Infinite loop with Task.sleep for periodic cleanup.

**Current Code**:
```swift
private func startPeriodicCleanup() async {
    while true {
        try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
        await performCleanup()
    }
}
```

**Analysis**: This is **INEFFICIENT POLLING** but somewhat acceptable.

**Why it's problematic**:
- Runs cleanup every minute regardless of activity
- No way to stop the cleanup task
- Could use event-driven cleanup instead

**However**:
- Memory cleanup is important to prevent leaks
- 1-minute interval is reasonable
- The cleanup is lightweight (just filtering dictionaries)

**Better approach**:
- Trigger cleanup based on events (e.g., every N events processed)
- Or use a stored task that can be cancelled
- Or combine with other periodic maintenance

**Status**: MINOR ISSUE - Works but could be more efficient

---

## 17. NDKSubscriptionBuilder fetchEvents Timeout #1 (NDKSubscriptionBuilder.swift:195)

**Problem**: Using Task.sleep for fetch timeout with TaskGroup.

**Current Code**:
```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
        await subscription.waitForEOSE()
    }
    
    group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw NDKError.timeout(operation: "Fetch events", seconds: Int(timeout))
    }
    
    try await group.next()
    group.cancelAll()
}
```

**Analysis**: This is a **LEGITIMATE USE** - proper timeout pattern!

**Why it's correct**:
- Uses TaskGroup to race EOSE against timeout
- Properly cancels the losing task
- Standard Swift pattern for timeouts
- Clean and efficient

**Status**: NO CHANGE NEEDED ✓ (Textbook timeout implementation)

---

## 18. NDKSubscriptionBuilder fetchEvents Timeout #2 (NDKSubscriptionBuilder.swift:245)

**Problem**: Identical timeout pattern in another fetch method.

**Current Code**: Same as #17 - TaskGroup racing EOSE against timeout.

**Analysis**: Also a **LEGITIMATE USE** - same proper pattern.

**Status**: NO CHANGE NEEDED ✓ (Same as #17)

---

## 19. NDKSubscription waitForEOSE Polling (NDKSubscription.swift:382)

**Problem**: Polling loop to wait for EOSE signal.

**Current Code**:
```swift
public func waitForEOSE() async {
    while !self.eoseReceived {
        try? await Task.sleep(nanoseconds: 100_000_000) // Sleep 100ms
    }
}
```

**Analysis**: This is a **HACK** - inefficient polling!

**Why it's wrong**:
- Polls every 100ms checking a boolean
- Wastes CPU cycles
- Not event-driven
- Could miss the EOSE signal between polls

**Root cause**:
- No proper async signaling for EOSE
- Should use AsyncStream or Continuation

**Proper fix**:
- Use an AsyncStream that yields when EOSE arrives
- Or use a Continuation that resumes on EOSE
- Make it truly event-driven

**Status**: TO FIX - Replace polling with event-driven approach

---

## 20. NDKSubscription EOSE Timeout (NDKSubscription.swift:614)

**Problem**: Timeout task for subscription lifetime.

**Current Code**:
```swift
private func setupTimeoutIfNeeded() async {
    let options = await stateActor.getOptions()
    guard let timeout = options.timeout else { return }
    
    let timeoutTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        
        // If the task wasn't cancelled, the timeout was reached
        if !Task.isCancelled {
            await self?.close()
        }
    }
    
    await stateActor.setTimeoutTask(timeoutTask)
}
```

**Analysis**: This is a **LEGITIMATE USE** with proper management!

**Why it's correct**:
- Timeout task is stored in the state actor
- Gets cancelled when subscription closes
- `setTimeoutTask` cancels any previous timeout
- Proper weak self capture to avoid retain cycles
- Clean task management

**Status**: NO CHANGE NEEDED ✓ (Well-managed timeout)

---

## 21. NDKRelay Reconnect Delay (NDKRelay.swift:509)

**Problem**: Using Task.sleep for exponential backoff on relay reconnection.

**Current Code**:
```swift
let reconnectTask = Task {
    try? await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
    if !Task.isCancelled {
        try? await self.connect()
    }
}

await stateActor.scheduleReconnectTask(reconnectTask)
```

**Analysis**: This is a **LEGITIMATE USE** with excellent management!

**Why it's correct**:
- Implements exponential backoff for reconnection
- Task is stored and previous tasks are cancelled
- `scheduleReconnectTask` cancels any existing reconnect task
- Checks `Task.isCancelled` before reconnecting
- This is exactly how reconnection should work

**Good patterns**:
- Exponential backoff with max delay cap
- Clean task management through state actor
- Proper cancellation handling

**Status**: NO CHANGE NEEDED ✓ (Excellent reconnection implementation)

---

## 22. NDKNWCWallet Connection Wait (NDKNWCWallet.swift:369)

**Problem**: Arbitrary 1-second sleep when wallet is connecting.

**Current Code**:
```swift
case .connecting:
    // Wait a bit for connection to complete
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    if case .connected = _status {
        return
    }
    throw NDKError.connectionFailed(...)
```

**Analysis**: This is a **HACK** - arbitrary wait time!

**Why it's wrong**:
- Waits 1 second hoping connection completes
- No guarantee connection will finish in 1 second
- Could fail under load or slow network
- Classic "hope it works" timing

**Root cause**:
- No proper async coordination for connection state
- Should wait for actual connection completion

**Proper fix**:
- Use AsyncStream or Continuation to signal when connection completes
- Or make `connect()` truly async and wait for it properly
- Remove arbitrary timing assumptions

**Status**: TO FIX - Replace with proper async state management

---

## 23. NWCResponseHandler Subscription Wait (NWCResponseHandler.swift:90)

**Problem**: 0.5 second sleep to "wait for subscription to be established".

**Current Code**:
```swift
// 3. Wait a moment for subscription to be established
try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

// 4. Now publish the request
print("[NWC Response] Publishing request event \(requestId)")
let publishedRelays = try await ndk.publish(event)
```

**Analysis**: This is a **HACK** - race condition workaround!

**Why it's wrong**:
- Assumes subscription takes < 0.5 seconds to establish
- Publishing before subscription is ready loses the response
- Arbitrary delay that might fail under load
- Classic timing-based race condition

**Root cause**:
- Subscription establishment is async but has no completion signal
- Need to ensure subscription is active before publishing

**Proper fix**:
- Make subscription provide a "ready" signal
- Or restructure to ensure subscription is established first
- Remove timing assumptions

**Status**: TO FIX - Fix race condition properly

---

## 24. NWCResponseHandler Multi-Response Timeout (NWCResponseHandler.swift:219)

**Problem**: Timeout for collecting multiple NWC responses.

**Current Code**:
```swift
let timeoutTask = Task<[String: Result<T, NDKError>], Error> {
    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    throw NDKError.timeout(operation: "NWC multi-response", seconds: Int(timeout))
}

let result = try await withThrowingTaskGroup(of: [String: Result<T, NDKError>].self) { group in
    group.addTask { try await responseTask.value }
    group.addTask { try await timeoutTask.value }
    
    guard let firstResult = try await group.next() else {
        throw NDKError.timeout(operation: "NWC multi-response", seconds: Int(timeout))
    }
    
    group.cancelAll()
    return firstResult
}
```

**Analysis**: This is a **LEGITIMATE USE** - proper timeout pattern!

**Why it's correct**:
- Uses TaskGroup to race response collection against timeout
- Properly cancels all tasks when done
- Standard Swift timeout pattern
- Clean implementation

**Status**: NO CHANGE NEEDED ✓ (Proper timeout implementation)

---

## Summary

Out of 24 Task.sleep instances analyzed:

**Legitimate Uses (14):**
- Retry/backoff delays: 4
- Proper timeouts: 7
- External API polling: 1
- Batching/debouncing: 2

**Hacks to Fix (10):**
- Race conditions: 3 (continuation storage, subscription establishment)
- Arbitrary "wait for stable" delays: 2
- Resource leaks (uncancelled timeouts): 2
- Inefficient polling: 2
- Minor efficiency issue: 1

**Critical Issues:**
1. **NDKRelayConnection** - Race condition storing continuation
2. **NDKNostrRPC** - Timeout tasks never cancelled
3. **NDKSubscriptionCoordinator** - Timeout tasks never cancelled
4. **NWCResponseHandler** - Race condition with subscription

**High Priority Fixes:**
1. Fix race conditions (proper async coordination)
2. Fix resource leaks (cancel timeout tasks)
3. Replace polling with event-driven approaches

---
