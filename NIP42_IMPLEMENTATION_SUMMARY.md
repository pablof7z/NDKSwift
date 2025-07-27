# NIP-42 Authentication Implementation Summary

## Overview
NDKSwift now supports NIP-42 (Authentication of clients to relays) as specified in the Nostr protocol. This implementation enables relays to require authentication from clients before accepting events.

## Key Features Implemented

### 1. Authentication States
Extended `NDKRelayConnectionState` with three new states:
- `authRequired(challenge: String)` - Relay requires authentication with a challenge
- `authenticating` - Authentication is in progress  
- `authenticated` - Successfully authenticated with the relay

### 2. Authentication Delegate
New `NDKAuthenticationDelegate` protocol allows apps to control authentication:
```swift
public protocol NDKAuthenticationDelegate: AnyObject {
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool
}
```

### 3. Automatic Event Retry
- Events that fail due to authentication requirements are automatically tracked
- Once authentication succeeds, all pending events are automatically retried
- No manual intervention required from the app

### 4. Observable State Changes
- Relay state changes can be observed through `relay.stateStream`
- Apps can monitor when relays require authentication or become authenticated

## Usage Example

```swift
// Set up authentication delegate
class MyAuthDelegate: NDKAuthenticationDelegate {
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool {
        // Show UI to user asking if they want to authenticate
        return await showAuthPrompt(for: relay)
    }
}

// Configure NDK
let ndk = NDK(signer: signer)
ndk.authenticationDelegate = MyAuthDelegate()

// Monitor relay state
for await state in relay.stateStream {
    switch state.connectionState {
    case .authRequired(let challenge):
        print("Authentication required with challenge: \(challenge)")
    case .authenticated:
        print("Successfully authenticated!")
    default:
        break
    }
}

// Publish events normally - auth retry happens automatically
try await ndk.publish(event)
```

## Test Coverage

Comprehensive tests were added to validate:
- AUTH message reception and state transitions
- Automatic event retry after authentication
- Multiple event retry handling
- Authentication decline scenarios
- State stream notifications

## Files Modified

### Core Implementation
- `Sources/NDKSwift/Models/NDKRelay.swift` - Extended connection states
- `Sources/NDKSwift/Core/NDK.swift` - Added auth delegate and handler
- `Sources/NDKSwift/Core/Managers/NDKEventManager.swift` - Pending event tracking
- `Sources/NDKSwift/Core/Managers/NDKPool.swift` - Auth state handling

### Tests
- `Tests/NDKSwiftTests/Unit/Relay/NDKRelayAuthenticationTests.swift`
- `Tests/NDKSwiftTests/Unit/Relay/NDKRelayAuthenticationFlowTests.swift`
- `Tests/NDKSwiftTests/Integration/NIP42AuthenticationIntegrationTests.swift`

### Examples
- `Examples/AuthenticationDemo.swift` - Demo implementation

## Version
This feature is included in NDKSwift v0.7.11