# Outbox Debugger Demo

## Running the Debugger

```bash
cd Examples/OutboxDebugger
swift run outbox-debug
```

## Demo Commands

### 1. Check Outbox Information
```
outbox npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft
```
This shows the cached outbox information for jack (if any).

### 2. Publish an Event
```
publish npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft
```
This creates a "Hello world" event p-tagging jack and shows which relays accepted it.

### 3. Fetch Recent Events
```
req npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft
```
This fetches jack's most recent kind:1 event and shows which relays were queried.

## Features to Observe

1. **Relay Status**: Watch the top-right corner for real-time relay connection status
2. **Event Tracking**: See sent (↑) and received (↓) event counts
3. **Outbox Logic**: Observe which relays are selected based on the outbox model
4. **OK Responses**: See which relays accept or reject your published events

## Notes

- The debugger connects to relay.primal.net by default
- It generates a new private key each time it starts
- All commands support multiple npubs (space-separated)
- Use arrow keys to navigate command history