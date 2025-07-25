import Foundation

// MARK: - OUTBOX_DEBUG_HOOK

/// Debug hook system for monitoring NDK internals
public enum NDKDebugHooks {
    public typealias DebugHook = (DebugEvent) async -> Void
    
    public enum DebugEvent {
        // Pool events
        case poolConnecting(relay: String)
        case poolConnected(relay: String)
        case poolDisconnected(relay: String, error: Error?)
        case poolConnectionFailed(relay: String, error: Error)
        
        // Subscription events
        case subscriptionCreated(id: String, filter: NDKFilter)
        case subscriptionStarting(id: String, relays: Set<String>)
        case subscriptionReceived(id: String, relay: String, event: NDKEvent)
        case subscriptionEose(id: String, relay: String)
        case subscriptionClosed(id: String, reason: String)
        
        // Outbox events
        case outboxStrategyRequested(filter: NDKFilter)
        case outboxStrategyComputed(relays: [String: [String]]) // relay -> authors
        case outboxLookupStarted(pubkey: String)
        case outboxLookupCompleted(pubkey: String, found: Bool)
        
        // DataSource events
        case dataSourceCreated(filter: NDKFilter, relays: Set<String>?)
        case dataSourceSubscribing(subscriptionId: String)
        case dataSourceWaitingForRelays
        case dataSourceTimeout(subscriptionId: String)
        
        // General flow
        case flowStep(description: String)
        case flowError(description: String, error: Error?)
    }
    
    private static var debugHook: DebugHook?
    
    public static func setDebugHook(_ hook: DebugHook?) {
        debugHook = hook
    }
    
    public static func emit(_ event: DebugEvent) async {
        if let hook = debugHook {
            await hook(event)
        }
    }
}