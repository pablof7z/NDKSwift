import Foundation

/// Actor for thread-safe subscription state management
actor SubscriptionStateActor {
    private var state: NDKSubscriptionState = .pending
    private var activeRelays: Set<NDKRelay> = []
    private var eoseReceivedFrom: Set<String> = []
    private var eventStates: [EventID: EventConfirmationState] = [:]
    private var events: [NDKEvent] = []
    private var hasReceivedEOSE: Bool = false
    private var countResults: [String: Int] = [:] // relay URL -> count
    
    // Mutable properties moved from NDKSubscription
    private var options: NDKSubscriptionOptions
    private weak var ndk: NDK?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<NDKEvent, Error>.Continuation?
    private var registrationTask: Task<Void, Never>?
    
    init(options: NDKSubscriptionOptions, ndk: NDK?) {
        self.options = options
        self.ndk = ndk
    }
    
    func transitionToActive() -> Bool {
        guard state == .pending || state == .inactive else { return false }
        state = .active
        return true
    }
    
    func transitionToClosed() -> (Bool, Set<NDKRelay>) {
        guard state != .closed else { return (false, []) }
        state = .closed
        let relays = activeRelays
        activeRelays.removeAll()
        
        // Clean up tasks
        timeoutTask?.cancel()
        timeoutTask = nil
        registrationTask?.cancel()
        registrationTask = nil
        
        return (true, relays)
    }
    
    func addRelay(_ relay: NDKRelay) {
        activeRelays.insert(relay)
    }
    
    func handleEOSE(fromRelay relay: RelayProtocol?, expectedRelays: Set<NDKRelay>) -> Bool {
        let relayUrl = relay?.url ?? "cache"
        eoseReceivedFrom.insert(relayUrl)
        
        // Check if we've received EOSE from all expected relays
        let expectedUrls = Set(expectedRelays.map { $0.url })
        let allEOSEReceived = expectedUrls.isSubset(of: eoseReceivedFrom)
        if allEOSEReceived {
            hasReceivedEOSE = true
        }
        return allEOSEReceived
    }
    
    func addEventIfNotSeen(_ event: NDKEvent, from source: EventSource) async -> Bool {
        let eventId = event.id
        
        switch source {
        case .optimistic:
            // For optimistic events, always add and mark as optimistic
            if eventStates[eventId] == nil {
                eventStates[eventId] = .optimistic
                events.append(event)
                return true
            }
            return false
            
        case .relay(let relay):
            // For relay events, check if we've seen this before
            if let existingState = eventStates[eventId] {
                if case .optimistic = existingState {
                    // Upgrade from optimistic to confirmed
                    eventStates[eventId] = .confirmed(fromRelay: relay.url)
                    return false // Don't add to events again
                }
                return false // Already confirmed
            } else {
                // New confirmed event
                eventStates[eventId] = .confirmed(fromRelay: relay.url)
                events.append(event)
                return true
            }
            
        case .cache:
            // For cache events, add if not already seen
            if eventStates[eventId] == nil {
                eventStates[eventId] = .confirmed(fromRelay: "cache")
                events.append(event)
                return true
            }
            return false
        }
    }
    
    func getEventConfirmationState(eventId: EventID) -> EventConfirmationState? {
        return eventStates[eventId]
    }
    
    func getEvents() -> [NDKEvent] {
        return events
    }
    
    func getEventCount() -> Int {
        return events.count
    }
    
    func updateCount(_ count: Int, from relay: RelayProtocol?) {
        let relayUrl = relay?.url ?? "unknown"
        countResults[relayUrl] = count
    }
    
    func getCountResults() -> [String: Int] {
        return countResults
    }
    
    // Accessors for mutable properties
    func getOptions() -> NDKSubscriptionOptions {
        return options
    }
    
    func updateOptions(_ newOptions: NDKSubscriptionOptions) {
        self.options = newOptions
    }
    
    func getNDK() -> NDK? {
        return ndk
    }
    
    func getContinuation() -> AsyncThrowingStream<NDKEvent, Error>.Continuation? {
        return continuation
    }
    
    func setContinuation(_ newContinuation: AsyncThrowingStream<NDKEvent, Error>.Continuation?) {
        self.continuation = newContinuation
    }
    
    func setTimeoutTask(_ task: Task<Void, Never>?) {
        timeoutTask?.cancel()
        timeoutTask = task
    }
    
    func setRegistrationTask(_ task: Task<Void, Never>?) {
        registrationTask = task
    }
    
    func cancelTimeoutTask() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
    
    func finishContinuation() {
        continuation?.finish()
        continuation = nil
    }
    
    var currentState: NDKSubscriptionState { state }
    var isActive: Bool { state == .active }
    var isClosed: Bool { state == .closed }
    var eoseReceived: Bool { hasReceivedEOSE }
}

/// Simplified subscription options
public struct NDKSubscriptionOptions: Sendable {
    /// Whether to close the subscription on EOSE
    public var closeOnEose: Bool = false
    
    /// Use cache for initial events
    public var useCache: Bool = true
    
    /// Maximum number of events to receive
    public var limit: Int?
    
    /// Timeout for the subscription
    public var timeout: TimeInterval?
    
    /// Specific relays to use for this subscription
    public var relays: Set<NDKRelay>?
    
    /// Whether to skip optimistic events from local publishing
    public var skipOptimisticEvents: Bool = false
    
    public init() {}
}

/// Simplified subscription implementation
/// 
/// ## Usage Pattern
/// 
/// NDKSubscription conforms to AsyncSequence, making it easy to consume events:
/// 
/// ```swift
/// let subscription = ndk.subscribe(filters: [filter])
/// 
/// do {
///     for try await event in subscription {
///         // Process event
///     }
/// } catch {
///     // Handle subscription errors
///     print("Subscription failed: \(error)")
/// }
/// ```
/// 
/// ## Resource Management
/// 
/// **Important**: Subscriptions must be explicitly closed to free server resources. 
/// If you let a subscription go out of scope without calling `close()`, it will 
/// remain active on the relays.
/// 
/// ### Recommended Pattern with Task:
/// 
/// ```swift
/// let subscriptionTask = Task {
///     let subscription = ndk.subscribe(filters: [filter])
///     defer {
///         // Ensure close is called when task completes or is cancelled
///         Task { await subscription.close() }
///     }
///     
///     do {
///         for try await event in subscription {
///             // Process events
///         }
///     } catch {
///         // Handle errors
///     }
/// }
/// 
/// // Later, to stop the subscription:
/// subscriptionTask.cancel()
/// ```
/// 
/// ### Manual Management:
/// 
/// ```swift
/// let subscription = ndk.subscribe(filters: [filter])
/// 
/// // Process events...
/// 
/// // Always close when done
/// await subscription.close()
/// ```
public final class NDKSubscription: AsyncSequence, Sendable {
    public typealias Element = NDKEvent
    
    /// Unique subscription ID
    public let id: String
    
    /// Filters for this subscription
    public let filters: [NDKFilter]
    
    /// Thread-safe state management
    internal let stateActor: SubscriptionStateActor
    
    /// The async stream of events
    private let stream: AsyncThrowingStream<NDKEvent, Error>
    
    // All state is now async-only for thread safety
    public var isActive: Bool {
        get async { await stateActor.isActive }
    }
    
    public var isClosed: Bool {
        get async { await stateActor.isClosed }
    }
    
    public var eoseReceived: Bool {
        get async { await stateActor.eoseReceived }
    }
    
    public var events: [NDKEvent] {
        get async { await stateActor.getEvents() }
    }
    
    /// Count results from relays (NIP-45)
    public var countResults: [String: Int] {
        get async { await stateActor.getCountResults() }
    }
    
    /// Current subscription state (public read-only)
    public var state: NDKSubscriptionState {
        get async { await stateActor.currentState }
    }
    
    /// Subscription options
    public var options: NDKSubscriptionOptions {
        get async { await stateActor.getOptions() }
    }
    
    /// Reference to NDK instance
    public var ndk: NDK? {
        get async { await stateActor.getNDK() }
    }

    public init(
        id: String? = nil,
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        ndk: NDK? = nil
    ) {
        self.id = id ?? "sub_\(Int.random(in: 100000...999999))"
        self.filters = filters
        
        // Initialize the state actor with the options and ndk
        self.stateActor = SubscriptionStateActor(options: options, ndk: ndk)
        
        // Create the event stream with proper cleanup
        var streamContinuation: AsyncThrowingStream<NDKEvent, Error>.Continuation?
        self.stream = AsyncThrowingStream<NDKEvent, Error> { continuation in
            streamContinuation = continuation
            continuation.onTermination = { _ in
                // Clean up when stream is terminated
            }
        }
        
        // Store continuation in the actor
        Task {
            await self.stateActor.setContinuation(streamContinuation)
            await self.setupTimeoutIfNeeded()
        }
    }

    deinit {
        // Clean up synchronously to avoid Task creation during deallocation
        Task.detached { [stateActor] in
            await stateActor.cancelTimeoutTask()
            await stateActor.finishContinuation()
        }
    }

    // MARK: - AsyncSequence Conformance
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncThrowingStream<NDKEvent, Error>.AsyncIterator
        
        init(iterator: AsyncThrowingStream<NDKEvent, Error>.AsyncIterator) {
            self.iterator = iterator
        }
        
        public mutating func next() async throws -> NDKEvent? {
            try await iterator.next()
        }
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        // Auto-start subscription when iteration begins
        Task {
            let currentState = await stateActor.currentState
            if currentState == .pending {
                await start()
            }
        }
        return AsyncIterator(iterator: stream.makeAsyncIterator())
    }

    // MARK: - Subscription Control
    
    /// Wait for EOSE to be received from all relays
    public func waitForEOSE() async {
        while await !self.eoseReceived {
            try? await Task.sleep(nanoseconds: 100_000_000) // Sleep 100ms
        }
    }

    /// Start the subscription
    public func start() async {
        let shouldStart = await stateActor.transitionToActive()
        guard shouldStart else { return }
        
        let options = await stateActor.getOptions()
        
        // Start with cache if needed
        if options.useCache {
            await checkCache()
        }
        
        // Query relays
        await queryRelays()
    }
    
    /// Update the relays for this subscription (used by outbox model)
    public func updateRelays(_ newRelays: Set<NDKRelay>) async {
        // Get current options from actor
        var newOptions = await stateActor.getOptions()
        newOptions.relays = newRelays
        await stateActor.updateOptions(newOptions)
        
        // If already active, query the new relays
        if await stateActor.isActive {
            await queryRelays()
        }
    }

    /// Close the subscription
    public func close() async {
        let (shouldClose, relays) = await stateActor.transitionToClosed()
        guard shouldClose else { return }
        
        // Close on all active relays
        for relay in relays {
            await relay.subscriptionManager.removeSubscription(id)
            await relay.removeSubscription(byId: id)
        }
        
        // Complete the stream (done in the actor)
        await stateActor.finishContinuation()
    }

    // MARK: - Cache Handling

    private func checkCache() async {
        guard let ndk = await stateActor.getNDK(), let cache = ndk.cache else { return }
        
        var cachedEvents: [NDKEvent] = []
        for filter in filters {
            if let events = try? await cache.queryEvents(filter) {
                cachedEvents.append(contentsOf: events)
            }
        }
        
        for event in cachedEvents {
            await handleEvent(event, from: .cache)
        }
    }

    // MARK: - Relay Handling

    private func queryRelays() async {
        guard let ndk = await stateActor.getNDK() else { return }
        
        let options = await stateActor.getOptions()
        let ndkRelays = await ndk.relays
        let relaysToUse = options.relays ?? Set(ndkRelays)
        
        for relay in relaysToUse {
            await stateActor.addRelay(relay)
            // Note: The main subscription manager handles the actual subscription
        }
    }

    // MARK: - Event Handling

    /// Handle an event received from a relay (backwards compatibility)
    public func handleEvent(_ event: NDKEvent, fromRelay relay: RelayProtocol?) async {
        let source: EventSource = relay != nil ? .relay(relay!) : .cache
        await handleEvent(event, from: source)
    }
    
    /// Handle an event with source information
    public func handleEvent(_ event: NDKEvent, from source: EventSource) async {
        guard await stateActor.currentState != .closed else { return }
        
        // Check if subscription wants to skip optimistic events
        let options = await stateActor.getOptions()
        if case .optimistic = source, options.skipOptimisticEvents {
            return
        }
        
        // Check if event matches our filters
        var matchesAny = false
        for filter in filters {
            if await filter.matches(event: event) {
                matchesAny = true
                break
            }
        }
        guard matchesAny else {
            return
        }
        
        // Use actor for thread-safe deduplication and storage
        let wasAdded = await stateActor.addEventIfNotSeen(event, from: source)
        guard wasAdded else { return } // Already seen or just confirmed
        
        let currentEventCount = await stateActor.getEventCount()
        
        // Store in cache if available (only for confirmed events)
        if case .relay = source, let ndk = await stateActor.getNDK(), let cache = ndk.cache {
            try? await cache.saveEvent(event)
        }
        
        // Send event to stream
        if let continuation = await stateActor.getContinuation() {
            continuation.yield(event)
        }
        
        // Check limit
        if let limit = options.limit, currentEventCount >= limit {
            await close()
        }
    }

    /// Handle EOSE (End of Stored Events)
    public func handleEOSE(fromRelay relay: RelayProtocol? = nil) async {
        let ndk = await stateActor.getNDK()
        let options = await stateActor.getOptions()
        
        let expectedRelays: Set<NDKRelay>
        if let relays = options.relays {
            expectedRelays = relays
        } else if let ndk = ndk {
            expectedRelays = Set(await ndk.relays)
        } else {
            expectedRelays = Set([])
        }
        
        let shouldComplete = await stateActor.handleEOSE(
            fromRelay: relay,
            expectedRelays: expectedRelays
        )
        
        if shouldComplete && options.closeOnEose {
            await close()
        }
    }

    /// Handle subscription error
    public func handleError(_ error: Error) {
        Task {
            // Log if debug mode
            if let ndk = await stateActor.getNDK(), ndk.debugMode {
                print("❌ Subscription error: \(error)")
            }
            
            // Propagate error through stream and close
            if let continuation = await stateActor.getContinuation() {
                continuation.finish(throwing: error)
            }
            await close()
        }
    }
    
    /// Handle COUNT message from relay (NIP-45)
    public func handleCount(_ count: Int, fromRelay relay: RelayProtocol? = nil) async {
        // Store count result
        await stateActor.updateCount(count, from: relay)
        
        // Log if debug mode
        if let ndk = await stateActor.getNDK(), ndk.debugMode {
            let relayInfo = relay.map { " from \($0.url)" } ?? ""
            print("🔢 Received count: \(count)\(relayInfo)")
        }
    }

    // MARK: - Private Helpers

    private func setupTimeoutIfNeeded() async {
        let options = await stateActor.getOptions()
        guard let timeout = options.timeout else { return }
        
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            
            // If the task wasn't cancelled, the timeout was reached
            if !Task.isCancelled {
                await self?.close()
            }
        }
        
        await stateActor.setTimeoutTask(timeoutTask)
    }
}

// MARK: - Equatable & Hashable

extension NDKSubscription: Equatable, Hashable {
    public static func == (lhs: NDKSubscription, rhs: NDKSubscription) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
