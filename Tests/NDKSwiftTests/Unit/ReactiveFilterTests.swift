import XCTest
@testable import NDKSwiftCore

final class ReactiveFilterTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK with in-memory cache
        ndk = NDK(relayUrls: ["wss://relay.damus.io"], cache: MemoryCache())
        
        // Create test signer
        signer = try NDKPrivateKeySigner.generate()
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }
    
    func testReactiveFilterCreation() async throws {
        // Start session
        let sessionData = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .progressive
            )
        )
        
        XCTAssertNotNil(ndk.sessionData, "Session data should be stored on NDK instance")
        XCTAssertEqual(ndk.sessionData?.pubkey, sessionData.pubkey, "Session data should match")
        
        // Create reactive filter
        let expectation = XCTestExpectation(description: "Reactive filter should be created")
        
        let filter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                print("ReactiveFilter builder called with \(sessionData.followList.count) follows")
                expectation.fulfill()
                return NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [1],
                    limit: 10
                )
            }
        )
        
        // Observe with reactive filter
        let stream = ndk.observe(filter)
        
        // Try to consume some events
        Task {
            var eventCount = 0
            for await event in stream {
                eventCount += 1
                print("Received event: \(event.id)")
                if eventCount >= 1 {
                    break
                }
            }
        }
        
        // Wait for builder to be called
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testReactiveFilterWithEmptyFollowList() async throws {
        // Start session
        let sessionData = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .progressive
            )
        )
        
        // Verify empty follow list
        XCTAssertTrue(sessionData.followList.isEmpty, "New user should have empty follow list")
        
        // Create reactive filter
        let builderCalled = XCTestExpectation(description: "Builder should be called")
        
        let filter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                builderCalled.fulfill()
                // Return a filter that won't match anything
                return NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [1],
                    limit: 10
                )
            }
        )
        
        // Observe with reactive filter
        let stream = ndk.observe(filter)
        
        // Try to consume events
        Task {
            for await _ in stream {
                // Should not receive any events with empty follow list
                XCTFail("Should not receive events with empty follow list")
            }
            print("Stream ended as expected")
        }
        
        await fulfillment(of: [builderCalled], timeout: 2.0)
    }
}