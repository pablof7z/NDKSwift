import Foundation
@testable import NDKSwift

// MARK: - MockCache

/// A comprehensive mock implementation of NDKCacheAdapter for testing
/// Provides tracking of method calls and configurable behavior
class MockCache: NDKCacheAdapter {
    // Storage
    var events = [EventID: NDKEvent]()
    var profiles = [PublicKey: NDKUserProfile]()
    var mockEvents = [NDKEvent]()  // Pre-configured events for testing
    var nip05Data = [String: (pubkey: PublicKey, relays: [String])]()
    var relayStatuses = [RelayURL: NDKRelayConnectionState]()
    var unpublishedEvents = [RelayURL: [NDKEvent]]()
    
    // Method call tracking
    var queryCalled = false
    var setEventCalled = false
    var fetchProfileCalled = false
    var saveProfileCalled = false
    var loadNip05Called = false
    var saveNip05Called = false
    var updateRelayStatusCalled = false
    var getRelayStatusCalled = false
    var addUnpublishedEventCalled = false
    var getUnpublishedEventsCalled = false
    var removeUnpublishedEventCalled = false
    
    // Behavior configuration
    var shouldFailQuery = false
    var queryDelay: TimeInterval?
    
    // Protocol implementation
    var locking: Bool = false
    var ready: Bool = true
    
    func query(subscription: NDKSubscription) async -> [NDKEvent] {
        queryCalled = true
        
        if let delay = queryDelay {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        if shouldFailQuery {
            return []
        }
        
        // Return pre-configured mock events if available
        if !mockEvents.isEmpty {
            return mockEvents.filter { event in
                subscription.filters.contains { filter in
                    filter.matches(event: event)
                }
            }
        }
        
        // Otherwise filter stored events
        return events.values.filter { event in
            subscription.filters.contains { filter in
                filter.matches(event: event)
            }
        }
    }
    
    func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay: NDKRelay?) async {
        setEventCalled = true
        events[event.id] = event
    }
    
    func fetchProfile(pubkey: PublicKey) async -> NDKUserProfile? {
        fetchProfileCalled = true
        return profiles[pubkey]
    }
    
    func saveProfile(pubkey: PublicKey, profile: NDKUserProfile) async {
        saveProfileCalled = true
        profiles[pubkey] = profile
    }
    
    func loadNip05(_ nip05: String) async -> (pubkey: PublicKey, relays: [String])? {
        loadNip05Called = true
        return nip05Data[nip05]
    }
    
    func saveNip05(_ nip05: String, pubkey: PublicKey, relays: [String]) async {
        saveNip05Called = true
        nip05Data[nip05] = (pubkey: pubkey, relays: relays)
    }
    
    func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async {
        updateRelayStatusCalled = true
        relayStatuses[url] = status
    }
    
    func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState? {
        getRelayStatusCalled = true
        return relayStatuses[url]
    }
    
    func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {
        addUnpublishedEventCalled = true
        for url in relayUrls {
            if unpublishedEvents[url] == nil {
                unpublishedEvents[url] = []
            }
            unpublishedEvents[url]?.append(event)
        }
    }
    
    func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] {
        getUnpublishedEventsCalled = true
        return unpublishedEvents[relayUrl] ?? []
    }
    
    func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {
        removeUnpublishedEventCalled = true
        unpublishedEvents[relayUrl]?.removeAll { $0.id == eventId }
    }
    
    // Helper methods
    func reset() {
        events.removeAll()
        profiles.removeAll()
        mockEvents.removeAll()
        nip05Data.removeAll()
        relayStatuses.removeAll()
        unpublishedEvents.removeAll()
        
        queryCalled = false
        setEventCalled = false
        fetchProfileCalled = false
        saveProfileCalled = false
        loadNip05Called = false
        saveNip05Called = false
        updateRelayStatusCalled = false
        getRelayStatusCalled = false
        addUnpublishedEventCalled = false
        getUnpublishedEventsCalled = false
        removeUnpublishedEventCalled = false
        
        shouldFailQuery = false
        queryDelay = nil
    }
    
    func clear() async {
        reset()
    }
}

// MARK: - MockRelay

enum MockRelayMode {
    case simple              // Just tracks sent messages
    case messageTracking     // Tracks and parses messages
    case fullResponse       // Simulates full relay responses
}

class MockRelay: NDKRelay {
    // Storage
    var mockEvents: [NDKEvent] = []
    var sentMessages: [String] = []
    var receivedFilters: [NDKFilter] = []
    var activeSubscriptions: [String: [NDKFilter]] = [:]
    
    // Configuration
    var mode: MockRelayMode = .simple
    var shouldFailConnection = false
    var shouldDisconnect = false
    var shouldFailPublish = false
    var autoRespond = true
    var simulateEOSE = true
    
    // Callbacks
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onSend: ((String) -> Void)?
    
    // Response handling for full mode
    var customEventResponses: [String: [NDKEvent]] = [:]  // subscriptionId -> events
    var responseDelay: TimeInterval?
    
    convenience init(url: String, mode: MockRelayMode = .simple) {
        self.init(url: url)
        self.mode = mode
    }
    
    override func connect() async throws {
        if shouldFailConnection {
            throw NDKError.relayConnectionFailed(url: url)
        }
        if shouldDisconnect {
            throw NDKError.relayDisconnected
        }
        
        connectionState = .connected
        onConnect?()
    }
    
    override func disconnect() async {
        connectionState = .disconnected
        onDisconnect?()
    }
    
    override func send(_ message: String) async throws {
        sentMessages.append(message)
        onSend?(message)
        
        guard mode != .simple else { return }
        
        // Parse the message
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let command = json.first as? String else {
            return
        }
        
        switch command {
        case "REQ":
            await handleREQ(json: json)
        case "EVENT":
            await handleEVENT(json: json)
        case "CLOSE":
            await handleCLOSE(json: json)
        default:
            break
        }
    }
    
    private func handleREQ(json: [Any]) async {
        guard json.count >= 3,
              let subscriptionId = json[1] as? String else { return }
        
        var filters: [NDKFilter] = []
        
        // Parse filters
        for i in 2..<json.count {
            if let filterDict = json[i] as? [String: Any] {
                var filter = NDKFilter()
                if let ids = filterDict["ids"] as? [String] {
                    filter.ids = ids
                }
                if let authors = filterDict["authors"] as? [String] {
                    filter.authors = authors
                }
                if let kinds = filterDict["kinds"] as? [Int] {
                    filter.kinds = kinds
                }
                if let since = filterDict["since"] as? Int64 {
                    filter.since = since
                }
                if let until = filterDict["until"] as? Int64 {
                    filter.until = until
                }
                if let limit = filterDict["limit"] as? Int {
                    filter.limit = limit
                }
                
                // Parse tag filters
                for (key, value) in filterDict {
                    if key.hasPrefix("#") {
                        let tagName = String(key.dropFirst())
                        if let tagValues = value as? [String] {
                            filter.addTagFilter(tagName, values: tagValues)
                        }
                    }
                }
                
                filters.append(filter)
            }
        }
        
        receivedFilters.append(contentsOf: filters)
        activeSubscriptions[subscriptionId] = filters
        
        guard mode == .fullResponse && autoRespond else { return }
        
        // Add response delay if configured
        if let delay = responseDelay {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Send custom responses if configured
        if let customEvents = customEventResponses[subscriptionId] {
            for event in customEvents {
                ndk?.processEvent(event, from: self)
            }
        } else {
            // Send matching mock events
            for event in mockEvents {
                if matchesAnyFilter(event: event, filters: filters) {
                    ndk?.processEvent(event, from: self)
                }
            }
        }
        
        // Send EOSE if configured
        if simulateEOSE {
            ndk?.processEOSE(subscriptionId: subscriptionId, from: self)
        }
    }
    
    private func handleEVENT(json: [Any]) async {
        guard json.count >= 2 else { return }
        // Event publishing is handled by publish() method
    }
    
    private func handleCLOSE(json: [Any]) async {
        guard json.count >= 2,
              let subscriptionId = json[1] as? String else { return }
        
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }
    
    override func publish(_ event: NDKEvent) async throws {
        if shouldFailPublish {
            throw NDKError.custom("Publish failed")
        }
        
        mockEvents.append(event)
        
        // Simulate OK response in full mode
        if mode == .fullResponse && autoRespond {
            // In a real implementation, this would send OK response
        }
    }
    
    private func matchesAnyFilter(event: NDKEvent, filters: [NDKFilter]) -> Bool {
        return filters.contains { $0.matches(event: event) }
    }
    
    // Helper methods
    func reset() {
        mockEvents.removeAll()
        sentMessages.removeAll()
        receivedFilters.removeAll()
        activeSubscriptions.removeAll()
        customEventResponses.removeAll()
        
        shouldFailConnection = false
        shouldDisconnect = false
        shouldFailPublish = false
        autoRespond = true
        simulateEOSE = true
        responseDelay = nil
        
        onConnect = nil
        onDisconnect = nil
        onSend = nil
    }
    
    func addMockResponse(subscriptionId: String, events: [NDKEvent]) {
        customEventResponses[subscriptionId] = events
    }
}

// MARK: - MockSigner

class MockSigner: NDKSigner {
    let publicKey: String
    let privateKey: String?
    var shouldFailSigning = false
    
    init(publicKey: String = "test_pubkey", privateKey: String? = "test_privkey") {
        self.publicKey = publicKey
        self.privateKey = privateKey
    }
    
    func sign(event: inout NDKEvent) async throws {
        if shouldFailSigning {
            throw NDKError.signingFailed
        }
        event.pubkey = publicKey
        event.sig = "mock_signature_\(event.id)"
    }
    
    func encrypt(message: String, recipientPublicKey: String) async throws -> String {
        return "encrypted_\(message)"
    }
    
    func decrypt(message: String, senderPublicKey: String) async throws -> String {
        if message.hasPrefix("encrypted_") {
            return String(message.dropFirst("encrypted_".count))
        }
        return message
    }
}

// MARK: - MockDelegate

class MockEventDelegate: NDKEventDelegate {
    var receivedEvents: [NDKEvent] = []
    var verifiedEvents: [NDKEvent] = []
    
    func event(_ event: NDKEvent, didVerifySignature verified: Bool) {
        if verified {
            verifiedEvents.append(event)
        }
    }
    
    func eventReceived(_ event: NDKEvent) {
        receivedEvents.append(event)
    }
}

// MARK: - Mock WebSocket for Relay Testing

class MockWebSocketTask {
    var isCancelled = false
    
    func cancel() {
        isCancelled = true
    }
}