import XCTest
@testable import NDKSwift

final class NDKListBlacklistTests: XCTestCase {
    
    func testMuteListMintBlacklisting() {
        // Create a mute list (kind 10000)
        let muteList = NDKList(kind: EventKind.muteList)
        
        // Add some mint URLs
        muteList.tags = [
            ["r", "https://mint1.example.com"],
            ["r", "https://cashu-mint.example.com"],
            ["r", "https://fedimint.example.com"],
            ["p", "somepubkey123"], // Non-mint entry
            ["r", "https://relay.example.com"] // Non-mint URL
        ]
        
        // Test isMintBlacklisted
        XCTAssertTrue(muteList.isMintBlacklisted("https://mint1.example.com"))
        XCTAssertTrue(muteList.isMintBlacklisted("https://cashu-mint.example.com"))
        XCTAssertTrue(muteList.isMintBlacklisted("https://fedimint.example.com"))
        XCTAssertFalse(muteList.isMintBlacklisted("https://unknownmint.example.com"))
        
        // Test blacklistedMints
        let blacklistedMints = muteList.blacklistedMints
        XCTAssertEqual(blacklistedMints.count, 3)
        XCTAssertTrue(blacklistedMints.contains("https://mint1.example.com"))
        XCTAssertTrue(blacklistedMints.contains("https://cashu-mint.example.com"))
        XCTAssertTrue(blacklistedMints.contains("https://fedimint.example.com"))
    }
    
    func testBlockedRelaysList() {
        // Create a blocked relays list (kind 10006)
        let blockedRelaysList = NDKList(kind: EventKind.blockedRelays)
        
        // Add some relay URLs
        blockedRelaysList.tags = [
            ["r", "wss://relay1.example.com"],
            ["r", "wss://relay2.example.com/"],
            ["r", "WSS://RELAY3.EXAMPLE.COM"], // Test case insensitivity
            ["p", "somepubkey123"] // Non-relay entry
        ]
        
        // Test isRelayBlocked with normalization
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay1.example.com"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay1.example.com/")) // With trailing slash
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay2.example.com"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay3.example.com")) // Case insensitive
        XCTAssertFalse(blockedRelaysList.isRelayBlocked("wss://notblocked.example.com"))
        
        // Test blockedRelays
        let blockedRelays = blockedRelaysList.blockedRelays
        XCTAssertEqual(blockedRelays.count, 3)
        XCTAssertTrue(blockedRelays.contains("wss://relay1.example.com"))
        XCTAssertTrue(blockedRelays.contains("wss://relay2.example.com/"))
        XCTAssertTrue(blockedRelays.contains("WSS://RELAY3.EXAMPLE.COM"))
    }
    
    func testNonBlacklistLists() {
        // Test that non-blacklist lists return empty results
        let contactList = NDKList(kind: EventKind.contacts)
        contactList.tags = [
            ["r", "https://mint1.example.com"],
            ["r", "wss://relay1.example.com"]
        ]
        
        // Should return false/empty for blacklist checks
        XCTAssertFalse(contactList.isMintBlacklisted("https://mint1.example.com"))
        XCTAssertFalse(contactList.isRelayBlocked("wss://relay1.example.com"))
        XCTAssertTrue(contactList.blacklistedMints.isEmpty)
        XCTAssertTrue(contactList.blockedRelays.isEmpty)
    }
    
    func testRelayURLNormalization() {
        let blockedRelaysList = NDKList(kind: EventKind.blockedRelays)
        blockedRelaysList.tags = [
            ["r", "wss://relay.example.com"] // Without trailing slash
        ]
        
        // All these variations should be considered blocked
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay.example.com"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("wss://relay.example.com/"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("WSS://RELAY.EXAMPLE.COM"))
        XCTAssertTrue(blockedRelaysList.isRelayBlocked("WSS://RELAY.EXAMPLE.COM/"))
    }
}