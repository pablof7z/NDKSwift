import XCTest
@testable import NDKSwift

final class MintDiscoveryTests: XCTestCase {
    var ndk: NDK!
    var mintDiscovery: MintDiscovery!
    
    override func setUp() async throws {
        ndk = NDK()
        let wallet = NDKCashuWallet(ndk: ndk)
        mintDiscovery = wallet.mintDiscovery
    }
    
    override func tearDown() async throws {
        ndk = nil
        mintDiscovery = nil
    }
    
    // MARK: - Mint Announcement Tests
    
    func testMintAnnouncementEncoding() throws {
        let announcement = NDKMintAnnouncement(
            mintURL: URL(string: "https://mint.example.com")!,
            name: "Test Mint",
            description: "A test mint",
            descriptions: ["en": "English description", "es": "Descripción en español"],
            pubkey: "02a1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc",
            contact: [["email", "admin@mint.com"], ["nostr", "npub1..."]],
            motd: "Welcome to Test Mint",
            units: ["sat", "usd"],
            nuts: ["4": ["method": "bolt11"], "5": ["method": "bolt11"]],
            icon: URL(string: "https://mint.example.com/icon.png")
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(announcement)
        let json = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(json.contains("\"mint_url\""))
        XCTAssertTrue(json.contains("\"name\""))
        XCTAssertTrue(json.contains("\"units\""))
        
        // Test decoding
        let decoded = try JSONDecoder().decode(NDKMintAnnouncement.self, from: data)
        XCTAssertEqual(decoded.mintURL, announcement.mintURL)
        XCTAssertEqual(decoded.name, announcement.name)
        XCTAssertEqual(decoded.units, announcement.units)
    }
    
    func testMintAnnouncementEvent() async throws {
        let signer = NDKPrivateKeySigner.generate()
        let keypair = try await signer.keypair()
        
        let announcement = NDKMintAnnouncement(
            mintURL: URL(string: "https://mint.example.com")!,
            name: "Test Mint",
            units: ["sat"]
        )
        
        let event = try NDKEvent.mintAnnouncement(announcement: announcement, keypair: keypair)
        
        XCTAssertEqual(event.kind, EventKind.mintAnnouncement)
        XCTAssertTrue(event.tags.contains(where: { $0[0] == "u" && $0[1] == "https://mint.example.com" }))
        XCTAssertTrue(event.tags.contains(where: { $0[0] == "unit" && $0[1] == "sat" }))
        
        // Test parsing
        let parsed = try event.parseMintAnnouncement()
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.mintURL, announcement.mintURL)
        XCTAssertEqual(parsed?.name, announcement.name)
    }
    
    // MARK: - Suspicious Mint Detection Tests
    
    func testSuspiciousMintDetection() async throws {
        let testCases: [(URL, Bool, String)] = [
            (URL(string: "https://mint.example.com")!, false, "HTTPS mint should be OK"),
            (URL(string: "http://mint.example.com")!, true, "HTTP mint should be suspicious"),
            (URL(string: "https://localhost:3338")!, true, "Localhost should be suspicious"),
            (URL(string: "https://127.0.0.1:3338")!, true, "127.0.0.1 should be suspicious"),
            (URL(string: "https://192.168.1.100:3338")!, true, "Local network should be suspicious"),
            (URL(string: "https://10.0.0.1:3338")!, true, "Local network should be suspicious"),
            (URL(string: "https://mint.example.com:9999")!, true, "Uncommon port should be suspicious"),
            (URL(string: "https://mint.example.com:443")!, false, "Standard HTTPS port should be OK"),
            (URL(string: "https://mint.example.com:3338")!, false, "Standard Cashu port should be OK"),
        ]
        
        for (url, expectedSuspicious, message) in testCases {
            let isSuspicious = await mintDiscovery.isSuspiciousMint(url)
            XCTAssertEqual(isSuspicious, expectedSuspicious, message)
        }
    }
    
    // MARK: - Reputation Calculation Tests
    
    func testReputationScoring() async throws {
        // Create mock events with different levels of completeness
        let signer = NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Well-formed announcement
        let goodAnnouncement = NDKMintAnnouncement(
            mintURL: URL(string: "https://mint.example.com")!,
            name: "Good Mint",
            description: "A well-documented mint",
            pubkey: "02a1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc",
            contact: [["email", "admin@mint.com"]],
            units: ["sat"]
        )
        
        // Minimal announcement
        let minimalAnnouncement = NDKMintAnnouncement(
            mintURL: URL(string: "https://mint2.example.com")!
        )
        
        // Suspicious announcement
        let suspiciousAnnouncement = NDKMintAnnouncement(
            mintURL: URL(string: "http://192.168.1.100:9999")!,
            name: "Suspicious Mint"
        )
        
        // Test that well-formed announcements get higher scores
        // Note: We can't easily test the private calculateReputation method,
        // but we can test the overall discovery behavior
        
        // For now, just verify the announcements are created correctly
        XCTAssertNotNil(goodAnnouncement.name)
        XCTAssertNotNil(goodAnnouncement.pubkey)
        XCTAssertNotNil(goodAnnouncement.contact)
        
        XCTAssertNil(minimalAnnouncement.name)
        XCTAssertNil(minimalAnnouncement.description)
        
        let isSuspicious = await mintDiscovery.isSuspiciousMint(suspiciousAnnouncement.mintURL)
        XCTAssertTrue(isSuspicious)
    }
    
    // MARK: - Integration Tests
    
    func testMintDiscoveryWithMockRelay() async throws {
        // This would require setting up a mock relay to return test events
        // For now, we'll just test the basic structure
        
        let filter = NDKFilter(kinds: [EventKind.mintAnnouncement], limit: 10)
        XCTAssertEqual(filter.kinds, [EventKind.mintAnnouncement])
        XCTAssertEqual(filter.limit, 10)
        
        // Test unit filtering
        var unitFilter = NDKFilter(kinds: [EventKind.mintAnnouncement])
        unitFilter.tags = ["unit": ["sat", "usd"]]
        XCTAssertEqual(unitFilter.tags?["unit"], ["sat", "usd"])
    }
    
    func testMintAnnouncementTagParsing() async throws {
        let signer = NDKPrivateKeySigner.generate()
        let keypair = try await signer.keypair()
        
        let announcement = NDKMintAnnouncement(
            mintURL: URL(string: "https://mint.example.com:3338")!,
            name: "Multi-Unit Mint",
            units: ["sat", "usd", "eur"]
        )
        
        let event = try NDKEvent.mintAnnouncement(announcement: announcement, keypair: keypair)
        
        // Check all unit tags are present
        let unitTags = event.tags.filter { $0[0] == "unit" }.map { $0[1] }
        XCTAssertEqual(Set(unitTags), Set(["sat", "usd", "eur"]))
        
        // Check mint URL tag
        let urlTags = event.tags.filter { $0[0] == "u" }
        XCTAssertEqual(urlTags.count, 1)
        XCTAssertEqual(urlTags.first?[1], "https://mint.example.com:3338")
    }
}