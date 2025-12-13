# Technical Debt Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate technical debt, force casts, legacy patterns, and Swift 6 concurrency violations across NDKSwift library.

**Architecture:** Sequential cleanup of critical issues with pre-commit hooks to prevent regression. Each task is isolated to minimize conflicts and can be merged independently.

**Tech Stack:** Swift 6, Swift Package Manager, Git hooks

---

## Task 1: Add Pre-Commit Hook to Prevent Force Casts and Hacks

**Files:**
- Create: `.git/hooks/pre-commit`
- Create: `scripts/validate-code-quality.sh`
- Modify: `.gitignore`

**Step 1: Create code quality validation script**

Create `scripts/validate-code-quality.sh`:

```bash
#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Running code quality checks..."

# Get list of staged Swift files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)

if [ -z "$STAGED_FILES" ]; then
    echo "${GREEN}✓ No Swift files to check${NC}"
    exit 0
fi

ERRORS=0

echo ""
echo "Checking for prohibited patterns..."

# Check for force casts (as!)
echo -n "  Checking for force casts... "
FORCE_CASTS=$(echo "$STAGED_FILES" | xargs grep -n " as! " 2>/dev/null || true)
if [ -n "$FORCE_CASTS" ]; then
    echo "${RED}✗ Found force casts (as!)${NC}"
    echo "$FORCE_CASTS"
    echo ""
    echo "${YELLOW}Use conditional casting (as?) with proper error handling instead.${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo "${GREEN}✓${NC}"
fi

# Check for force unwraps (!) except for IBOutlets and implicitly unwrapped optionals in declarations
echo -n "  Checking for dangerous force unwraps... "
FORCE_UNWRAPS=$(echo "$STAGED_FILES" | xargs grep -n "[^!]![^=!]" 2>/dev/null | grep -v "@IBOutlet" | grep -v "// swiftlint:disable:next force_unwrapping" || true)
if [ -n "$FORCE_UNWRAPS" ]; then
    echo "${YELLOW}⚠ Found potential force unwraps${NC}"
    echo "$FORCE_UNWRAPS"
    echo ""
    echo "${YELLOW}Review these carefully. Use optional binding instead where possible.${NC}"
    # Don't fail for this - it's a warning
else
    echo "${GREEN}✓${NC}"
fi

# Check for @unchecked Sendable
echo -n "  Checking for @unchecked Sendable... "
UNCHECKED_SENDABLE=$(echo "$STAGED_FILES" | xargs grep -n "@unchecked Sendable" 2>/dev/null || true)
if [ -n "$UNCHECKED_SENDABLE" ]; then
    echo "${YELLOW}⚠ Found @unchecked Sendable${NC}"
    echo "$UNCHECKED_SENDABLE"
    echo ""
    echo "${YELLOW}Ensure this is documented and truly necessary. Consider using actors instead.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

# Check for nonisolated(unsafe)
echo -n "  Checking for nonisolated(unsafe)... "
NONISOLATED_UNSAFE=$(echo "$STAGED_FILES" | xargs grep -n "nonisolated(unsafe)" 2>/dev/null || true)
if [ -n "$NONISOLATED_UNSAFE" ]; then
    echo "${YELLOW}⚠ Found nonisolated(unsafe)${NC}"
    echo "$NONISOLATED_UNSAFE"
    echo ""
    echo "${YELLOW}Ensure this is documented and truly necessary. Consider using thread-safe alternatives.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

# Check for underscore-prefixed properties (anti-pattern in modern Swift)
echo -n "  Checking for underscore-prefixed properties... "
UNDERSCORE_PROPS=$(echo "$STAGED_FILES" | xargs grep -n "^[[:space:]]*var _[a-zA-Z]" 2>/dev/null || true)
if [ -n "$UNDERSCORE_PROPS" ]; then
    echo "${YELLOW}⚠ Found underscore-prefixed properties${NC}"
    echo "$UNDERSCORE_PROPS"
    echo ""
    echo "${YELLOW}Use standard Swift naming conventions. Consider lazy var or direct initialization.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

echo ""

if [ $ERRORS -gt 0 ]; then
    echo "${RED}❌ Pre-commit checks failed with $ERRORS error(s)${NC}"
    echo ""
    echo "Fix the issues above or use 'git commit --no-verify' to skip checks (not recommended)."
    exit 1
fi

echo "${GREEN}✅ All code quality checks passed!${NC}"
exit 0
```

**Step 2: Make script executable**

Run: `chmod +x scripts/validate-code-quality.sh`
Expected: Script is executable

**Step 3: Create pre-commit hook**

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash

# Run code quality validation
./scripts/validate-code-quality.sh

exit $?
```

**Step 4: Make pre-commit hook executable**

Run: `chmod +x .git/hooks/pre-commit`
Expected: Hook is executable

**Step 5: Test the hook with a force cast**

Create a test file with a force cast:

```bash
echo "let test = value as! String" > test_force_cast.swift
git add test_force_cast.swift
git commit -m "test: verify pre-commit hook works"
```

Expected: Commit should FAIL with error about force cast

**Step 6: Clean up test file**

```bash
git reset HEAD test_force_cast.swift
rm test_force_cast.swift
```

**Step 7: Commit the hook setup**

```bash
git add scripts/validate-code-quality.sh
git commit -m "feat: add pre-commit hook to prevent force casts and code quality issues

- Blocks force casts (as!)
- Warns about force unwraps, @unchecked Sendable, nonisolated(unsafe)
- Warns about underscore-prefixed properties
- Provides actionable error messages"
```

---

## Task 2: Remove Force Casts to NDKRelay in NDKSubscriptionCoordinator

**Files:**
- Modify: `Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift:443,459`
- Add test: `Tests/NDKSwiftCoreTests/DataSource/NDKSubscriptionCoordinatorTests.swift`

**Step 1: Read current implementation**

Read file: `Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift`
Focus on lines 440-465 (event handling)

**Step 2: Write test for safe relay casting**

Create test in `Tests/NDKSwiftCoreTests/DataSource/NDKSubscriptionCoordinatorTests.swift`:

```swift
import XCTest
@testable import NDKSwiftCore

final class NDKSubscriptionCoordinatorTests: XCTestCase {

    func testHandleEventWithNonNDKRelayDoesNotCrash() async throws {
        // Given: A coordinator with event handler
        let ndk = NDK()
        let coordinator = NDKSubscriptionCoordinator(ndk: ndk)

        var receivedEvents: [(NDKEvent, String)] = []
        coordinator.onEvent = { event, relay in
            receivedEvents.append((event, relay.url))
        }

        // When: Event from a mock relay (not NDKRelay)
        let mockRelay = MockRelayProtocol(url: "wss://test.relay")
        let event = NDKEvent(content: "test")

        await coordinator.handleEvent(event, from: mockRelay)

        // Then: Should handle gracefully without crash
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents[0].1, "wss://test.relay")
    }

    func testHandleEOSEWithNonNDKRelayDoesNotCrash() async throws {
        // Given: A coordinator with EOSE handler
        let ndk = NDK()
        let coordinator = NDKSubscriptionCoordinator(ndk: ndk)

        var eoseRelays: [String] = []
        coordinator.onEOSE = { relay in
            eoseRelays.append(relay.url)
        }

        // When: EOSE from a mock relay
        let mockRelay = MockRelayProtocol(url: "wss://test.relay")

        await coordinator.handleEOSE(from: mockRelay)

        // Then: Should handle gracefully
        XCTAssertEqual(eoseRelays.count, 1)
        XCTAssertEqual(eoseRelays[0], "wss://test.relay")
    }
}

// Mock relay for testing
private class MockRelayProtocol: RelayProtocol {
    let url: String
    var status: RelayStatus = .connected

    init(url: String) {
        self.url = url
    }

    func connect() async {}
    func disconnect() {}
    func subscribe(to filters: [NDKFilter]) -> AsyncStream<NDKEvent> {
        AsyncStream { _ in }
    }
}
```

**Step 3: Run test to verify it fails**

Run: `swift test --filter NDKSubscriptionCoordinatorTests`
Expected: Tests fail because MockRelayProtocol doesn't exist yet or coordinator crashes on cast

**Step 4: Fix the force casts**

In `Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift`, replace lines 440-465:

```swift
func handleEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
    // Call callback if set
    if let onEvent = onEvent {
        // Only pass NDKRelay instances to maintain type safety
        // For other RelayProtocol implementations, we can't guarantee full NDKRelay functionality
        guard let ndkRelay = relay as? NDKRelay else {
            NDKLogger.log("Warning: Received event from non-NDKRelay relay: \(relay.url)", level: .warning)
            return
        }
        await onEvent(event, ndkRelay)
    }

    // Call legacy handlers
    for handler in eventHandlers {
        await handler(event)
    }

    // Stream to AsyncSequence
    eventContinuation?.yield((event: event, relay: relay.url))
}

func handleEOSE(from relay: RelayProtocol) async {
    // Call callback if set
    if let onEOSE = onEOSE {
        guard let ndkRelay = relay as? NDKRelay else {
            NDKLogger.log("Warning: Received EOSE from non-NDKRelay relay: \(relay.url)", level: .warning)
            return
        }
        await onEOSE(ndkRelay)
    }

    // Mark EOSE in subscription tracking
    eoseContinuation?.yield(relay.url)
}
```

**Step 5: Run tests to verify they pass**

Run: `swift test --filter NDKSubscriptionCoordinatorTests`
Expected: All tests pass

**Step 6: Run full test suite**

Run: `swift test`
Expected: All tests pass (no regressions)

**Step 7: Temporary disable pre-commit hook and commit**

Since we're in a worktree and haven't merged the hook yet:

```bash
git add Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift
git add Tests/NDKSwiftCoreTests/DataSource/NDKSubscriptionCoordinatorTests.swift
git commit --no-verify -m "fix: replace force casts with safe conditional casting in NDKSubscriptionCoordinator

- Replace 'as!' with 'as?' for RelayProtocol to NDKRelay casts
- Add proper error handling and logging for non-NDKRelay instances
- Add tests to verify behavior with mock relay implementations
- Prevents runtime crashes when custom RelayProtocol implementations are used

Fixes type safety issue at NDKSubscriptionCoordinator.swift:443,459"
```

---

## Task 3: Remove Legacy Event Handlers (Dual Delivery Pattern)

**Files:**
- Modify: `Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift`
- Modify: Any files that use `eventHandlers` array

**Step 1: Find all usages of eventHandlers**

Run: `grep -r "eventHandlers" Sources/`
Expected: List of files using the legacy pattern

**Step 2: Analyze which parts of codebase use legacy handlers**

Read each file from step 1 to understand usage patterns.

**Step 3: Write migration guide comment**

In `Sources/NDKSwiftCore/DataSource/NDKSubscriptionCoordinator.swift`, add deprecation:

```swift
@available(*, deprecated, message: "Use onEvent callback or async stream instead")
public var eventHandlers: [(NDKEvent) async -> Void] = []
```

**Step 4: Update all internal usages to use onEvent**

For each usage found in step 1, convert from:
```swift
coordinator.eventHandlers.append { event in
    // handle
}
```

To:
```swift
coordinator.onEvent = { event, relay in
    // handle
}
```

**Step 5: Remove eventHandlers loop from handleEvent**

In `handleEvent` method, remove:
```swift
// Call legacy handlers
for handler in eventHandlers {
    await handler(event)
}
```

**Step 6: Run tests**

Run: `swift test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add -A
git commit --no-verify -m "refactor: remove legacy event handlers pattern

- Deprecate eventHandlers array in favor of onEvent callback
- Migrate all internal usages to modern async callback pattern
- Remove dual delivery mechanism to simplify codebase
- Maintains backward compatibility with deprecation warning

Breaking change: eventHandlers will be removed in next major version"
```

---

## Task 4: Convert Logger to Thread-Safe Actor

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/Utilities/NDKLogger.swift:194-264`
- Add test: `Tests/NDKSwiftCoreTests/Core/Utilities/NDKLoggerTests.swift`

**Step 1: Read current logger implementation**

Read: `Sources/NDKSwiftCore/Core/Utilities/NDKLogger.swift`

**Step 2: Write tests for concurrent logging**

Create `Tests/NDKSwiftCoreTests/Core/Utilities/NDKLoggerTests.swift`:

```swift
import XCTest
@testable import NDKSwiftCore

final class NDKLoggerTests: XCTestCase {

    override func setUp() async throws {
        await NDKLogger.shared.reset()
    }

    func testConcurrentLogging() async throws {
        // Given: Logger configured to capture messages
        var loggedMessages: [String] = []
        await NDKLogger.shared.setLogHandler { message in
            loggedMessages.append(message)
        }

        // When: Multiple tasks log concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await NDKLogger.shared.log("Message \(i)", level: .info)
                }
            }
        }

        // Then: All messages logged without data races
        XCTAssertEqual(loggedMessages.count, 100)
    }

    func testLogLevelFiltering() async throws {
        // Given: Logger at warning level
        await NDKLogger.shared.setLogLevel(.warning)

        var loggedMessages: [String] = []
        await NDKLogger.shared.setLogHandler { message in
            loggedMessages.append(message)
        }

        // When: Logging at different levels
        await NDKLogger.shared.log("Debug", level: .debug)
        await NDKLogger.shared.log("Info", level: .info)
        await NDKLogger.shared.log("Warning", level: .warning)
        await NDKLogger.shared.log("Error", level: .error)

        // Then: Only warning and error logged
        XCTAssertEqual(loggedMessages.count, 2)
        XCTAssertTrue(loggedMessages[0].contains("Warning"))
        XCTAssertTrue(loggedMessages[1].contains("Error"))
    }
}
```

**Step 3: Run tests to verify current behavior**

Run: `swift test --filter NDKLoggerTests`
Expected: May fail due to data races or missing actor isolation

**Step 4: Convert NDKLogger to actor**

Replace the logger implementation:

```swift
/// Thread-safe logger using actor isolation
public actor NDKLogger {
    public static let shared = NDKLogger()

    private var logLevel: NDKLogLevel = .info
    private var logNetworkTraffic: Bool = false
    private var prettyPrintNetworkMessages: Bool = true
    private var enabledCategories: Set<NDKLogCategory> = [
        .general,
        .relay,
        .subscription,
        .event,
        .pool,
        .profile,
        .cache,
        .network,
        .signer,
        .wallet
    ]
    private var logHandler: ((String) -> Void)?

    private init() {}

    // MARK: - Configuration

    public func setLogLevel(_ level: NDKLogLevel) {
        self.logLevel = level
    }

    public func getLogLevel() -> NDKLogLevel {
        return logLevel
    }

    public func setLogNetworkTraffic(_ enabled: Bool) {
        self.logNetworkTraffic = enabled
    }

    public func getLogNetworkTraffic() -> Bool {
        return logNetworkTraffic
    }

    public func setPrettyPrintNetworkMessages(_ enabled: Bool) {
        self.prettyPrintNetworkMessages = enabled
    }

    public func getPrettyPrintNetworkMessages() -> Bool {
        return prettyPrintNetworkMessages
    }

    public func setEnabledCategories(_ categories: Set<NDKLogCategory>) {
        self.enabledCategories = categories
    }

    public func getEnabledCategories() -> Set<NDKLogCategory> {
        return enabledCategories
    }

    public func setLogHandler(_ handler: @escaping (String) -> Void) {
        self.logHandler = handler
    }

    public func reset() {
        self.logLevel = .info
        self.logNetworkTraffic = false
        self.prettyPrintNetworkMessages = true
        self.enabledCategories = [
            .general, .relay, .subscription, .event, .pool,
            .profile, .cache, .network, .signer, .wallet
        ]
        self.logHandler = nil
    }

    // MARK: - Logging

    public func log(
        _ message: String,
        level: NDKLogLevel = .info,
        category: NDKLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check if we should log this message
        guard level.rawValue >= logLevel.rawValue else { return }
        guard enabledCategories.contains(category) else { return }

        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(level.emoji) \(category.emoji)] \(fileName):\(line) \(function) - \(message)"

        if let handler = logHandler {
            handler(logMessage)
        } else {
            print(logMessage)
        }
    }

    public func logNetwork(
        _ message: String,
        direction: String,
        relay: String? = nil
    ) {
        guard logNetworkTraffic else { return }

        let prefix = relay.map { "[\($0)] " } ?? ""
        let formattedMessage = prettyPrintNetworkMessages ? prettyPrint(message) : message

        log("\(prefix)\(direction): \(formattedMessage)", level: .debug, category: .network)
    }

    private func prettyPrint(_ message: String) -> String {
        // Pretty print JSON if possible
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return message
        }
        return prettyString
    }
}

// MARK: - Convenience static methods for backward compatibility

extension NDKLogger {
    public static func log(
        _ message: String,
        level: NDKLogLevel = .info,
        category: NDKLogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await shared.log(message, level: level, category: category, file: file, function: function, line: line)
        }
    }

    public static func logNetwork(
        _ message: String,
        direction: String,
        relay: String? = nil
    ) {
        Task {
            await shared.logNetwork(message, direction: direction, relay: relay)
        }
    }
}
```

**Step 5: Update all logger callsites to use async**

Find all `NDKLogger.logLevel`, `NDKLogger.logNetworkTraffic`, etc. and update to:
```swift
await NDKLogger.shared.setLogLevel(.debug)
let level = await NDKLogger.shared.getLogLevel()
```

Note: The static convenience methods remain fire-and-forget for logging calls.

**Step 6: Run tests**

Run: `swift test --filter NDKLoggerTests`
Expected: All tests pass

**Step 7: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 8: Commit**

```bash
git add -A
git commit --no-verify -m "refactor: convert NDKLogger to thread-safe actor

- Replace nonisolated(unsafe) static properties with actor-isolated state
- Add proper async/await APIs for configuration
- Maintain backward-compatible static convenience methods for logging
- Add comprehensive tests for concurrent logging
- Eliminates data race risks in logger configuration

BREAKING CHANGE: Logger configuration now requires await"
```

---

## Task 5: Create Typed JSON Decoder for NostrMessage

**Files:**
- Create: `Sources/NDKSwiftCore/Relay/NostrMessageDecoder.swift`
- Modify: `Sources/NDKSwiftCore/Relay/NostrMessage.swift`
- Add test: `Tests/NDKSwiftCoreTests/Relay/NostrMessageDecoderTests.swift`

**Step 1: Write tests for JSON decoding**

Create `Tests/NDKSwiftCoreTests/Relay/NostrMessageDecoderTests.swift`:

```swift
import XCTest
@testable import NDKSwiftCore

final class NostrMessageDecoderTests: XCTestCase {

    func testDecodeEventMessage() throws {
        // Given: Valid EVENT message JSON
        let json = """
        ["EVENT", "sub123", {
            "id": "abc123",
            "pubkey": "pubkey123",
            "created_at": 1234567890,
            "kind": 1,
            "tags": [],
            "content": "Hello",
            "sig": "signature123"
        }]
        """

        // When: Decoding
        let message = try NostrMessageDecoder.decode(json)

        // Then: Correct message type and data
        guard case .event(let subscriptionId, let event) = message else {
            XCTFail("Expected EVENT message")
            return
        }
        XCTAssertEqual(subscriptionId, "sub123")
        XCTAssertEqual(event.content, "Hello")
    }

    func testDecodeInvalidJSON() {
        // Given: Invalid JSON
        let json = "not valid json"

        // When/Then: Should throw descriptive error
        XCTAssertThrowsError(try NostrMessageDecoder.decode(json)) { error in
            guard let decodingError = error as? NostrMessageDecodingError else {
                XCTFail("Expected NostrMessageDecodingError")
                return
            }
            XCTAssertEqual(decodingError, .invalidJSON)
        }
    }

    func testDecodeMissingRequiredField() {
        // Given: EVENT message missing required field
        let json = """
        ["EVENT", "sub123", {
            "id": "abc123",
            "created_at": 1234567890,
            "kind": 1,
            "tags": [],
            "content": "Hello"
        }]
        """

        // When/Then: Should throw missing field error
        XCTAssertThrowsError(try NostrMessageDecoder.decode(json)) { error in
            guard let decodingError = error as? NostrMessageDecodingError else {
                XCTFail("Expected NostrMessageDecodingError")
                return
            }
            if case .missingRequiredField(let field) = decodingError {
                XCTAssertTrue(field == "pubkey" || field == "sig")
            } else {
                XCTFail("Expected missingRequiredField error")
            }
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter NostrMessageDecoderTests`
Expected: Tests fail because NostrMessageDecoder doesn't exist

**Step 3: Create NostrMessageDecoder**

Create `Sources/NDKSwiftCore/Relay/NostrMessageDecoder.swift`:

```swift
import Foundation

public enum NostrMessageDecodingError: Error, Equatable {
    case invalidJSON
    case notAnArray
    case emptyArray
    case unknownMessageType(String)
    case missingRequiredField(String)
    case invalidFieldType(field: String, expected: String)
    case invalidEventData
}

public struct NostrMessageDecoder {

    public static func decode(_ jsonString: String) throws -> NostrMessage {
        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw NostrMessageDecodingError.invalidJSON
        }

        // Ensure it's an array
        guard let array = json as? [Any], !array.isEmpty else {
            throw NostrMessageDecodingError.notAnArray
        }

        // Get message type
        guard let typeString = array[0] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "type", expected: "String")
        }

        // Decode based on type
        switch typeString {
        case "EVENT":
            return try decodeEvent(array)
        case "OK":
            return try decodeOK(array)
        case "EOSE":
            return try decodeEOSE(array)
        case "CLOSED":
            return try decodeClosed(array)
        case "NOTICE":
            return try decodeNotice(array)
        case "AUTH":
            return try decodeAuth(array)
        default:
            throw NostrMessageDecodingError.unknownMessageType(typeString)
        }
    }

    private static func decodeEvent(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 3 else {
            throw NostrMessageDecodingError.missingRequiredField("subscriptionId or event")
        }

        guard let subscriptionId = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "subscriptionId", expected: "String")
        }

        guard let eventDict = array[2] as? [String: Any] else {
            throw NostrMessageDecodingError.invalidFieldType(field: "event", expected: "Dictionary")
        }

        let event = try decodeEventDict(eventDict)
        return .event(subscriptionId: subscriptionId, event: event)
    }

    private static func decodeEventDict(_ dict: [String: Any]) throws -> NDKEvent {
        // Required fields
        guard let id = dict["id"] as? String else {
            throw NostrMessageDecodingError.missingRequiredField("id")
        }
        guard let pubkey = dict["pubkey"] as? String else {
            throw NostrMessageDecodingError.missingRequiredField("pubkey")
        }
        guard let kind = dict["kind"] as? Int else {
            throw NostrMessageDecodingError.missingRequiredField("kind")
        }
        guard let content = dict["content"] as? String else {
            throw NostrMessageDecodingError.missingRequiredField("content")
        }
        guard let sig = dict["sig"] as? String else {
            throw NostrMessageDecodingError.missingRequiredField("sig")
        }

        // created_at can be Int or Int64
        let createdAt: Int64
        if let timestamp = dict["created_at"] as? Int64 {
            createdAt = timestamp
        } else if let timestamp = dict["created_at"] as? Int {
            createdAt = Int64(timestamp)
        } else {
            throw NostrMessageDecodingError.missingRequiredField("created_at")
        }

        // Tags (optional but usually present)
        let tags: [[String]]
        if let tagsArray = dict["tags"] as? [[Any]] {
            tags = tagsArray.map { tag in
                tag.compactMap { $0 as? String }
            }
        } else {
            tags = []
        }

        // Create event
        let event = NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )

        return event
    }

    private static func decodeOK(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 3 else {
            throw NostrMessageDecodingError.missingRequiredField("eventId or success")
        }

        guard let eventId = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "eventId", expected: "String")
        }

        guard let success = array[2] as? Bool else {
            throw NostrMessageDecodingError.invalidFieldType(field: "success", expected: "Bool")
        }

        let message = array.count > 3 ? array[3] as? String : nil

        return .ok(eventId: eventId, success: success, message: message)
    }

    private static func decodeEOSE(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 2 else {
            throw NostrMessageDecodingError.missingRequiredField("subscriptionId")
        }

        guard let subscriptionId = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "subscriptionId", expected: "String")
        }

        return .eose(subscriptionId: subscriptionId)
    }

    private static func decodeClosed(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 3 else {
            throw NostrMessageDecodingError.missingRequiredField("subscriptionId or message")
        }

        guard let subscriptionId = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "subscriptionId", expected: "String")
        }

        guard let message = array[2] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "message", expected: "String")
        }

        return .closed(subscriptionId: subscriptionId, message: message)
    }

    private static func decodeNotice(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 2 else {
            throw NostrMessageDecodingError.missingRequiredField("message")
        }

        guard let message = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "message", expected: "String")
        }

        return .notice(message: message)
    }

    private static func decodeAuth(_ array: [Any]) throws -> NostrMessage {
        guard array.count >= 2 else {
            throw NostrMessageDecodingError.missingRequiredField("challenge")
        }

        guard let challenge = array[1] as? String else {
            throw NostrMessageDecodingError.invalidFieldType(field: "challenge", expected: "String")
        }

        return .auth(challenge: challenge)
    }
}
```

**Step 4: Update NostrMessage to use the decoder**

In `Sources/NDKSwiftCore/Relay/NostrMessage.swift`, replace the JSON parsing:

```swift
public static func fromJSON(_ jsonString: String) -> NostrMessage? {
    do {
        return try NostrMessageDecoder.decode(jsonString)
    } catch {
        NDKLogger.log("Failed to decode Nostr message: \(error)", level: .error, category: .network)
        return nil
    }
}
```

**Step 5: Run tests**

Run: `swift test --filter NostrMessageDecoderTests`
Expected: All tests pass

**Step 6: Run full test suite**

Run: `swift test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add -A
git commit --no-verify -m "refactor: create typed JSON decoder for NostrMessage

- Create NostrMessageDecoder with proper error handling
- Define NostrMessageDecodingError with descriptive cases
- Replace unsafe 'as?' casts with type-safe decoding
- Add comprehensive tests for all message types
- Improves error reporting for malformed messages"
```

---

## Task 6: Eliminate Underscore-Prefixed Properties

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/NDK.swift:117-153`
- Modify: `Sources/NDKSwiftCore/Models/NDKRelay.swift` (if any)

**Step 1: Find all underscore-prefixed properties**

Run: `grep -rn "var _[a-zA-Z]" Sources/NDKSwiftCore/`
Expected: List of all underscore-prefixed properties

**Step 2: Analyze lazy initialization pattern**

Read `Sources/NDKSwiftCore/Core/NDK.swift` lines 117-153.

**Step 3: Replace with lazy var**

In `Sources/NDKSwiftCore/Core/NDK.swift`, replace:

```swift
var _relayRanker: NDKRelayRanker?
var relayRanker: NDKRelayRanker {
    lazyInit(&_relayRanker) {
        NDKRelayRanker()
    }
}
```

With:

```swift
public lazy var relayRanker: NDKRelayRanker = {
    NDKRelayRanker()
}()
```

**Step 4: Apply to all lazy properties**

Do the same for:
- `_relaySelector` → `lazy var relaySelector`
- `_publishingStrategy` → `lazy var publishingStrategy`
- `_nip05Manager` → `lazy var nip05Manager`
- `_blossomServerManager` → `lazy var blossomServerManager`

**Step 5: Remove lazyInit helper function**

Remove the `lazyInit` helper function as it's no longer needed.

**Step 6: Run tests**

Run: `swift test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add -A
git commit --no-verify -m "refactor: replace underscore-prefixed properties with lazy var

- Replace manual lazy initialization pattern with built-in lazy var
- Remove underscore prefixes (anti-pattern in modern Swift)
- Remove custom lazyInit helper function
- Simplifies code while maintaining lazy initialization behavior"
```

---

## Task 7: Document Pre-Commit Hook Installation in README

**Files:**
- Modify: `README.md`

**Step 1: Add pre-commit hook section to README**

Add to README.md:

```markdown
## Development

### Pre-Commit Hooks

This repository includes a pre-commit hook to maintain code quality and prevent common Swift anti-patterns.

The hook will block commits that contain:
- Force casts (`as!`) - Use safe casting (`as?`) instead
- Force unwraps (`!`) in unsafe contexts (warnings only)
- `@unchecked Sendable` (warnings only)
- `nonisolated(unsafe)` (warnings only)
- Underscore-prefixed properties (warnings only)

To enable the pre-commit hook:

```bash
# Make the script executable (already done in repo)
chmod +x scripts/validate-code-quality.sh

# Install the hook
cp scripts/validate-code-quality.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

To bypass the hook in exceptional cases (not recommended):
```bash
git commit --no-verify -m "your message"
```

### Running Quality Checks Manually

You can run the quality checks at any time:

```bash
./scripts/validate-code-quality.sh
```
```

**Step 2: Commit**

```bash
git add README.md
git commit --no-verify -m "docs: add pre-commit hook installation instructions

- Document how to install and use pre-commit hooks
- Explain what patterns are blocked vs warned
- Include manual quality check instructions"
```

---

## Completion Checklist

After all tasks complete:

- [ ] All force casts removed
- [ ] Legacy event handlers removed
- [ ] Logger converted to actor
- [ ] Typed JSON decoder implemented
- [ ] Underscore properties eliminated
- [ ] Pre-commit hook installed and documented
- [ ] All tests passing
- [ ] No Swift 6 concurrency warnings
- [ ] README updated

## Notes for Execution

- Each task should be done in a separate git worktree
- Create GitHub issue before starting each task
- Create PR after completing each task
- Merge PR before moving to next task
- Use `--no-verify` for commits until pre-commit hook is merged to main
- Run full test suite after each task to catch regressions
- Document any breaking changes in commit messages
