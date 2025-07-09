# E2E Test Guide

## Overview

NDKSwift includes comprehensive end-to-end tests that verify core functionality against live Nostr relays. These tests ensure that the library works correctly in real-world scenarios.

## Running E2E Tests

To run the end-to-end tests:

```bash
swift run E2ECoreTest
```

This test suite verifies:
1. **Relay Connection** - Connects to multiple public relays
2. **Event Publishing** - Publishes a test event and verifies it was accepted
3. **Event Fetching** - Retrieves the published event by ID
4. **Real-time Subscriptions** - Creates a subscription and receives events in real-time
5. **Graceful Disconnection** - Properly disconnects from all relays

## Test Details

The E2E test uses:
- Public relays: `wss://relay.damus.io`, `wss://relay.primal.net`, `wss://nos.lol`
- Ephemeral keys generated for each test run
- Timeout handling to prevent hanging tests
- Unique content tags to avoid interference between test runs

## Debugging

To enable verbose logging, modify the test to set `debugMode = true`:

```swift
self.ndk.debugMode = true
```

## Expected Output

A successful test run will show:
```
🧪 Starting NDKSwift E2E Core Functionality Test...

--- 1. Testing Relay Connection ---
✅ Connected to 3/3 relays.

--- 2. Testing Event Publishing ---
✅ Published to 2 relays.

--- 3. Testing Event Fetching ---
✅ Successfully fetched event.

--- 4. Testing Real-time Subscriptions ---
✅ Subscription test passed.

✅ All E2E tests passed successfully!

--- 5. Disconnecting ---
✅ Disconnected from 3/3 relays.
```

## Troubleshooting

If tests fail:
1. Check internet connectivity
2. Verify that the test relays are online
3. Some relays may require proof-of-work (pow) which can cause publishing to fail
4. Network latency can affect test timing - the test includes reasonable timeouts

## Adding More Tests

To add more E2E tests, follow the pattern in `Sources/E2ECoreTest/main.swift`:
1. Create a new test method following the naming convention `test_N_description`
2. Use assertions to verify expected behavior
3. Handle timeouts appropriately
4. Clean up resources after each test