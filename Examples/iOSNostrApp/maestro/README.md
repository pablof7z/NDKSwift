# Maestro Tests for iOS Nostr App

This directory contains Maestro UI tests for the iOS Nostr app, focusing on relay connection management and event publishing tracking.

## Prerequisites

1. Install Maestro CLI:
   ```bash
   curl -Ls "https://get.maestro.mobile.dev" | bash
   ```

2. Build and install the iOS app in the simulator:
   ```bash
   # From the Examples/iOSNostrApp directory
   xcodebuild -scheme iOSNostrApp -destination 'platform=iOS Simulator,name=iPhone 15' build
   ```

## Running Tests

### Run all tests:
```bash
maestro test maestro/
```

### Run specific test:
```bash
maestro test maestro/relay_connection_test.yaml
```

### Run with Maestro Studio (interactive):
```bash
maestro studio
```

## Test Scenarios

### relay_connection_test.yaml

This test verifies the manual relay connection control flow:

1. **Initial State**: App starts with relays added but not connected
2. **Publishing with No Relays**: Attempts to publish show appropriate error
3. **Connecting Relays**: Tests the Connect button functionality
4. **Publishing with Connected Relays**: Verifies events are sent to connected relays
5. **OK Message Tracking**: Waits for and verifies relay acceptance messages
6. **Relay Management**: Tests adding, removing, and disconnecting relays
7. **Publish Status Display**: Verifies the UI shows correct status for each relay

## Key Assertions

- Relays start in disconnected state
- Publishing to zero relays shows appropriate message
- Connect/Disconnect buttons work correctly
- Publish status shows ✅ for accepted, ❌ for rejected
- OK messages from relays are displayed
- Relay count in publish message matches connected relays

## Debugging

If tests fail:

1. Run with `--debug` flag:
   ```bash
   maestro test --debug maestro/relay_connection_test.yaml
   ```

2. Use Maestro Studio to step through:
   ```bash
   maestro studio
   ```

3. Check app logs in Console.app while test runs

## Tips

- The test waits up to 5 seconds for relay connections
- OK messages may take a few seconds to arrive from relays
- The test creates a new account each run for consistency
- Make sure the iOS Simulator is running before starting tests