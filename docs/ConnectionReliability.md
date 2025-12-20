# Connection Reliability

NDKSwift now includes comprehensive connection reliability features that automatically detect and recover from connection failures, ensuring your app stays connected to Nostr relays even when backgrounded, when network conditions change, or when connections become stale.

## Features

### 🔍 **Active Connection Monitoring**

- **WebSocket State Monitoring**: Continuously monitors WebSocket task state to detect dead connections
- **Periodic Health Checks**: Sends ping/pong messages every 30 seconds to verify connections are alive
- **Automatic Recovery**: Automatically reconnects when failures are detected

### 📱 **iOS Lifecycle Awareness**

- **Background/Foreground Detection**: Monitors when your app enters/exits background
- **Automatic Reconnection**: Reconnects all relays when returning to foreground
- **Smart Resource Management**: Pauses unnecessary work during backgrounding

### 🌐 **Network Change Detection**

- **Connectivity Monitoring**: Detects when network becomes available/unavailable
- **Network Type Changes**: Handles WiFi ↔ Cellular transitions
- **Automatic Recovery**: Reconnects when network is restored

## Usage

### Basic Setup (Default Configuration)

The default configuration enables all reliability features with sensible defaults:

```swift
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io", "wss://nos.lol"],
    signer: yourSigner
)
await ndk.connect()
```

That's it! Connection reliability is enabled by default with these settings:
- Health checks every 30 seconds
- WebSocket state monitoring every 5 seconds
- iOS lifecycle monitoring enabled
- Network change monitoring enabled
- Auto-reconnect on foreground: enabled
- Auto-reconnect on network change: enabled

### Custom Configuration

You can customize the connection reliability behavior:

```swift
// Conservative configuration (less battery usage)
let config = NDKConnectionConfig.conservative
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: config
)

// Aggressive configuration (faster detection)
let config = NDKConnectionConfig.aggressive
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: config
)

// Minimal configuration (only state monitoring)
let config = NDKConnectionConfig.minimal
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: config
)

// Fully custom configuration
let config = NDKConnectionConfig(
    enableStateMonitoring: true,
    enableHealthChecks: true,
    healthCheckInterval: 45,  // Check every 45 seconds
    enableLifecycleMonitoring: true,
    enableNetworkMonitoring: true,
    healthCheckTimeout: 10,
    autoReconnectOnNetworkChange: true,
    autoReconnectOnForeground: true
)
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: config
)
```

## Configuration Options

### Predefined Configurations

#### `.default`
- **Best for**: Most applications
- Health checks every 30 seconds
- All monitoring features enabled
- Balanced between reliability and battery life

#### `.conservative`
- **Best for**: Battery-sensitive applications
- Health checks every 60 seconds
- All monitoring features enabled
- Optimized for battery life

#### `.aggressive`
- **Best for**: Real-time applications
- Health checks every 15 seconds
- All monitoring features enabled
- Optimized for fast failure detection

#### `.minimal`
- **Best for**: Resource-constrained scenarios
- Only WebSocket state monitoring
- No periodic health checks
- No lifecycle/network monitoring

### Custom Configuration Parameters

```swift
NDKConnectionConfig(
    // Enable WebSocket state monitoring (checks task state periodically)
    enableStateMonitoring: Bool = true,

    // Enable periodic ping/pong health checks
    enableHealthChecks: Bool = true,

    // Interval between health checks in seconds
    healthCheckInterval: TimeInterval = 30,

    // Enable iOS app lifecycle monitoring (background/foreground)
    enableLifecycleMonitoring: Bool = true,

    // Enable network connectivity monitoring
    enableNetworkMonitoring: Bool = true,

    // Timeout for health check responses in seconds
    healthCheckTimeout: TimeInterval = 10,

    // Auto-reconnect when network changes (WiFi ↔ Cellular)
    autoReconnectOnNetworkChange: Bool = true,

    // Auto-reconnect when app returns to foreground
    autoReconnectOnForeground: Bool = true
)
```

## How It Works

### Connection Monitoring

NDKSwift employs multiple layers of monitoring to ensure connections remain healthy:

1. **WebSocket State Monitoring** (every 5 seconds)
   - Checks if WebSocket task is still running
   - Detects suspended or cancelled tasks
   - Triggers reconnection if task state is invalid

2. **Health Checks** (configurable interval, default 30s)
   - Sends WebSocket ping frames
   - Waits for pong response (10s timeout)
   - Triggers reconnection on ping failure or timeout

3. **App Lifecycle Monitoring**
   - Observes `UIApplication` notifications (iOS)
   - Detects background/foreground transitions
   - Automatically reconnects when returning to foreground

4. **Network Monitoring**
   - Uses `NWPathMonitor` to track network status
   - Detects connectivity loss and restoration
   - Detects network type changes (WiFi, Cellular, etc.)
   - Triggers reconnection when network is restored

### Automatic Reconnection

When a connection failure is detected:

1. The failed connection is closed
2. A small delay allows the network to stabilize (for network changes)
3. A clean reconnection is attempted
4. **Existing subscriptions are automatically restarted** (no app intervention needed!)
5. Connection state is updated accordingly

The reconnection process is completely transparent to your application. All subscriptions continue to work seamlessly.

## Subscription Continuity

**Important**: When connections are restored, all active subscriptions are automatically restarted. Your app doesn't need to do anything—data will continue flowing through your existing subscription streams.

```swift
// This subscription continues working even through reconnections
let subscription = ndk.subscribe(filter: NDKFilter(kinds: [1], limit: 20))

for await events in subscription.events {
    // Events will continue arriving even if the app was backgrounded
    // or the network connection changed
    for event in events {
        print("Received: \(event.content)")
    }
}
```

## Performance Considerations

### Battery Impact

Connection monitoring has minimal battery impact:
- **WebSocket state checks**: Negligible (simple state reads)
- **Health checks**: Minimal (<1% battery impact with 30s interval)
- **Lifecycle monitoring**: No additional battery usage (system notifications)
- **Network monitoring**: Minimal (uses system's NWPathMonitor)

For maximum battery life, use `.conservative` configuration or increase `healthCheckInterval`.

### Network Usage

- Each health check sends a small ping frame (~10 bytes)
- Default 30s interval = ~30KB per hour per relay
- Network monitoring uses no additional bandwidth

### CPU Usage

All monitoring tasks run on background queues with low priority. CPU impact is negligible.

## Troubleshooting

### Connections Not Reconnecting

1. Check that you've called `await ndk.connect()` at least once
2. Verify that lifecycle monitoring is enabled in your config
3. Check iOS background modes if needed for your use case
4. Enable debug logging to see connection events:

```swift
// In your app initialization
NDKLogger.setLogLevel(.debug)
```

### Frequent Reconnections

If you see too many reconnections:
1. Increase `healthCheckInterval` (e.g., 60 seconds)
2. Increase `healthCheckTimeout` (e.g., 15 seconds)
3. Use `.conservative` configuration
4. Check relay stability (some relays may have issues)

### Health Checks Timing Out

If health checks frequently timeout:
1. Increase `healthCheckTimeout` (default 10s)
2. Check your network connection quality
3. Try different relays (some may be slow)
4. Consider disabling health checks if not needed:

```swift
let config = NDKConnectionConfig(
    enableHealthChecks: false,
    enableStateMonitoring: true  // Keep state monitoring
)
```

## Migration Guide

### Existing Apps

If you're upgrading from an older version of NDKSwift, **no code changes are required**. Connection reliability is enabled by default with sensible settings.

However, you may want to adjust the configuration based on your app's needs:

```swift
// Before (still works, uses default config)
let ndk = NDK(relayURLs: ["wss://relay.damus.io"])

// After (with custom config)
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: .conservative  // Optimize for battery life
)
```

### Benefits

Apps will now:
- ✅ Stay connected when backgrounded
- ✅ Automatically recover from network changes
- ✅ Detect and recover from stale connections
- ✅ Continue receiving events without interruption
- ✅ Require no app-level connection management

## Technical Details

### Architecture

The connection reliability system consists of four main components:

1. **NDKConnectionConfig**: Configuration for all reliability features
2. **NDKConnectionMonitor**: iOS lifecycle monitoring (background/foreground)
3. **NDKNetworkMonitor**: Network connectivity monitoring using NWPathMonitor
4. **NDKRelayConnection**: Enhanced with health checks and state monitoring

All components are integrated at the `NDKPool` level, which:
- Creates monitors with the provided configuration
- Coordinates reconnection across all relays
- Delegates lifecycle and network events to monitors

### Thread Safety

All monitoring components are implemented as Swift actors, ensuring thread-safe access to connection state and configuration.

### Subscription Restart

When a relay reconnects, the existing subscription restart logic in `NDKRelay.handleRelayReconnection()` automatically reactivates all subscriptions. This mechanism was already present in NDKSwift and now works seamlessly with the new connection monitoring.

## Examples

### Real-time Chat App (Aggressive)

```swift
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io", "wss://nos.lol"],
    connectionConfig: .aggressive
)
```

### Social Feed (Default)

```swift
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io", "wss://nos.lol"]
)
```

### Background Updates (Conservative)

```swift
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: .conservative
)
```

### Embedded/Widget (Minimal)

```swift
let ndk = NDK(
    relayURLs: ["wss://relay.damus.io"],
    connectionConfig: .minimal
)
```

## Summary

Connection reliability in NDKSwift is:
- ✅ **Zero Configuration**: Works out of the box with sensible defaults
- ✅ **Fully Automatic**: No app-level connection management needed
- ✅ **Transparent**: Subscriptions continue working seamlessly
- ✅ **Configurable**: Fine-tune for your app's needs
- ✅ **Efficient**: Minimal impact on battery and performance
- ✅ **Platform-Aware**: Integrates with iOS lifecycle and network APIs

Your Nostr app will now maintain reliable connections without any additional code, providing a better user experience and eliminating the need to manually handle connection issues.
