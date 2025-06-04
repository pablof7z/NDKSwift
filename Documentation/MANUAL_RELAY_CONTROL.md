# Manual Relay Control in NDKSwift

This guide explains how to implement manual relay connection control in NDKSwift applications, allowing users to connect/disconnect relays individually and track event publishing status.

## Overview

By default, NDKSwift doesn't automatically connect to relays when they're added to the pool. This gives you full control over when and which relays to connect to, which is useful for:

- Testing relay connectivity
- Managing bandwidth usage
- Debugging relay issues
- Building relay management interfaces

## Basic Usage

### Adding Relays Without Auto-Connect

```swift
let ndk = NDK()

// Add relays without connecting
let relay1 = ndk.addRelay("wss://relay.damus.io")
let relay2 = ndk.addRelay("wss://nos.lol")

// Relays are now in the pool but not connected
print(relay1.connectionState) // .disconnected
```

### Manual Connection Control

```swift
// Connect to a specific relay
try await relay1.connect()

// Disconnect from a relay
await relay1.disconnect()

// Connect to all relays
await ndk.connect()

// Disconnect from all relays
await ndk.disconnect()
```

## Tracking Connection States

Each relay exposes its connection state which can be monitored:

```swift
// Observe connection state changes
relay.observeConnectionState { state in
    switch state {
    case .connected:
        print("Connected to \(relay.url)")
    case .connecting:
        print("Connecting to \(relay.url)")
    case .disconnected:
        print("Disconnected from \(relay.url)")
    case .failed(let error):
        print("Failed to connect: \(error)")
    default:
        break
    }
}
```

## Event Publishing with Relay Tracking

When publishing events, NDKSwift tracks which relays accepted or rejected the event:

```swift
// Create and sign an event
let event = NDKEvent(content: "Hello, Nostr!")
event.ndk = ndk
try await event.sign()

// Publish the event
let publishedRelays = try await ndk.publish(event)

// Check publish status per relay
for (relayUrl, status) in event.relayPublishStatuses {
    switch status {
    case .succeeded:
        print("✅ Published to \(relayUrl)")
    case .failed(let reason):
        print("❌ Failed at \(relayUrl): \(reason)")
    default:
        print("⏳ Status at \(relayUrl): \(status)")
    }
}

// Access OK messages from relays
for (relayUrl, okMessage) in event.relayOKMessages {
    if okMessage.accepted {
        print("✅ \(relayUrl) accepted: \(okMessage.message ?? "OK")")
    } else {
        print("❌ \(relayUrl) rejected: \(okMessage.message ?? "No reason")")
    }
}
```

## iOS App Example

Here's a complete SwiftUI example showing manual relay control with publish tracking:

```swift
@MainActor
class NostrViewModel: ObservableObject {
    @Published var connectedRelays: [RelayInfo] = []
    @Published var lastPublishedEvent: NDKEvent?
    @Published var publishedEventRelayStatuses: [(relay: String, status: String, okMessage: String?)] = []
    
    private var ndk: NDK?
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK()
        
        // Add relays but don't connect
        _ = ndk?.addRelay("wss://relay.damus.io")
        _ = ndk?.addRelay("wss://nos.lol")
        _ = ndk?.addRelay("wss://relay.nostr.band")
        
        updateRelayStatus()
    }
    
    func connectRelay(_ url: String) {
        guard let relay = ndk?.relays.first(where: { $0.url == url }) else { return }
        
        Task {
            try? await relay.connect()
            await MainActor.run {
                updateRelayStatus()
            }
        }
    }
    
    func disconnectRelay(_ url: String) {
        guard let relay = ndk?.relays.first(where: { $0.url == url }) else { return }
        
        Task {
            await relay.disconnect()
            await MainActor.run {
                updateRelayStatus()
            }
        }
    }
    
    func publishMessage(_ content: String) async {
        guard let ndk = ndk else { return }
        
        // Create and sign event
        let event = NDKEvent(content: content)
        event.ndk = ndk
        try? await event.sign()
        
        // Store for tracking
        lastPublishedEvent = event
        
        // Publish
        let publishedRelays = try? await ndk.publish(event)
        
        // Monitor for OK messages
        startMonitoringPublishStatus(for: event)
    }
    
    private func startMonitoringPublishStatus(for event: NDKEvent) {
        Task {
            // Monitor for 10 seconds
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    updatePublishStatuses(for: event)
                }
            }
        }
    }
    
    private func updatePublishStatuses(for event: NDKEvent) {
        var statuses: [(relay: String, status: String, okMessage: String?)] = []
        
        for relay in ndk?.relays ?? [] {
            let relayUrl = relay.url
            var statusText = ""
            var okMessage: String?
            
            // Check OK message first
            if let ok = event.relayOKMessages[relayUrl] {
                statusText = ok.accepted ? "✅ Accepted" : "❌ Rejected"
                okMessage = ok.message
            } else if let publishStatus = event.relayPublishStatuses[relayUrl] {
                // Fall back to publish status
                switch publishStatus {
                case .succeeded:
                    statusText = "✅ Published"
                case .failed(.connectionFailed):
                    statusText = "❌ Not connected"
                case .failed(.custom(let message)):
                    statusText = "❌ \(message)"
                default:
                    statusText = "⏳ Pending"
                }
            } else if relay.connectionState != .connected {
                statusText = "⚪ Not connected"
            }
            
            statuses.append((relay: relayUrl, status: statusText, okMessage: okMessage))
        }
        
        publishedEventRelayStatuses = statuses
    }
}
```

## SwiftUI Interface

```swift
struct ContentView: View {
    @StateObject private var viewModel = NostrViewModel()
    
    var body: some View {
        VStack {
            // Relay management
            ForEach(viewModel.connectedRelays) { relay in
                HStack {
                    Text(relay.url)
                    Spacer()
                    
                    if relay.connectionState == .connected {
                        Button("Disconnect") {
                            viewModel.disconnectRelay(relay.url)
                        }
                    } else {
                        Button("Connect") {
                            viewModel.connectRelay(relay.url)
                        }
                    }
                }
            }
            
            // Publish status
            if viewModel.lastPublishedEvent != nil {
                VStack {
                    Text("Publish Status")
                        .font(.headline)
                    
                    ForEach(viewModel.publishedEventRelayStatuses, id: \.relay) { status in
                        HStack {
                            Text(status.relay)
                            Spacer()
                            Text(status.status)
                            if let okMsg = status.okMessage {
                                Text("(\(okMsg))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}
```

## Key Features

1. **Manual Connection Control**: Relays can be added without connecting, giving you full control
2. **Connection State Tracking**: Monitor relay connection states in real-time
3. **Publish Status Tracking**: See which relays accepted/rejected your events
4. **OK Message Access**: Access detailed rejection reasons from relays
5. **Per-Relay Statistics**: Track messages sent/received per relay

## Best Practices

1. **Don't Auto-Connect**: Add relays first, then let users choose which to connect
2. **Monitor OK Messages**: Check `relayOKMessages` for detailed feedback from relays
3. **Handle Disconnections**: Update UI when relays disconnect unexpectedly
4. **Show Progress**: Display connection/publishing states to users
5. **Batch Operations**: Use `ndk.connect()` to connect all relays at once when needed

## Testing Relay Behavior

This manual control approach is perfect for testing:

```swift
// Test publishing to zero relays
let event = NDKEvent(content: "Test")
try await event.sign()
let published = try await ndk.publish(event)
assert(published.isEmpty)

// Connect one relay and republish
try await relay1.connect()
let published2 = try await ndk.publish(event)
assert(published2.count == 1)

// Check OK message
if let okMsg = event.relayOKMessages[relay1.url] {
    print("Relay response: \(okMsg.accepted ? "accepted" : "rejected")")
}
```

This pattern gives you complete control over relay connections and detailed visibility into event publishing results.