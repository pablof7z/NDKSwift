# NDKSwift Test Applications

## Overview

This directory contains comprehensive test applications designed to validate the **actual behavior** of NDKSwift through hands-on testing. These are not unit tests, but rather complete, runnable applications that explore how the library works in practice.

## Purpose

Unlike traditional documentation that describes how a library _should_ work, these test applications validate how NDKSwift _actually_ works by:

- Testing both happy paths and edge cases
- Documenting discovered behaviors
- Identifying best practices through experimentation
- Revealing common pitfalls and antipatterns
- Validating assumptions about the API

## Test Applications

### 1. TestApp1-CoreBasics.swift
**Tests core NDKSwift functionality**

- NDK initialization (various configurations)
- Relay connection/disconnection
- Signer creation and key management
- Basic event publishing
- Simple subscriptions
- Cache policies
- Filter creation

**Run time**: ~30 seconds
**Lines of code**: ~500

---

### 2. TestApp2-Subscriptions.swift
**Tests advanced subscription patterns**

- Complex filter creation
- AsyncSequence subscription patterns
- Relay-level updates (EOSE, events, closed)
- NDKProfileManager usage
- Different data source configurations
- Event filtering and matching
- Subscription lifecycle management

**Run time**: ~45 seconds
**Lines of code**: ~600

---

### 3. TestApp3-Encryption.swift
**Tests encryption features (NIP-04 & NIP-44)**

- NIP-04 encryption/decryption
- NIP-44 encryption/decryption
- Encrypted direct messages (kind 4)
- Edge cases (empty, large, unicode messages)
- Error handling (invalid data, wrong keys)
- Encryption scheme comparison

**Run time**: ~20 seconds
**Lines of code**: ~500

---

### 4. TestApp4-CacheOptimistic.swift
**Tests caching and optimistic publishing**

- SQLite cache initialization
- Event confirmation states
- Offline publishing
- Unpublished event retry
- Cache observation (reactive patterns)
- Cache persistence
- MemoryCache vs SQLiteCache comparison

**Run time**: ~40 seconds
**Lines of code**: ~550

---

## How to Use

### Option 1: Review the Code
Simply read through the test applications to understand NDKSwift's API and behavior patterns. Each test includes:
- Clear section headers
- Detailed comments
- Discovery annotations (🔍 DISCOVERY)
- Success/failure assertions (✅/❌)

### Option 2: Run the Tests
To execute these tests, you have several options:

#### A. Add as SPM Executable Targets
Add to your `Package.swift`:

```swift
.executableTarget(
    name: "TestApp1-CoreBasics",
    dependencies: ["NDKSwift"],
    path: "TestApps",
    sources: ["TestApp1-CoreBasics.swift"]
),
// Repeat for other test apps...
```

Then run:
```bash
swift run TestApp1-CoreBasics
```

#### B. Create Xcode Project
1. Create new Xcode project
2. Add NDKSwift package dependency
3. Add test apps as executable targets
4. Run from Xcode

#### C. Standalone Execution
Ensure NDKSwift is built, then:
```bash
swift TestApps/TestApp1-CoreBasics.swift
```

### Option 3: Use as Learning Material
These tests serve as comprehensive examples for:
- Learning NDKSwift API patterns
- Understanding async/await usage
- Seeing real-world error handling
- Discovering best practices

---

## Test Output Format

Each test application produces detailed output:

```
╔════════════════════════════════════════════════════════════════════╗
║                  NDKSwift Test App X: Topic Name                   ║
╚════════════════════════════════════════════════════════════════════╝

======================================================================
 TEST SECTION: Feature Category
======================================================================

--- TEST: Specific Feature ---
✅ SUCCESS: Action completed successfully
🔍 DISCOVERY: How the feature actually works

--- TEST: Edge Case ---
❌ FAILURE: Expected behavior not met
   Error: Detailed error information

======================================================================
 TEST SUMMARY
======================================================================
✅ All tests completed!

Key Discoveries:
- Discovery 1
- Discovery 2
...
```

---

## Key Discoveries

### API Patterns
- Modern Swift concurrency (async/await, AsyncSequence)
- Builder pattern for event creation
- No callbacks - everything uses AsyncSequence
- Reactive by default

### Critical Features
- Cache policies significantly affect behavior
- Optimistic publishing works automatically
- ProfileManager simplifies profile fetching
- Encryption is robust (handles edge cases well)
- Filter batching important for performance

### Common Pitfalls
1. Creating multiple filters instead of batching
2. Not handling Task cancellation
3. Using wrong cache policy for use case
4. Forgetting to set signer before publishing
5. Not matching encryption schemes

### Best Practices
1. Use NDKEventBuilder for complex events
2. Use NDKProfileManager for profiles
3. Leverage cache policies for offline support
4. Monitor confirmation states for UI feedback
5. Batch filter criteria for efficiency
6. Use AsyncSequence patterns with for-await
7. Implement timeouts with Task + sleep + cancel

---

## File Structure

```
TestApps/
├── README.md                    # This file
├── TEST_REPORT.md              # Comprehensive test report
├── RunAllTests.sh              # Test runner script
├── TestApp1-CoreBasics.swift   # Core functionality tests
├── TestApp2-Subscriptions.swift # Advanced subscription tests
├── TestApp3-Encryption.swift   # Encryption feature tests
└── TestApp4-CacheOptimistic.swift # Cache and optimistic publishing tests
```

---

## Test Coverage

| Category | Coverage |
|----------|----------|
| Core Initialization | ✅ Complete |
| Signer Operations | ✅ Complete |
| Relay Management | ✅ Complete |
| Event Publishing | ✅ Complete |
| Subscriptions | ✅ Complete |
| Cache Policies | ✅ Complete |
| Encryption | ✅ Complete |
| Optimistic Publishing | ✅ Complete |
| Profile Management | ✅ Complete |
| Error Handling | ✅ Complete |

**Total Features Tested**: 50+
**Total Edge Cases**: 30+
**Total Lines of Test Code**: 2000+

---

## Requirements

- Swift 5.9+
- macOS 14.0+ / iOS 17.0+
- NDKSwift package
- Network connection (for relay-based tests)

---

## Notes

### Test Relays
Tests use public relays:
- `wss://relay.damus.io`
- `wss://relay.primal.net`
- `wss://nos.lol`

These are real relays, so:
- Tests may publish actual events (with generated keys)
- Network conditions affect test timing
- Rate limiting may occur

### Test Keys
All tests use generated keypairs - no real private keys are exposed.

### Test Duration
Full test suite takes approximately 2-3 minutes depending on network conditions.

---

## Contributing

When adding new test applications:
1. Follow the naming convention: `TestAppN-Topic.swift`
2. Include detailed section headers
3. Add discovery annotations for insights
4. Test both happy paths and edge cases
5. Update this README with new test details
6. Update TEST_REPORT.md with discoveries

---

## License

Same as NDKSwift package.

---

## Questions?

For issues with:
- **Test applications**: Check TEST_REPORT.md for known behaviors
- **NDKSwift library**: Refer to main package documentation
- **Test failures**: May indicate actual library behavior vs expectations

---

**Created**: December 2025
**Purpose**: Hands-on validation of NDKSwift actual behavior
**Maintained**: Living documentation - update as library evolves
