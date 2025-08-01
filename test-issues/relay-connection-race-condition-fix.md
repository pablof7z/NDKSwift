# RelayConnectionRaceConditionTests Fix

## Issue
The `RelayConnectionRaceConditionTests` was using real relay URLs (wss://relay.damus.io) which caused:
- Tests to hang when network is unavailable
- Flaky test behavior dependent on external services
- Unnecessary network traffic during test runs
- Excessive logging output

## Fix Applied
1. **Replaced real relay URLs with mock URLs**
   - Changed from `wss://relay.damus.io` to `wss://mock.relay.test`
   - This prevents actual network connections during tests

2. **Reduced logging noise**
   - Changed `NDKLogger.logLevel` from `.debug` to `.error`
   - Removed print statements that were cluttering test output

3. **Improved test stability**
   - Tests now focus on race condition behavior without network dependencies
   - Connection errors are expected and handled gracefully

## Benefits
- Tests run faster without network delays
- Tests are more reliable and deterministic
- CI/CD pipelines won't fail due to external relay availability
- Cleaner test output for easier debugging

## Verification
Run the test with:
```bash
swift test --filter "RelayConnectionRaceConditionTests"
```

The test should now pass consistently without hanging or producing excessive output.