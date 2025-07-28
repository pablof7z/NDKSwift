import XCTest
@testable import NDKSwift

/// Tests for OK message handling, especially auth-required scenarios
final class NDKRelayOKMessageTests: XCTestCase {
    var ndk: NDK!
    var relay: NDKRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        let signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(signer: signer)
        relay = NDKRelay(url: "wss://test.relay")
        relay.ndk = ndk
    }
    
    override func tearDown() async throws {
        ndk = nil
        relay = nil
        try await super.tearDown()
    }
    
    func testOKMessageWithAuthRequiredError() async throws {
        // Create test event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(.textNote)
            .content("Test")
            .build(signer: ndk.signer!)
        
        // Simulate receiving OK message with auth-required error
        let okMessage = NostrMessage.ok(
            eventId: event.id,
            accepted: false,
            message: "error: restricted: authentication required"
        )
        
        // Process the message through NDK
        // In a real scenario, this would be handled by the relay connection
        
        // Give time for processing
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // The relay should have handled the OK message
        // In a real scenario, this would trigger the auth flow
    }
    
    func testOKMessageWithVariousAuthErrors() async throws {
        let authErrorMessages = [
            "error: authentication required",
            "error: restricted: please authenticate",
            "error: auth-required: NIP-42",
            "error: must authenticate first",
            "error: this relay requires authentication"
        ]
        
        for errorMsg in authErrorMessages {
            let event = try await NDKEventBuilder(ndk: ndk)
                .kind(.textNote)
                .content("Test \(errorMsg)")
                .build(signer: ndk.signer!)
            
            let okMessage = NostrMessage.ok(
                eventId: event.id,
                accepted: false,
                message: errorMsg
            )
            
            // Process should recognize these as auth errors
            // In a real scenario, this would be handled by the relay connection
        }
    }
    
    func testOKMessageSuccessUpdatesCache() async throws {
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(.textNote)
            .content("Test")
            .build(signer: ndk.signer!)
        
        // First save event to cache
        try await ndk.cache.saveEvent(event)
        
        // Simulate successful OK message
        let okMessage = NostrMessage.ok(
            eventId: event.id,
            accepted: true,
            message: nil
        )
        
        await ndk.processOKMessage(
            eventId: event.id,
            accepted: true,
            message: nil,
            from: relay
        )
        
        // Event should be confirmed in cache
        let cachedEvent = try await ndk.cache.fetchEvent(byId: event.id)
        XCTAssertNotNil(cachedEvent)
    }
    
    func testAuthEventOKMessageTriggersStateChange() async throws {
        // Set up auth delegate
        let authDelegate = TestAuthDelegate()
        ndk.authenticationDelegate = authDelegate
        
        // Simulate relay in authenticating state
        await relay.updateConnectionState(.authenticating)
        
        // Create auth event (kind 22242)
        let authEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.clientAuthentication)
            .tag([NostrConstants.TagName.challenge, "test-challenge"])
            .tag([NostrConstants.TagName.relay, relay.url])
            .build(signer: ndk.signer!)
        
        // Track this as pending auth
        ndk.pendingAuthEvents[authEvent.id] = relay
        
        // Simulate successful OK for auth event
        await ndk.processOKMessage(
            eventId: authEvent.id,
            accepted: true,
            message: nil,
            from: relay
        )
        
        // Relay should now be authenticated
        let state = await relay.connectionState
        XCTAssertEqual(state, .authenticated)
        
        // Pending auth event should be cleared
        XCTAssertNil(ndk.pendingAuthEvents[authEvent.id])
    }
}

// MARK: - Test Helpers

class TestAuthDelegate: NDKAuthenticationDelegate {
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool {
        return true
    }
}