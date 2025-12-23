@testable import NDKSwiftCore
import XCTest

/// Integration tests for subscription grouping API
/// Note: Full REQ message batching tests would require mock relays
@MainActor
final class SubscriptionGroupingIntegrationTests: XCTestCase {
    private var ndk: NDK!

    override func setUp() async throws {
        try await super.setUp()

        // Create NDK instance with in-memory cache
        ndk = NDK()
    }

    override func tearDown() async throws {
        await ndk.disconnect()
        ndk = nil
        try await super.tearDown()
    }

    /// Test creating subscriptions with default options
    func testDefaultSubscriptionOptions() async throws {
        let filter = NDKFilter(kinds: [1])

        // Create subscription with default options
        let subscription = ndk.subscribe(filter: filter)

        // Verify subscription is created
        XCTAssertNotNil(subscription)

        // The subscription should start with empty data
        XCTAssertTrue(subscription.data.isEmpty)
    }

    /// Test creating subscriptions with custom options
    func testCustomSubscriptionOptions() async throws {
        let filter = NDKFilter(kinds: [1])

        // Create custom options
        var options = NDKSubscriptionOptions()
        options.groupable = false
        options.groupableDelay = 0.5
        options.groupableDelayType = .atLeast

        // Create subscription with custom options
        let subscription = ndk.subscribe(filter: filter, options: options)

        // Verify subscription is created
        XCTAssertNotNil(subscription)
    }

    /// Test creating multiple subscriptions with same filter
    func testMultipleSubscriptionsWithSameFilter() async throws {
        let filter = NDKFilter(authors: ["alice"], kinds: [1])

        // Create multiple subscriptions
        let sub1 = ndk.subscribe(filter: filter)
        let sub2 = ndk.subscribe(filter: filter)
        let sub3 = ndk.subscribe(filter: filter)

        // All subscriptions should be created
        XCTAssertNotNil(sub1)
        XCTAssertNotNil(sub2)
        XCTAssertNotNil(sub3)

        // Each subscription should have its own stream
        XCTAssertTrue(sub1 !== sub2)
        XCTAssertTrue(sub2 !== sub3)
    }

    /// Test NDKSubscriptionOptions default values
    func testSubscriptionOptionsDefaults() async throws {
        let options = NDKSubscriptionOptions()

        // Verify default values
        XCTAssertEqual(options.maxAge, 0)
        XCTAssertEqual(options.cachePolicy, .cacheWithNetwork)
        XCTAssertNil(options.relays)
        XCTAssertFalse(options.exclusiveRelays)
        XCTAssertNil(options.subscriptionId)
        XCTAssertNil(options.closeOnEose)
        XCTAssertTrue(options.groupable)
        XCTAssertNil(options.groupableDelay)
        XCTAssertNil(options.groupableDelayType)
    }

    /// Test NDKSubscriptionOptions static defaults
    func testSubscriptionOptionsStaticDefaults() async throws {
        let defaultOptions = NDKSubscriptionOptions.default
        XCTAssertEqual(defaultOptions.cachePolicy, .cacheWithNetwork)

        let cacheOnlyOptions = NDKSubscriptionOptions.cacheOnly
        XCTAssertEqual(cacheOnlyOptions.cachePolicy, .cacheOnly)

        let networkOnlyOptions = NDKSubscriptionOptions.networkOnly
        XCTAssertEqual(networkOnlyOptions.cachePolicy, .networkOnly)
    }

    /// Test subscription with options initializer
    func testSubscriptionWithOptionsInitializer() async throws {
        let filter = NDKFilter(kinds: [1])
        var options = NDKSubscriptionOptions()
        options.maxAge = 300
        options.cachePolicy = .cacheOnly
        options.groupable = false

        // Create subscription using the options initializer
        let subscription = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            options: options
        )

        // Verify subscription is created
        XCTAssertNotNil(subscription)
    }

    /// Test that NDKSubscriptionDelayType is public
    func testDelayTypeIsPublic() async throws {
        // This test verifies that NDKSubscriptionDelayType is public
        let delayType1: NDKSubscriptionDelayType = .atLeast
        let delayType2: NDKSubscriptionDelayType = .atMost

        XCTAssertNotEqual(delayType1, delayType2)
    }
}
