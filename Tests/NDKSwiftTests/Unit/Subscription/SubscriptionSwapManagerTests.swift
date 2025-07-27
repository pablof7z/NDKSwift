import XCTest
@testable import NDKSwift

final class SubscriptionSwapManagerTests: XCTestCase {
    var manager: SubscriptionSwapManager!
    var ndk: NDK!
    var sessionData: NDKSessionData!
    
    override func setUp() async throws {
        manager = SubscriptionSwapManager.shared
        ndk = NDK()
        sessionData = NDKSessionData(pubkey: TestFixtures.Keys.alice.publicKey, ndk: ndk)
    }
    
    override func tearDown() async throws {
        // Clean up any tracked subscriptions
        ndk = nil
        sessionData = nil
    }
    
    // MARK: - Registration Tests
    
    func testRegisterSubscription() async {
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [1])
        )
        
        let reactiveFilter = ReactiveFilter(
            dependencies: [.followList],
            builder: { _ in NDKFilter(kinds: [1]) }
        )
        
        await manager.register(
            id: "test-sub-1",
            dataSource: dataSource,
            reactiveFilter: reactiveFilter,
            sessionData: sessionData
        )
        
        // Verify registration by unregistering without error
        await manager.unregister(id: "test-sub-1")
    }
    
    func testUnregisterSubscription() async {
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [1])
        )
        
        let reactiveFilter = ReactiveFilter(
            dependencies: [.followList],
            builder: { _ in NDKFilter(kinds: [1]) }
        )
        
        await manager.register(
            id: "test-sub-2",
            dataSource: dataSource,
            reactiveFilter: reactiveFilter,
            sessionData: sessionData
        )
        
        // Unregister should work without error
        await manager.unregister(id: "test-sub-2")
        
        // Unregistering again should not crash
        await manager.unregister(id: "test-sub-2")
    }
    
    // MARK: - WOT Configuration Tests
    
    func testWOTConfigurationHandling() async {
        let wotConfig = WOTConfiguration(minimumScore: 2, includeDirectFollows: true)
        
        let reactiveFilter = ReactiveFilter(
            dependencies: [.followList],
            wotConfig: wotConfig,
            builder: { sessionData in
                NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [1]
                )
            }
        )
        
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: reactiveFilter.builder(sessionData)
        )
        
        await manager.register(
            id: "wot-test",
            dataSource: dataSource,
            reactiveFilter: reactiveFilter,
            sessionData: sessionData
        )
        
        // TODO: Update follow list through proper event mechanism
        // For now, just test registration/unregistration with WOT config
        
        // Test passes if no crash occurs with WOT config
        await manager.unregister(id: "wot-test")
    }
    
    // MARK: - Multiple Subscription Tests
    
    func testMultipleSubscriptionsWithDifferentDependencies() async {
        // Subscription 1: Depends on follow list
        let dataSource1 = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [1])
        )
        let reactiveFilter1 = ReactiveFilter(
            dependencies: [.followList],
            builder: { _ in NDKFilter(kinds: [1]) }
        )
        
        // Subscription 2: No dependencies
        let dataSource2 = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [0])
        )
        let reactiveFilter2 = ReactiveFilter(
            dependencies: [],
            builder: { _ in NDKFilter(kinds: [0]) }
        )
        
        await manager.register(
            id: "sub-1",
            dataSource: dataSource1,
            reactiveFilter: reactiveFilter1,
            sessionData: sessionData
        )
        
        await manager.register(
            id: "sub-2",
            dataSource: dataSource2,
            reactiveFilter: reactiveFilter2,
            sessionData: sessionData
        )
        
        // TODO: Update follow list through proper event mechanism
        // For now, just test multiple registrations/unregistrations
        
        // Test passes if no crash occurs
        
        await manager.unregister(id: "sub-1")
        await manager.unregister(id: "sub-2")
    }
}