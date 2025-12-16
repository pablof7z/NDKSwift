import XCTest
@testable import NDKSwiftCore

final class HintIndexIntegrationTests: XCTestCase {
    func test_ndk_hasHintIndex() async throws {
        let ndk = NDK()
        let hintIndex = await ndk.hintIndex
        XCTAssertNotNil(hintIndex)
    }

    func test_hintIndex_startsEmpty() async throws {
        let ndk = NDK()
        let count = await ndk.hintIndex.count
        XCTAssertEqual(count, 0)
    }

    func test_hintIndex_canRecordHints() async throws {
        let ndk = NDK()
        await ndk.hintIndex.recordHint(pubkey: "test_pubkey", relay: "wss://relay.example.com", source: .nip19)

        let hints = await ndk.hintIndex.hints(for: "test_pubkey")
        XCTAssertEqual(hints.count, 1)
    }
}
