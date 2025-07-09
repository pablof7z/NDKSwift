import XCTest
@testable import NDKSwift

final class NDKSubscriptionSendableTests: XCTestCase {
    
    func testSubscriptionIsSendable() async throws {
        // Create a subscription
        let filter = NDKFilter()
        filter.kinds = [1]
        filter.limit = 10
        
        let options = NDKSubscriptionOptions()
        let subscription = NDKSubscription(
            id: "test-sub",
            filters: [filter],
            options: options,
            ndk: nil
        )
        
        // Test that we can access properties asynchronously
        XCTAssertEqual(subscription.id, "test-sub")
        XCTAssertEqual(await subscription.isActive, false)
        XCTAssertEqual(await subscription.isClosed, false)
        XCTAssertEqual(await subscription.state, .pending)
        
        // Test that we can pass subscription across actor boundaries
        actor TestActor {
            func processSubscription(_ subscription: NDKSubscription) async -> (String, NDKSubscriptionState, Bool) {
                let id = subscription.id
                let state = await subscription.state
                let closeOnEose = await subscription.options.closeOnEose
                return (id, state, closeOnEose)
            }
        }
        
        let testActor = TestActor()
        let (id, state, closeOnEose) = await testActor.processSubscription(subscription)
        
        XCTAssertEqual(id, "test-sub")
        XCTAssertEqual(state, .pending)
        XCTAssertEqual(closeOnEose, false)
        
        // Test concurrent access
        await withTaskGroup(of: NDKSubscriptionState.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await subscription.state
                }
            }
            
            for await state in group {
                XCTAssertEqual(state, .pending)
            }
        }
    }
    
    func testSubscriptionOptionsAccess() async throws {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.useCache = false
        options.limit = 100
        
        let subscription = NDKSubscription(
            filters: [NDKFilter()],
            options: options
        )
        
        // Test async access to options
        let retrievedOptions = await subscription.options
        XCTAssertEqual(retrievedOptions.closeOnEose, true)
        XCTAssertEqual(retrievedOptions.useCache, false)
        XCTAssertEqual(retrievedOptions.limit, 100)
    }
    
    func testSubscriptionStateTransitions() async throws {
        let subscription = NDKSubscription(
            filters: [NDKFilter()],
            options: NDKSubscriptionOptions()
        )
        
        // Initial state
        XCTAssertEqual(await subscription.state, .pending)
        
        // Start subscription
        await subscription.start()
        XCTAssertEqual(await subscription.state, .active)
        
        // Close subscription
        await subscription.close()
        XCTAssertEqual(await subscription.state, .closed)
    }
}