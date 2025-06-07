import XCTest
@testable import NDKSwift

final class NDKFetchEventTests: XCTestCase {
    
    var ndk: NDK!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        ndk = NDK()
        mockRelay = MockRelay(url: "wss://test.relay")
        // Add mock relay to pool
        ndk.relayPool.relaysByUrl["wss://test.relay"] = mockRelay
    }
    
    override func tearDown() async throws {
        ndk = nil
        mockRelay = nil
    }
    
    // MARK: - Hex ID Tests
    
    func testFetchEventWithHexId() async throws {
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let mockEvent = NDKEvent(
            pubkey: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test event"
        )
        mockEvent.id = eventId
        
        // Set up mock relay to return the event
        mockRelay.mockEvents = [mockEvent]
        mockRelay.connectionState = .connected
        
        let fetchedEvent = try await ndk.fetchEvent(eventId, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, eventId)
        XCTAssertEqual(fetchedEvent?.content, "Test event")
    }
    
    // MARK: - Note Bech32 Tests
    
    func testFetchEventWithNoteBech32() async throws {
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let noteBech32 = try Bech32.note(from: eventId)
        
        let mockEvent = NDKEvent(
            pubkey: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test note event"
        )
        mockEvent.id = eventId
        
        mockRelay.mockEvents = [mockEvent]
        mockRelay.connectionState = .connected
        
        let fetchedEvent = try await ndk.fetchEvent(noteBech32, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, eventId)
        XCTAssertEqual(fetchedEvent?.content, "Test note event")
    }
    
    // MARK: - Nevent Bech32 Tests
    
    func testFetchEventWithNeventBech32() async throws {
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let neventBech32 = try Bech32.nevent(
            eventId: eventId,
            relays: ["wss://test.relay"],
            author: author,
            kind: 1
        )
        
        let mockEvent = NDKEvent(
            pubkey: author,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test nevent event"
        )
        mockEvent.id = eventId
        
        mockRelay.mockEvents = [mockEvent]
        mockRelay.connectionState = .connected
        
        let fetchedEvent = try await ndk.fetchEvent(neventBech32, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, eventId)
        XCTAssertEqual(fetchedEvent?.content, "Test nevent event")
    }
    
    // MARK: - Naddr Bech32 Tests
    
    func testFetchEventWithNaddrBech32() async throws {
        let identifier = "test-article"
        let kind = 30023
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let naddrBech32 = try Bech32.naddr(
            identifier: identifier,
            kind: kind,
            author: author,
            relays: ["wss://test.relay"]
        )
        
        let mockEvent = NDKEvent(
            pubkey: author,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [["d", identifier]],
            content: "Test article content"
        )
        mockEvent.id = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        
        mockRelay.mockEvents = [mockEvent]
        mockRelay.connectionState = .connected
        
        let fetchedEvent = try await ndk.fetchEvent(naddrBech32, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.pubkey, author)
        XCTAssertEqual(fetchedEvent?.kind, kind)
        XCTAssertEqual(fetchedEvent?.tags.first, ["d", identifier])
        XCTAssertEqual(fetchedEvent?.content, "Test article content")
    }
    
    // MARK: - Error Cases
    
    func testFetchEventWithInvalidHexId() async throws {
        let invalidId = "invalid"
        
        do {
            _ = try await ndk.fetchEvent(invalidId)
            XCTFail("Should have thrown an error")
        } catch NDKError.invalidInput(let message) {
            XCTAssertTrue(message.contains("64-character hex"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFetchEventWithUnsupportedBech32() async throws {
        let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let npubBech32 = try Bech32.npub(from: pubkey)
        
        do {
            _ = try await ndk.fetchEvent(npubBech32)
            XCTFail("Should have thrown an error")
        } catch NDKError.invalidInput(let message) {
            XCTAssertTrue(message.contains("Unsupported bech32 type"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFetchEventNotFound() async throws {
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        
        // Mock relay returns no events
        mockRelay.mockEvents = []
        mockRelay.connectionState = .connected
        
        let fetchedEvent = try await ndk.fetchEvent(eventId, relays: Set([mockRelay]))
        
        XCTAssertNil(fetchedEvent)
    }
}

// MARK: - Mock Relay for Testing

class MockRelay: NDKRelay {
    var mockEvents: [NDKEvent] = []
    var receivedFilters: [NDKFilter] = []
    
    override func send(_ message: String) async throws {
        // Parse the message to extract filters
        if let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
           json.first as? String == "REQ",
           json.count >= 3 {
            // Extract filters from REQ message
            for i in 2..<json.count {
                if let filterDict = json[i] as? [String: Any] {
                    // Simple filter reconstruction for testing
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
                    receivedFilters.append(filter)
                }
            }
            
            // Simulate returning matching events
            let subscriptionId = json[1] as? String ?? "test"
            for event in mockEvents {
                if matchesAnyFilter(event: event, filters: receivedFilters) {
                    // Simulate EVENT message
                    ndk?.processEvent(event, from: self)
                }
            }
            
            // Simulate EOSE
            ndk?.processEOSE(subscriptionId: subscriptionId, from: self)
        }
    }
    
    private func matchesAnyFilter(event: NDKEvent, filters: [NDKFilter]) -> Bool {
        for filter in filters {
            if let ids = filter.ids, ids.contains(event.id ?? "") {
                return true
            }
            if let authors = filter.authors, authors.contains(event.pubkey) {
                if let kinds = filter.kinds, kinds.contains(event.kind) {
                    // Check d-tag for addressable events
                    if let dTagValues = filter.tagFilter("d") {
                        for dTagValue in dTagValues {
                            if event.tags.contains(where: { $0.first == "d" && $0.count > 1 && $0[1] == dTagValue }) {
                                return true
                            }
                        }
                    } else {
                        return true
                    }
                }
            }
        }
        return false
    }
}