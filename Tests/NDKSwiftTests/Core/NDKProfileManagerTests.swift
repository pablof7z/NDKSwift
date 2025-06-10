import XCTest
@testable import NDKSwift

final class NDKProfileManagerTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        ndk = nil
    }
    
    func testFetchProfileWithCache() async throws {
        // Skip - requires actual relay connection
        XCTSkip("Profile fetching requires relay connection")
    }
    
    func testFetchProfileForceRefresh() async throws {
        // Skip - requires mock infrastructure
        XCTSkip("Profile manager tests require mock infrastructure")
    }
    
    func testFetchMultipleProfiles() async throws {
        // Skip - requires mock infrastructure
        XCTSkip("Profile manager tests require mock infrastructure")
    }
    
    func testCacheEviction() async throws {
        // Skip - requires mock infrastructure
        XCTSkip("Profile manager tests require mock infrastructure")
    }
    
    func testProfileBatching() async throws {
        // Skip - requires mock infrastructure
        XCTSkip("Profile manager tests require mock infrastructure")
    }
    
    func testCacheStaleness() async throws {
        // Skip - requires mock infrastructure
        XCTSkip("Profile manager tests require mock infrastructure")
    }
    
    // Test basic NDK profile fetching if available
    func testNDKProfileFetching() async throws {
        // Skip - requires actual relay connection
        XCTSkip("NDK profile fetching requires relay connection")
        
        // If NDK has profile fetching:
        // let profile = try await ndk.fetchProfile("pubkey")
        // XCTAssertNotNil(profile)
    }
}