import XCTest
@testable import Olas
@testable import NDKSwift

final class FeedViewModelTests: XCTestCase {
    var ndk: NDK!

    override func setUp() async throws {
        ndk = NDK(relayUrls: [])
    }

    override func tearDown() async throws {
        await ndk.disconnect()
    }

    func testInitialStateIsEmpty() async {
        let viewModel = await FeedViewModel(ndk: ndk)

        await MainActor.run {
            XCTAssertTrue(viewModel.posts.isEmpty)
            XCTAssertFalse(viewModel.isLoading)
            XCTAssertNil(viewModel.error)
        }
    }

    func testPostsAreImageEvents() async {
        let viewModel = await FeedViewModel(ndk: ndk)

        await MainActor.run {
            XCTAssertEqual(viewModel.filter.kinds, [OlasConstants.EventKinds.image])
        }
    }
}
