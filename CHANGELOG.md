# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Optimistic Publishing**: Events now appear immediately in subscriptions when published locally
  - New `EventSource` enum to track event origins (optimistic, relay, cache)
  - New `EventConfirmationState` enum to track confirmation status
  - New `NDKOptimisticPublishingConfig` for granular configuration
  - Events are immediately dispatched to matching subscriptions during publish
  - Cache tracks unpublished events with confirmation states
  - Sophisticated deduplication prevents duplicate events when relay confirms
  - UI can show "sending..." vs "sent" indicators using confirmation states

### Enhanced
- **NDKCache Protocol**: Added optimistic publishing support methods
  - `addUnpublishedEvent(_:relays:)` - Cache events optimistically
  - `confirmEvent(eventId:onRelay:)` - Mark events as confirmed  
  - `getEventConfirmationState(eventId:)` - Get confirmation status
- **NDKSubscriptionOptions**: Added `skipOptimisticEvents` flag to opt-out of optimistic events
- **NDK Core**: Enhanced `publish()` method with optimistic dispatch before relay publishing
- **SimpleMemoryCache**: Implemented optimistic publishing support with confirmation state tracking

### Configuration
- Optimistic publishing is **enabled by default** for better UX
- `NDKOptimisticPublishingConfig.disabled` available for traditional behavior
- Per-subscription opt-out via `NDKSubscriptionOptions.skipOptimisticEvents`

### Performance
- Minimal overhead - only affects the publish path
- Events are processed once optimistically, then deduplicated when arriving from relays
- Memory usage slightly increased due to confirmation state tracking

### Breaking Changes
- None - Full backwards compatibility maintained
- Existing code works without changes
- Default behavior provides instant feedback while maintaining reliability

## [0.6.2] - Previous Release
<!-- Previous changelog entries would go here -->