# NIP-29 (Relay-based Groups) Implementation Plan for NDKSwift

> **Status**: Planned - Not Yet Implemented  
> **Last Updated**: December 2024

**Note**: This document outlines a planned implementation for NIP-29 support in NDKSwift. The features described here are not yet available in the current codebase.

## Overview

NIP-29 defines relay-based groups that are managed by specific relays with closed membership. Groups are identified by a random string ID and can be public/private for reading and open/closed for membership. This implementation will follow NDKSwift's existing patterns while providing a clean, modern Swift API for group functionality.

## Key Concepts

- **Group Identity**: Groups have metadata stored in kind 39000 events signed by the relay
- **Membership**: Managed through moderation events (kinds 9000-9022)
- **Group Posts**: Regular events with an `h` tag containing the group ID
- **Roles**: Arbitrary role labels (admin, moderator, etc.) defined by relays
- **Client Validation**: Clients must validate group membership locally, not trust relay enforcement

## Implementation Phases

### Phase 1: Read-Only Foundation (Priority: High)

#### 1.1 Define Event Kinds and Constants

Add to `Sources/NDKSwift/Core/Types.swift`:

```swift
// Group moderation events
public static let groupPutUser = 9000
public static let groupRemoveUser = 9001
public static let groupEditMetadata = 9002
public static let groupDeleteEvent = 9005
public static let groupCreate = 9007
public static let groupDelete = 9008
public static let groupCreateInvite = 9009
public static let groupJoinRequest = 9021
public static let groupLeaveRequest = 9022

// Group metadata events
public static let groupMetadata = 39000
public static let groupAdmins = 39001
public static let groupMembers = 39002
public static let groupRoles = 39003
```

#### 1.2 Create NDKGroup Model Class

Create `Sources/NDKSwift/Models/Kinds/NDKGroup.swift`:

```swift
/// Represents a NIP-29 relay-based group
public class NDKGroup {
    /// The underlying metadata event (kind 39000)
    public let metadataEvent: NDKEvent
    
    /// Group identifier (d tag value)
    public let id: String
    
    /// Group name
    public var name: String? { 
        metadataEvent.tags.first(where: { $0.name == "name" })?.value 
    }
    
    /// Group picture URL
    public var picture: String? {
        metadataEvent.tags.first(where: { $0.name == "picture" })?.value
    }
    
    /// Group description
    public var about: String? {
        metadataEvent.tags.first(where: { $0.name == "about" })?.value
    }
    
    /// Whether the group is public (readable by anyone)
    public var isPublic: Bool {
        metadataEvent.tags.contains(where: { $0.name == "public" })
    }
    
    /// Whether the group is open (anyone can join)
    public var isOpen: Bool {
        metadataEvent.tags.contains(where: { $0.name == "open" })
    }
    
    /// Whether this is a managed group (has metadata)
    public var isManaged: Bool { true }
    
    /// The relay hosting this group
    public let relay: NDKRelay
    
    /// Full group identifier in format "relay.com'groupid"
    public var fullIdentifier: String {
        "\(relay.url)'\\(id)"
    }
    
    public init(metadataEvent: NDKEvent, relay: NDKRelay) throws {
        guard metadataEvent.kind == EventKind.groupMetadata,
              let groupId = metadataEvent.tags.first(where: { $0.name == "d" })?.value else {
            throw NDKError.invalidEvent
        }
        
        self.metadataEvent = metadataEvent
        self.id = groupId
        self.relay = relay
    }
}
```

#### 1.3 Add Group-Specific Tag Helpers

Extend `Sources/NDKSwift/Utils/TagHelpers.swift`:

```swift
// Group-specific tag helpers
extension Array where Element == Tag {
    /// Get the group ID from h tag
    var groupId: String? {
        first(where: { $0.name == "h" })?.value
    }
    
    /// Create an h tag for a group
    static func groupTag(_ groupId: String) -> Tag {
        Tag(name: "h", value: groupId)
    }
    
    /// Create an addressable event reference (a tag)
    static func addressableEventTag(kind: Int, pubkey: String, identifier: String, relay: String? = nil) -> Tag {
        var values = ["\(kind):\(pubkey):\(identifier)"]
        if let relay = relay {
            values.append(relay)
        }
        return Tag(name: "a", values: values)
    }
}
```

#### 1.4 Implement Client-Side Validation

Add validation methods to NDKGroup:

```swift
extension NDKGroup {
    /// Validate if a user is a member of the group
    public func isMember(_ pubkey: String, members: NDKEvent?) -> Bool {
        guard let membersEvent = members,
              membersEvent.kind == EventKind.groupMembers,
              membersEvent.tags.first(where: { $0.name == "d" })?.value == id else {
            return false
        }
        
        return membersEvent.tags.contains(where: { 
            $0.name == "p" && $0.value == pubkey 
        })
    }
    
    /// Validate if a user has a specific role
    public func hasRole(_ pubkey: String, role: String, admins: NDKEvent?) -> Bool {
        guard let adminsEvent = admins,
              adminsEvent.kind == EventKind.groupAdmins,
              adminsEvent.tags.first(where: { $0.name == "d" })?.value == id else {
            return false
        }
        
        return adminsEvent.tags.contains(where: { 
            $0.name == "p" && 
            $0.value == pubkey && 
            $0.otherValues.contains(role)
        })
    }
    
    /// Validate if an event belongs to this group
    public func validateEvent(_ event: NDKEvent) -> Bool {
        return event.tags.groupId == id
    }
}
```

#### 1.5 Add Subscribe to Group Method

Extend `Sources/NDKSwift/Core/NDK.swift`:

```swift
/// Subscribe to events in a specific group
public func subscribeToGroup(
    _ group: NDKGroup,
    kinds: Set<Int>? = nil,
    options: NDKSubscriptionOptions = .init()
) -> NDKSubscription {
    var filter = NDKFilter()
    filter.tags = ["h": [group.id]]
    if let kinds = kinds {
        filter.kinds = kinds
    }
    
    // Ensure we only query the group's relay
    var groupOptions = options
    groupOptions.relays = [group.relay]
    
    return subscribe(filters: [filter], options: groupOptions)
}

/// Fetch group metadata
public func fetchGroup(
    id: String,
    relay: NDKRelay
) async throws -> NDKGroup? {
    let filter = NDKFilter(
        kinds: [EventKind.groupMetadata],
        tags: ["d": [id]]
    )
    
    let events = try await fetchEvents(
        filters: [filter],
        relays: [relay]
    )
    
    guard let metadataEvent = events.first else { return nil }
    return try NDKGroup(metadataEvent: metadataEvent, relay: relay)
}

/// Fetch group members
public func fetchGroupMembers(
    _ group: NDKGroup
) async throws -> Set<String> {
    let filter = NDKFilter(
        kinds: [EventKind.groupMembers],
        tags: ["d": [group.id]]
    )
    
    let events = try await fetchEvents(
        filters: [filter],
        relays: [group.relay]
    )
    
    guard let membersEvent = events.first else { return [] }
    
    let memberPubkeys = membersEvent.tags
        .filter { $0.name == "p" }
        .map { $0.value }
    
    return Set(memberPubkeys)
}
```

### Phase 2: Group Interaction (Priority: Medium)

#### 2.1 Event Builders in NDKGroup

Add methods to create group events:

```swift
extension NDKGroup {
    /// Create a message event for this group
    public func createMessage(content: String, tags: [Tag] = []) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.text)
        event.content = content
        event.tags = tags + [.groupTag(id)]
        return event
    }
    
    /// Create a join request
    public func createJoinRequest(reason: String? = nil, inviteCode: String? = nil) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.groupJoinRequest)
        event.content = reason ?? ""
        event.tags = [.groupTag(id)]
        
        if let code = inviteCode {
            event.tags.append(Tag(name: "code", value: code))
        }
        
        return event
    }
    
    /// Create a leave request
    public func createLeaveRequest(reason: String? = nil) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.groupLeaveRequest)
        event.content = reason ?? ""
        event.tags = [.groupTag(id)]
        return event
    }
}
```

#### 2.2 User-Moderated Group Operations

Add moderation methods for users with proper roles:

```swift
extension NDKGroup {
    /// Create an event to add a user (requires admin/moderator role)
    public func createAddUserEvent(pubkey: String, roles: [String] = []) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.groupPutUser)
        event.tags = [
            .groupTag(id),
            Tag(name: "p", values: [pubkey] + roles)
        ]
        return event
    }
    
    /// Create an event to remove a user
    public func createRemoveUserEvent(pubkey: String, reason: String? = nil) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.groupRemoveUser)
        event.content = reason ?? ""
        event.tags = [
            .groupTag(id),
            Tag(name: "p", value: pubkey)
        ]
        return event
    }
    
    /// Create an event to delete a message
    public func createDeleteMessageEvent(eventId: String, reason: String? = nil) -> NDKEvent {
        var event = NDKEvent(kind: EventKind.groupDeleteEvent)
        event.content = reason ?? ""
        event.tags = [
            .groupTag(id),
            Tag(name: "e", value: eventId)
        ]
        return event
    }
}
```

#### 2.3 NIP-29 Relay Compliance Check

Extend NDKRelay to check for NIP-29 support:

```swift
extension NDKRelay {
    /// Check if this relay supports NIP-29 groups
    public var supportsGroups: Bool {
        // Check NIP-11 relay information for NIP-29 support
        supportedNIPs.contains(29)
    }
}
```

### Phase 3: Advanced Features (Priority: Low)

#### 3.1 NDKGroupManager

Create a manager for efficient group caching:

```swift
public actor NDKGroupManager {
    private var groupCache: [String: NDKGroup] = [:]
    private let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Fetch a group with caching
    public func fetchGroup(id: String, relay: NDKRelay) async throws -> NDKGroup? {
        let cacheKey = "\\(relay.url)'\\(id)"
        
        if let cached = groupCache[cacheKey] {
            return cached
        }
        
        let group = try await ndk.fetchGroup(id: id, relay: relay)
        if let group = group {
            groupCache[cacheKey] = group
        }
        
        return group
    }
    
    /// Watch for group updates
    public func watchGroup(_ group: NDKGroup) -> AsyncStream<NDKGroup> {
        // Implementation for watching group metadata changes
    }
}
```

#### 3.2 Relay/Bot-Managed Groups

Support for groups managed by relay bots:

```swift
extension NDKGroup {
    /// Request an action from a relay-managed group
    public func createManagedActionRequest(
        action: GroupAction,
        parameters: [String: Any]
    ) -> NDKEvent {
        // Create encrypted DM to group identity
        // or use a standardized request format
    }
}
```

#### 3.3 Group Discovery

Add methods for discovering groups:

```swift
extension NDK {
    /// Discover public groups from a relay
    public func discoverGroups(
        from relay: NDKRelay,
        limit: Int = 50
    ) async throws -> [NDKGroup] {
        let filter = NDKFilter(
            kinds: [EventKind.groupMetadata],
            limit: limit
        )
        
        let events = try await fetchEvents(
            filters: [filter],
            relays: [relay]
        )
        
        return events.compactMap { event in
            try? NDKGroup(metadataEvent: event, relay: relay)
        }
    }
}
```

## Testing Strategy

### Unit Tests
- Group metadata parsing
- Client-side validation logic
- Event builder methods
- Tag helper functions

### Integration Tests
- Group subscription flows
- Member list fetching
- Moderation event handling
- Relay compliance detection

### Example App
Create a GroupChat demo showing:
- Group discovery and joining
- Sending messages to groups
- Member list display
- Moderation features (for admins)

## Migration and Compatibility

- No breaking changes to existing APIs
- New functionality is additive
- Groups are opt-in feature

## Security Considerations

1. **Always validate locally** - Don't trust relay enforcement
2. **Verify signatures** - Ensure events are from claimed authors
3. **Check roles** - Validate user permissions before actions
4. **Handle untrusted relays** - Groups may exist on malicious relays

## Documentation Updates

### API Reference
- Document all new NDKGroup methods
- Add group subscription examples
- Explain validation requirements

### Usage Guide
- How to join and participate in groups
- Creating and managing groups
- Understanding group permissions
- Best practices for group apps

## Future Enhancements

- Group message threading
- File sharing in groups
- Voice/video integration
- Cross-relay group federation
- Advanced moderation tools

## Implementation Timeline

1. **Week 1-2**: Phase 1 (Read-only foundation)
2. **Week 3-4**: Phase 2 (Group interaction)
3. **Week 5-6**: Phase 3 (Advanced features)
4. **Week 7-8**: Testing, documentation, and example app

## Success Criteria

- Clean, Swift-idiomatic API
- Comprehensive client-side validation
- Efficient group event handling
- Clear documentation and examples
- Robust error handling
- Full test coverage