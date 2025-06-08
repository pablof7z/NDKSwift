import Foundation

/// Thread-safe event collection using actors
actor EventCollection {
    private var events: [NDKEvent] = []
    private var receivedEventIds: Set<EventID> = []
    
    /// Add an event if it's not a duplicate
    /// - Returns: true if the event was added, false if it was a duplicate
    func addEvent(_ event: NDKEvent) -> Bool {
        guard let eventId = event.id else { return false }
        
        // Check for duplicate
        guard !receivedEventIds.contains(eventId) else { return false }
        
        receivedEventIds.insert(eventId)
        events.append(event)
        return true
    }
    
    /// Get all events
    func getEvents() -> [NDKEvent] {
        events
    }
    
    /// Get event count
    func count() -> Int {
        events.count
    }
    
    /// Check if an event has been received
    func hasReceivedEvent(withId id: EventID) -> Bool {
        receivedEventIds.contains(id)
    }
    
    /// Clear all events
    func clear() {
        events.removeAll()
        receivedEventIds.removeAll()
    }
}

/// Thread-safe callback collection using actors
actor CallbackCollection<T> {
    private var callbacks: [T] = []
    
    /// Add a callback
    func add(_ callback: T) {
        callbacks.append(callback)
    }
    
    /// Get all callbacks
    func getAll() -> [T] {
        callbacks
    }
    
    /// Execute all callbacks with a value
    func execute<V>(with value: V, using executor: (T, V) -> Void) {
        for callback in callbacks {
            executor(callback, value)
        }
    }
    
    /// Clear all callbacks
    func clear() {
        callbacks.removeAll()
    }
    
    /// Get count
    func count() -> Int {
        callbacks.count
    }
}

/// Thread-safe state manager using actors
actor StateManager<State> {
    private var state: State
    
    init(_ initialState: State) {
        self.state = initialState
    }
    
    /// Get the current state
    func get() -> State {
        state
    }
    
    /// Update the state
    func update(_ newState: State) {
        state = newState
    }
    
    /// Update the state using a transform function
    func update(using transform: (State) -> State) {
        state = transform(state)
    }
}

/// Example of how to use these in NDKSubscription:
/// 
/// Instead of:
/// ```swift
/// private let eventsLock = NSLock()
/// private let receivedEventIdsLock = NSLock()
/// private var events: [NDKEvent] = []
/// private var receivedEventIds: Set<EventID> = []
/// ```
/// 
/// Use:
/// ```swift
/// private let eventCollection = EventCollection()
/// 
/// // Add event (async)
/// let wasAdded = await eventCollection.addEvent(event)
/// 
/// // Get events (async)
/// let allEvents = await eventCollection.getEvents()
/// ```
///
/// This eliminates manual lock management and provides compile-time thread safety.