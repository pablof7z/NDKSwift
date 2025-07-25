# Outbox Debugger

A terminal-based REPL CLI for debugging NDKSwift's outbox implementation.

## Features

- **Real-time relay monitoring**: Shows connected relays with sent/received event counts in the top-right corner
- **Outbox inspection**: View cached outbox information for any npub
- **Event publishing**: Create and publish kind:1 events with p-tags, tracking which relays accepted/rejected them
- **Query inspection**: See which relays are used when fetching events based on the outbox model

## Building

```bash
cd Examples/OutboxDebugger
swift build
```

## Running

```bash
swift run outbox-debug
```

Or after building:

```bash
.build/debug/outbox-debug
```

## Commands

### help
Shows available commands.

### outbox [npub...]
Displays cached outbox information (read/write relays) for one or more npubs.

Example:
```
outbox npub1abc...
```

### publish npub1... npub2...
Creates a "Hello world" kind:1 event p-tagging the specified npubs and publishes it. Shows which relays the event was sent to and their responses.

Example:
```
publish npub1abc... npub1def...
```

### req npub1... npub2...
Fetches the most recent kind:1 event from each specified npub. Shows which relays were queried based on the outbox model.

Example:
```
req npub1abc... npub1def...
```

### clear
Clears the screen.

### exit
Exits the debugger.

## Interface

```
┌─────────────────────── Outbox Debugger ───────────────────────┐
│                                          🟢 relay.primal.net   │
│                                             ↑23 ↓156           │
│                                                                │
│ Output area...                                                 │
│                                                                │
│                                                                │
│ ❯ _                                                            │
└────────────────────────────────────────────────────────────────┘
```

## Architecture

The debugger uses hooks inserted into NDKSwift to monitor relay activity without interfering with the outbox logic. This allows for accurate observation of:

- Which relays are selected for publishing
- Which relays accept or reject events
- Which relays are queried for fetching events
- Real-time connection status and message counts

All hooks are marked with `// MARK: - OUTBOX_DEBUG_HOOK` for easy removal.