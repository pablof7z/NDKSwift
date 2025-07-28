# Connection Error Rate Limiting

## Overview

NDKSwift now includes connection error rate limiting to prevent log spam when relays are consistently failing to connect. This is particularly useful when dealing with relays that are down or have DNS resolution issues.

## Problem

Previously, when a relay failed to connect (e.g., DNS resolution failure), it would generate multiple redundant error logs:
- Connection failed log
- Ping failed log  
- Receive loop ended log
- Connection error log
- Relay failed warning in NDKPool
- NDKPool connection failure log

This could result in 6+ log entries per relay per connection attempt, creating excessive noise in the logs.

## Solution

### 1. Rate Limiter (`NDKConnectionErrorRateLimiter`)

A new actor-based rate limiter that:
- Tracks errors per relay URL and error type
- Limits logging to once per 30 seconds for the same error type on the same relay
- Provides summary statistics of suppressed errors
- Automatically cleans up old error records after 5 minutes

### 2. Consolidated Error Logging

Error logging has been consolidated in `NDKRelayConnection`:
- The `handleConnectionError` method now accepts a `shouldLog` parameter to prevent double-logging
- Error logging checks with the rate limiter before writing to logs
- Different error types (connectionFailed, pingFailed, receiveError) are tracked separately
- Initial connection failures use `.error` level, subsequent retries use `.warning` level

### 3. Integration Points

The rate limiter is integrated at key error logging points:
- `NDKRelayConnection.connect()` - Initial connection failures
- `NDKRelayConnection.sendPing()` - Ping timeout errors
- `NDKRelayConnection.receiveMessages()` - Receive loop errors
- `NDKRelayConnection.handleConnectionError()` - General connection errors
- `NDKPool` relay state monitoring - Relay failure warnings

## Usage

The rate limiting is automatic and requires no configuration. When errors are suppressed, you'll see a debug-level summary message like:

```
📊 Suppressed 15 similar error(s) in the last 30 seconds
```

## Configuration

Currently, the rate limiter uses fixed values:
- **Minimum log interval**: 30 seconds between logs for the same error
- **Error reset interval**: 5 minutes (errors older than this are cleaned up)

These could be made configurable in the future if needed.

## Benefits

1. **Reduced log noise**: Failing relays no longer spam the logs
2. **Better debugging**: Important errors are still logged, but duplicates are suppressed
3. **Performance**: Less string formatting and I/O for suppressed logs
4. **Visibility**: Summary statistics show when errors are being suppressed

## Example

Before (multiple logs per failure):
```
[ERROR] 🔌 ❌ Ping failed for wss://devrelay.highlighter.com/: connectionFailed...
[ERROR] 🔌 🔴 Connection error for wss://devrelay.highlighter.com/: connectionFailed...
[ERROR] 🔌 ❌ Connection failed to wss://devrelay.highlighter.com/: connectionFailed...
[ERROR] 🔗 [NDKPool] Failed to connect to relay wss://devrelay.highlighter.com/: connectionFailed...
[ERROR] 🔌 🔴 Receive loop ended with error: connectionFailed...
[WARNING] 🔗 🔴 Relay failed: wss://devrelay.highlighter.com/, error: Connection failed...
```

After (single log with summary):
```
[ERROR] 🔌 ❌ Connection failed to wss://devrelay.highlighter.com/: connectionFailed...
[DEBUG] 📊 Suppressed 5 similar error(s) in the last 30 seconds
```